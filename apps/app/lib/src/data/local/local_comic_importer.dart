import 'dart:io';
import 'dart:typed_data';

import 'package:yomu/src/data/local/archive_password_store.dart';
import 'package:yomu/src/data/local/comic_file_picker.dart';
import 'package:yomu/src/data/local/cover_thumbnail_generator.dart';
import 'package:yomu/src/data/local/local_archive_import_stream.dart';
import 'package:yomu/src/data/local/local_comic_importer_models.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';
import 'package:yomu_platform/yomu_platform.dart';

export 'package:yomu/src/data/local/local_comic_importer_models.dart';

/// 受管沙盒本地漫画导入管线（支持 CBZ/ZIP/EPUB/CBT/PDF 多选、图片页多选与文件夹导入，ADR 0009）。
final class LocalComicImporter {
  LocalComicImporter({
    required ProgressDatabase db,
    required LocalComicsStorage storage,
    CoverThumbnailEncoder coverEncoder = encodeDefaultCoverThumbnail,
    NativePdfBridge? pdfBridge,
    NativeArchiveBridge? archiveBridge,
    ArchivePasswordStore? passwordStore,
  }) : _db = db,
       _storage = storage,
       _coverEncoder = coverEncoder,
       _pdfBridge = pdfBridge,
       _archiveBridge = archiveBridge,
       _passwordStore = passwordStore;

  final ProgressDatabase _db;
  final LocalComicsStorage _storage;
  final CoverThumbnailEncoder _coverEncoder;
  final NativePdfBridge? _pdfBridge;
  final NativeArchiveBridge? _archiveBridge;
  final ArchivePasswordStore? _passwordStore;
  int _idSeq = 0;

