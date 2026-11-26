import 'dart:io';
import 'dart:typed_data';

import 'package:yomu/src/data/local/cover_thumbnail_generator.dart';
import 'package:yomu/src/data/local/local_comic_importer_models.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

/// 导入单个归档文件流；若检测到为「嵌套合集包」（内部无直接图片但含多个子归档），
/// 自动拆包入库并归入同一系列，同时清理外层临时文件（LMB-06）。
Future<LocalImportBatchResult> importArchiveOrCollectionStream({
  required ProgressDatabase db,
  required LocalComicsStorage storage,
  required CoverThumbnailEncoder coverEncoder,
  required Stream<List<int>> Function() openStream,
  required String displayFileName,
  required String? parentFolderName,
  required String Function(String prefix) nextId,
  bool allowNestedUnpack = true,
}) async {
  final bookId = nextId('b');
  final safeFolder = bookId.replaceAll(':', '_');
  final lower = displayFileName.toLowerCase();
  final archiveExt = lower.endsWith('.epub')
      ? 'epub'
      : (lower.endsWith('.cbt') || lower.endsWith('.tar'))
      ? 'cbt'
      : 'cbz';
  final archiveRelPath = 'books/$safeFolder/archive.$archiveExt';
  final destFile = await storage.resolveFile(archiveRelPath);

  FileByteSource? fileSource;
  ComicArchiveReader? reader;
  try {
    await destFile.parent.create(recursive: true);
    await writeStreamToFile(openStream(), destFile);
    final sizeBytes = await destFile.length();
    fileSource = await FileByteSource.open(destFile);

    try {
      reader = await openComicArchive(fileSource);
    } on ArchiveException catch (e) {
      fileSource = null; // openComicArchive 失败时已关闭句柄
      if (allowNestedUnpack && e.kind == ArchiveErrorKind.noImages) {
        final unpacked = await _tryUnpackNestedCollection(
          db: db,
          storage: storage,
          coverEncoder: coverEncoder,
          outerFile: destFile,
          outerFileName: displayFileName,
          parentFolderName: parentFolderName,
          nextId: nextId,
        );
        if (unpacked != null) {
          await tryDeleteImportDir(destFile.parent);
          return unpacked;
        }
      }
      rethrow;
    }

    final storageKind = switch (reader) {
      EpubComicReader() => 'epub',
      TarComicReader() => 'tar',
      _ => 'zip',
    };
    final result = await commitComicReaderToDatabase(
      db: db,
      storage: storage,
      coverEncoder: coverEncoder,
      bookId: bookId,
      safeFolder: safeFolder,
      storageKind: storageKind,
      relativePath: archiveRelPath,
      sizeBytes: sizeBytes,
      displayName: displayFileName,
      parentFolderName: parentFolderName,
      reader: reader,
      generateSeriesId: () => nextId('s'),
    );
    await reader.close();
    reader = null;
    fileSource = null;
    return LocalImportBatchResult(
      importedSeriesIds: <String>[result.seriesId],
      importedBookIds: <String>[result.bookId],
    );
  } on Object {
    await reader?.close();
    await fileSource?.close();
    await tryDeleteImportDir(destFile.parent);
    rethrow;
  }
}

Future<LocalImportBatchResult?> _tryUnpackNestedCollection({
  required ProgressDatabase db,
  required LocalComicsStorage storage,
  required CoverThumbnailEncoder coverEncoder,
  required File outerFile,
  required String outerFileName,
  required String? parentFolderName,
  required String Function(String prefix) nextId,
}) async {
  final outerSource = await FileByteSource.open(outerFile);
  try {
    final nestedEntries = await inspectNestedZipArchives(outerSource);
    if (nestedEntries.isEmpty) return null;

    final collectionSeries =
        (parentFolderName != null && parentFolderName.trim().isNotEmpty)
        ? parentFolderName.trim()
        : inferTitlesFromFileName(outerFileName).seriesTitle;

    final seriesIds = <String>{};
    final bookIds = <String>[];
    final failures = <ImportFailureItem>[];

    for (final entry in nestedEntries) {
      final childName = importBaseName(entry.name);
      try {
        final childBytes = await ZipComicReader.extractEntry(
          outerSource,
          entry,
        );
        final sub = await importArchiveOrCollectionStream(
          db: db,
          storage: storage,
          coverEncoder: coverEncoder,
          openStream: () => Stream<Uint8List>.value(childBytes),
          displayFileName: childName,
          parentFolderName: collectionSeries,
          nextId: nextId,
          allowNestedUnpack: false,
        );
        seriesIds.addAll(sub.importedSeriesIds);
        bookIds.addAll(sub.importedBookIds);
        failures.addAll(sub.failures);
      } on ArchiveException catch (e) {
        failures.add(
          ImportFailureItem(
            fileName: childName,
            reason: mapArchiveImportFailure(e.kind),
          ),
        );
      } on FileSystemException {
        failures.add(
          ImportFailureItem(
            fileName: childName,
            reason: ImportFailureReason.ioError,
          ),
        );
      }
    }

    return LocalImportBatchResult(
      importedSeriesIds: seriesIds.toList(growable: false),
      importedBookIds: bookIds,
      failures: failures,
    );
  } finally {
    await outerSource.close();
  }
}
