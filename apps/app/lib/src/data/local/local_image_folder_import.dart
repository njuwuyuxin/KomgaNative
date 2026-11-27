import 'dart:io';

import 'package:yomu/src/data/local/comic_file_picker.dart';
import 'package:yomu/src/data/local/comic_reader_factory.dart';
import 'package:yomu/src/data/local/cover_thumbnail_generator.dart';
import 'package:yomu/src/data/local/local_comic_importer_models.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/local_import_cleanup.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

/// 将一组选中的散装图片页合成为单本漫画目录入库（兼容移动端相册/SAF 多选图片导入）。
Future<LocalImportBatchResult> importImageFilesAsBookToSandbox({
  required ProgressDatabase db,
  required LocalComicsStorage storage,
  required CoverThumbnailEncoder coverEncoder,
  required List<PickedComicFile> imageFiles,
  required String bookTitle,
  required String Function(String prefix) nextId,
  String? seriesTitle,
  ImportProgressCallback? onProgress,
  ImportCancellationToken? cancelToken,
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

  final bookId = nextId('b');
  final safeFolder = bookId.replaceAll(':', '_');
  final folderRelPath = 'books/$safeFolder/pages';
  final destDir = await storage.resolveDirectory(folderRelPath);

  FolderComicReader? reader;
  String? committedBookId;
  try {
    await destDir.create(recursive: true);
    var totalBytes = 0;
    for (var i = 0; i < valid.length; i++) {
      cancelToken?.throwIfCancelled();
      final item = valid[i];
      onProgress?.call(i, valid.length, item.name);
      final safeName = '${(i + 1).toString().padLeft(4, '0')}_${item.name}';
      final outFile = File('${destDir.path}/$safeName');
      await writeStreamToFile(
        item.openRead(),
        outFile,
        cancelToken: cancelToken,
      );
      totalBytes += await outFile.length();
    }
    reader = await FolderComicReader.open(destDir);
    final imported = await commitComicReaderToDatabase(
      db: db,
      storage: storage,
      coverEncoder: coverEncoder,
      bookId: bookId,
      safeFolder: safeFolder,
      storageKind: LocalStorageKind.folder.wireValue,
      relativePath: folderRelPath,
      sizeBytes: totalBytes,
      displayName: bookTitle,
      parentFolderName: seriesTitle,
      reader: reader,
      generateSeriesId: () => nextId('s'),
    );
    committedBookId = imported.bookId;
    final closing = reader;
    reader = null;
    await closing.close();
    onProgress?.call(valid.length, valid.length, '');
    return LocalImportBatchResult(
      importedSeriesIds: <String>[imported.seriesId],
      importedBookIds: <String>[imported.bookId],
    );
  } on ImportCancelledException {
    await tryCloseArchiveReader(reader);
    if (committedBookId != null) {
      await rollbackCommittedLocalBook(
        db: db,
        storage: storage,
        bookId: committedBookId,
      );
    }
    await tryDeleteImportDir(destDir.parent);
    return const LocalImportBatchResult(cancelled: true);
  } on ArchiveException catch (e) {
    await tryCloseArchiveReader(reader);
    if (committedBookId != null) {
      await rollbackCommittedLocalBook(
        db: db,
        storage: storage,
        bookId: committedBookId,
      );
    }
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
    await tryCloseArchiveReader(reader);
    if (committedBookId != null) {
      await rollbackCommittedLocalBook(
        db: db,
        storage: storage,
        bookId: committedBookId,
      );
    }
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

/// 将本地图片文件夹整体拷贝至受管沙盒并索引入库。
Future<LocalImportBatchResult> importLocalImageFolderToSandbox({
  required ProgressDatabase db,
  required LocalComicsStorage storage,
  required CoverThumbnailEncoder coverEncoder,
  required Directory sourceDir,
  required String folderName,
  required String Function(String prefix) nextId,
  ImportProgressCallback? onProgress,
  ImportCancellationToken? cancelToken,
}) async {
  cancelToken?.throwIfCancelled();
  onProgress?.call(0, 1, folderName);
  final bookId = nextId('b');
  final safeFolder = bookId.replaceAll(':', '_');
  final folderRelPath = 'books/$safeFolder/pages';
  final destDir = await storage.resolveDirectory(folderRelPath);
  FolderComicReader? probeReader;
  FolderComicReader? managedReader;
  String? committedBookId;

  try {
    probeReader = await FolderComicReader.open(sourceDir);
    await destDir.create(recursive: true);
    var totalBytes = 0;
    for (final page in probeReader.pages) {
      cancelToken?.throwIfCancelled();
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

    managedReader = await FolderComicReader.open(destDir);
    final imported = await commitComicReaderToDatabase(
      db: db,
      storage: storage,
      coverEncoder: coverEncoder,
      bookId: bookId,
      safeFolder: safeFolder,
      storageKind: LocalStorageKind.folder.wireValue,
      relativePath: folderRelPath,
      sizeBytes: totalBytes,
      displayName: folderName,
      parentFolderName: null,
      reader: managedReader,
      generateSeriesId: () => nextId('s'),
    );
    committedBookId = imported.bookId;
    await managedReader.close();
    managedReader = null;
    onProgress?.call(1, 1, '');
    return LocalImportBatchResult(
      importedSeriesIds: <String>[imported.seriesId],
      importedBookIds: <String>[imported.bookId],
    );
  } on ImportCancelledException {
    await tryCloseArchiveReader(probeReader);
    await tryCloseArchiveReader(managedReader);
    if (committedBookId != null) {
      await rollbackCommittedLocalBook(
        db: db,
        storage: storage,
        bookId: committedBookId,
      );
    }
    await tryDeleteImportDir(destDir.parent);
    return const LocalImportBatchResult(cancelled: true);
  } on ArchiveException catch (e) {
    await tryCloseArchiveReader(probeReader);
    await tryCloseArchiveReader(managedReader);
    if (committedBookId != null) {
      await rollbackCommittedLocalBook(
        db: db,
        storage: storage,
        bookId: committedBookId,
      );
    }
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
    await tryCloseArchiveReader(probeReader);
    await tryCloseArchiveReader(managedReader);
    if (committedBookId != null) {
      await rollbackCommittedLocalBook(
        db: db,
        storage: storage,
        bookId: committedBookId,
      );
    }
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