  String _nextId(String prefix) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    _idSeq = (_idSeq + 1) & 0xFFFF;
    return 'local:${prefix}_${micros}_$_idSeq';
  }

  /// 批量导入选中的压缩包文件流（兼容 Android `content://` 流、本地文件流与加密包密码解锁）。
  Future<LocalImportBatchResult> importArchiveFiles(
    List<PickedComicFile> files, {
    String? parentFolderName,
    ImportProgressCallback? onProgress,
    ArchivePasswordPromptCallback? onPasswordPrompt,
  }) async {
    final seriesIds = <String>{};
    final bookIds = <String>[];
    final failures = <ImportFailureItem>[];

    for (var i = 0; i < files.length; i++) {
      final item = files[i];
      onProgress?.call(i, files.length, item.name);
      try {
        final imported = await importArchiveOrCollectionStream(
          db: _db,
          storage: _storage,
          coverEncoder: _coverEncoder,
          openStream: item.openRead,
          displayFileName: item.name,
          parentFolderName: parentFolderName,
          nextId: _nextId,
          pdfBridge: _pdfBridge,
          archiveBridge: _archiveBridge,
          passwordStore: _passwordStore,
          onPasswordPrompt: onPasswordPrompt,
        );
        seriesIds.addAll(imported.importedSeriesIds);
        bookIds.addAll(imported.importedBookIds);
        failures.addAll(imported.failures);
      } on ArchiveException catch (e) {
        failures.add(
          ImportFailureItem(
            fileName: item.name,
            reason: mapArchiveImportFailure(e.kind),
          ),
        );
      } on FileSystemException {
        failures.add(
          ImportFailureItem(
            fileName: item.name,
            reason: ImportFailureReason.ioError,
          ),
        );
      }
    }
    onProgress?.call(files.length, files.length, '');

    return LocalImportBatchResult(
      importedSeriesIds: seriesIds.toList(growable: false),
      importedBookIds: bookIds,
      failures: failures,
    );
  }

  /// 将一组选中的散装图片页合成为单本漫画目录入库（兼容移动端相册/SAF 多选图片导入）。
  Future<LocalImportBatchResult> importImageFilesAsBook(
    List<PickedComicFile> imageFiles, {
    required String bookTitle,
    String? seriesTitle,
    ImportProgressCallback? onProgress,
  }) async {
    final valid = <PickedComicFile>[
      for (final f in imageFiles)
        if (isSupportedComicImagePath(f.name)) f,
    ];
    if (valid.isEmpty) {
      return LocalImportBatchResult(
        failures: <ImportFailureItem>[
          ImportFailureItem(
            fileName: bookTitle,
            reason: ImportFailureReason.noImages,
          ),
        ],
      );
    }
    valid.sort((a, b) => naturalCompare(a.name, b.name));

    final bookId = _nextId('b');
    final safeFolder = bookId.replaceAll(':', '_');
    final folderRelPath = 'books/$safeFolder/pages';
    final destDir = await _storage.resolveDirectory(folderRelPath);

    try {
      await destDir.create(recursive: true);
      var totalBytes = 0;
      for (var i = 0; i < valid.length; i++) {
        final item = valid[i];
        onProgress?.call(i, valid.length, item.name);
        final safeName = '${(i + 1).toString().padLeft(4, '0')}_${item.name}';
        final outFile = File('${destDir.path}/$safeName');
        await writeStreamToFile(item.openRead(), outFile);
        totalBytes += await outFile.length();
      }
      final reader = await FolderComicReader.open(destDir);
      final imported = await commitComicReaderToDatabase(
        db: _db,
        storage: _storage,
        coverEncoder: _coverEncoder,
        bookId: bookId,
        safeFolder: safeFolder,
        storageKind: 'folder',
        relativePath: folderRelPath,
        sizeBytes: totalBytes,
        displayName: bookTitle,
        parentFolderName: seriesTitle,
        reader: reader,
        generateSeriesId: () => _nextId('s'),
      );
      await reader.close();
      onProgress?.call(valid.length, valid.length, '');
      return LocalImportBatchResult(
        importedSeriesIds: <String>[imported.seriesId],
        importedBookIds: <String>[imported.bookId],
      );
    } on ArchiveException catch (e) {
      await tryDeleteImportDir(destDir.parent);
      return LocalImportBatchResult(
        failures: <ImportFailureItem>[
          ImportFailureItem(
            fileName: bookTitle,
            reason: mapArchiveImportFailure(e.kind),
          ),
        ],
      );
    } on FileSystemException {
      await tryDeleteImportDir(destDir.parent);
      return LocalImportBatchResult(
        failures: <ImportFailureItem>[
          ImportFailureItem(
            fileName: bookTitle,
            reason: ImportFailureReason.ioError,
          ),
        ],
      );
    }
  }

  /// 将侧车封面字节（如 `cover.jpg` / `folder.png` / `poster.jpg`）绑定为本地系列封面。
  Future<String?> applySeriesCoverImage(
    Uint8List imageBytes, {
    String? seriesId,
    String? seriesTitle,
    bool overwriteExisting = false,
  }) => applySidecarSeriesCover(
    db: _db,
    storage: _storage,
    coverEncoder: _coverEncoder,
    imageBytes: imageBytes,
    seriesId: seriesId,
    seriesTitle: seriesTitle,
    overwriteExisting: overwriteExisting,
  );

  /// 导入本地文件夹（支持文件夹内含多卷归档及同级侧车封面，或文件夹内直接放漫画图片页）。
  Future<LocalImportBatchResult> importDirectory(
    String directoryPath, {
    ImportProgressCallback? onProgress,
  }) async {
    final sourceDir = Directory(directoryPath);
    final folderName = importBaseName(directoryPath);
    if (!await sourceDir.exists()) {
      return LocalImportBatchResult(
        failures: <ImportFailureItem>[
          ImportFailureItem(
            fileName: folderName,
            reason: ImportFailureReason.ioError,
          ),
        ],
      );
    }

    final scanned = await _scanDirectoryForArchivesAndCover(sourceDir);
    if (scanned.archives.isNotEmpty) {
      final result = await importArchiveFiles(
        scanned.archives,
        parentFolderName: folderName,
        onProgress: onProgress,
      );
      final sidecarCover = scanned.sidecarCover;
      if (sidecarCover != null && result.importedSeriesIds.length == 1) {
        try {
          final bytes = await sidecarCover.readAsBytes();
          await applySeriesCoverImage(
            bytes,
            seriesId: result.importedSeriesIds.single,
          );
        } on FileSystemException {
          // 侧车封面读取失败不影响已导入分卷。
        }
      }
      return result;
    }

    onProgress?.call(0, 1, folderName);
    final bookId = _nextId('b');
    final safeFolder = bookId.replaceAll(':', '_');
    final folderRelPath = 'books/$safeFolder/pages';
    final destDir = await _storage.resolveDirectory(folderRelPath);
    FolderComicReader? probeReader;

    try {
      probeReader = await FolderComicReader.open(sourceDir);
      await destDir.create(recursive: true);
      var totalBytes = 0;
      for (final page in probeReader.pages) {
        final srcBytes = await probeReader.readPage(page.number);
        totalBytes += srcBytes.length;
        final pageFile = File('${destDir.path}/${page.entryName}');
        await pageFile.parent.create(recursive: true);
        await pageFile.writeAsBytes(srcBytes, flush: true);
      }
      final xmlBytes = probeReader.comicInfoBytes;
      if (xmlBytes != null) {
        await File('${destDir.path}/ComicInfo.xml').writeAsBytes(xmlBytes);
      }
      await probeReader.close();
      probeReader = null;

      final managedReader = await FolderComicReader.open(destDir);
      final imported = await commitComicReaderToDatabase(
        db: _db,
        storage: _storage,
        coverEncoder: _coverEncoder,
        bookId: bookId,
        safeFolder: safeFolder,
        storageKind: 'folder',
        relativePath: folderRelPath,
        sizeBytes: totalBytes,
        displayName: folderName,
        parentFolderName: null,
        reader: managedReader,
        generateSeriesId: () => _nextId('s'),
      );
      await managedReader.close();
      onProgress?.call(1, 1, '');
      return LocalImportBatchResult(
        importedSeriesIds: <String>[imported.seriesId],
        importedBookIds: <String>[imported.bookId],
      );
    } on ArchiveException catch (e) {
      await probeReader?.close();
      await tryDeleteImportDir(destDir.parent);
      return LocalImportBatchResult(
        failures: <ImportFailureItem>[
          ImportFailureItem(
            fileName: folderName,
            reason: mapArchiveImportFailure(e.kind),
          ),
        ],
      );
    } on FileSystemException {
      await probeReader?.close();
      await tryDeleteImportDir(destDir.parent);
      return LocalImportBatchResult(
        failures: <ImportFailureItem>[
          ImportFailureItem(
            fileName: folderName,
            reason: ImportFailureReason.ioError,
          ),
        ],
      );
    }
  }
}

Future<({List<PickedComicFile> archives, File? sidecarCover})>
_scanDirectoryForArchivesAndCover(Directory sourceDir) async {
  final archives = <PickedComicFile>[];
  File? sidecarCover;
  int? sidecarPrio;
  await for (final entity in sourceDir.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = importBaseName(entity.path);
    final lower = name.toLowerCase();
    if (isNestedComicArchivePath(name) ||
        lower.endsWith('.pdf') ||
        lower.endsWith('.cbr') ||
        lower.endsWith('.rar') ||
        lower.endsWith('.cb7') ||
        lower.endsWith('.7z')) {
      archives.add(PickedComicFile.fromFile(entity, name: name));
      continue;
    }
    final prio = sidecarCoverPriority(name);
    if (prio != null && (sidecarPrio == null || prio < sidecarPrio)) {
      sidecarCover = entity;
      sidecarPrio = prio;
    }
  }
  archives.sort((a, b) => naturalCompare(a.name, b.name));
  return (archives: archives, sidecarCover: sidecarCover);
}
