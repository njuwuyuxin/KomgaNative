import 'dart:io';
import 'dart:typed_data';

import 'package:yomu/src/data/local/archive_password_store.dart';
import 'package:yomu/src/data/local/comic_file_picker.dart';
import 'package:yomu/src/data/local/cover_thumbnail_generator.dart';
import 'package:yomu/src/data/local/local_archive_import_stream.dart';
import 'package:yomu/src/data/local/local_comic_importer_models.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/local_external_directory_import.dart';
import 'package:yomu/src/data/local/local_image_folder_import.dart';
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
    ImportCancellationToken? cancelToken,
  }) async {
    final seriesIds = <String>{};
    final bookIds = <String>[];
    final failures = <ImportFailureItem>[];
    var cancelled = false;

    for (var i = 0; i < files.length; i++) {
      if (cancelToken?.isCancelled ?? false) {
        cancelled = true;
        break;
      }
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
          cancelToken: cancelToken,
        );
        seriesIds.addAll(imported.importedSeriesIds);
        bookIds.addAll(imported.importedBookIds);
        failures.addAll(imported.failures);
        if (imported.cancelled) {
          cancelled = true;
          break;
        }
      } on ImportCancelledException {
        cancelled = true;
        break;
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
      cancelled: cancelled,
    );
  }

  /// 将一组选中的散装图片页合成为单本漫画目录入库（兼容移动端相册/SAF 多选图片导入）。
  Future<LocalImportBatchResult> importImageFilesAsBook(
    List<PickedComicFile> imageFiles, {
    required String bookTitle,
    String? seriesTitle,
    ImportProgressCallback? onProgress,
    ImportCancellationToken? cancelToken,
  }) => importImageFilesAsBookToSandbox(
    db: _db,
    storage: _storage,
    coverEncoder: _coverEncoder,
    imageFiles: imageFiles,
    bookTitle: bookTitle,
    seriesTitle: seriesTitle,
    nextId: _nextId,
    onProgress: onProgress,
    cancelToken: cancelToken,
  );

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

  /// 导入外部挂载或 SAF / iOS Bookmark 选中的文件夹至受管沙盒。
  Future<LocalImportBatchResult> importExternalDirectory(
    MountedExternalRoot root,
    ExternalRootsBridge bridge, {
    ImportProgressCallback? onProgress,
    ArchivePasswordPromptCallback? onPasswordPrompt,
    ImportCancellationToken? cancelToken,
  }) => importExternalDirectoryToSandbox(
    db: _db,
    storage: _storage,
    coverEncoder: _coverEncoder,
    bridge: bridge,
    root: root,
    importer: this,
    nextId: _nextId,
    onProgress: onProgress,
    onPasswordPrompt: onPasswordPrompt,
    cancelToken: cancelToken,
  );

  /// 导入本地文件夹（支持文件夹内含多卷归档及同级侧车封面，或文件夹内直接放漫画图片页）。
  Future<LocalImportBatchResult> importDirectory(
    String directoryPath, {
    ImportProgressCallback? onProgress,
    ArchivePasswordPromptCallback? onPasswordPrompt,
    ImportCancellationToken? cancelToken,
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

    final scanned = await scanLocalDirectoryForArchivesAndCover(sourceDir);
    if (scanned.archives.isNotEmpty) {
      final result = await importArchiveFiles(
        scanned.archives,
        parentFolderName: folderName,
        onProgress: onProgress,
        onPasswordPrompt: onPasswordPrompt,
        cancelToken: cancelToken,
      );
      final sidecarCover = scanned.sidecarCover;
      if (!result.cancelled &&
          sidecarCover != null &&
          result.importedSeriesIds.length == 1) {
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

    return importLocalImageFolderToSandbox(
      db: _db,
      storage: _storage,
      coverEncoder: _coverEncoder,
      sourceDir: sourceDir,
      folderName: folderName,
      nextId: _nextId,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }
}
