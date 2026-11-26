import 'dart:io';

import 'package:yomu/src/data/local/cover_thumbnail_generator.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

/// 单本导入失败的结构化原因（UI 按枚举展示本地化提示）。
enum ImportFailureReason {
  emptyFile,
  unsupportedFormat,
  encrypted,
  corrupted,
  noImages,
  ioError,
}

final class ImportFailureItem {
  const ImportFailureItem({required this.fileName, required this.reason});

  final String fileName;
  final ImportFailureReason reason;
}

final class LocalImportBatchResult {
  const LocalImportBatchResult({
    this.importedSeriesIds = const <String>[],
    this.importedBookIds = const <String>[],
    this.failures = const <ImportFailureItem>[],
  });

  final List<String> importedSeriesIds;
  final List<String> importedBookIds;
  final List<ImportFailureItem> failures;

  int get importedCount => importedBookIds.length;
  bool get hasFailures => failures.isNotEmpty;
}

typedef ImportProgressCallback = void Function(
  int completed,
  int total,
  String currentName,
);

ImportFailureReason mapArchiveImportFailure(ArchiveErrorKind kind) =>
    switch (kind) {
      ArchiveErrorKind.emptyFile => ImportFailureReason.emptyFile,
      ArchiveErrorKind.unsupportedContainer ||
      ArchiveErrorKind.unsupportedCompression =>
        ImportFailureReason.unsupportedFormat,
      ArchiveErrorKind.encryptedArchive => ImportFailureReason.encrypted,
      ArchiveErrorKind.corruptedArchive => ImportFailureReason.corrupted,
      ArchiveErrorKind.noImages => ImportFailureReason.noImages,
      ArchiveErrorKind.ioError ||
      ArchiveErrorKind.pageOutOfRange => ImportFailureReason.ioError,
    };

/// 从已打开的 [ComicArchiveReader] 提取元数据与封面缩略图，并事务写入本地目录表。
Future<({String seriesId, String bookId})> commitComicReaderToDatabase({
  required ProgressDatabase db,
  required LocalComicsStorage storage,
  required CoverThumbnailEncoder coverEncoder,
  required String bookId,
  required String safeFolder,
  required String storageKind,
  required String relativePath,
  required int sizeBytes,
  required String displayName,
  required String? parentFolderName,
  required ComicArchiveReader reader,
  required String Function() generateSeriesId,
}) async {
  final xmlBytes = reader.comicInfoBytes;
  final meta = xmlBytes != null
      ? parseComicInfoXml(xmlBytes)
      : const ComicInfoMetadata();
  final inferred = inferTitlesFromFileName(
    displayName,
    parentFolderName: parentFolderName,
  );

  final seriesTitle = _nonEmpty(meta.series) ?? inferred.seriesTitle;
  final bookName = _nonEmpty(meta.title) ?? inferred.bookTitle;
  final number =
      _nonEmpty(meta.number) ??
      (meta.volume != null ? '${meta.volume}' : inferred.number);
  final numberSort = double.tryParse(number) ?? inferred.numberSort;

  final coverPageNumber = meta.frontCoverPageIndex != null
      ? (meta.frontCoverPageIndex! + 1).clamp(1, reader.pages.length)
      : 1;
  String? coverRelPath;
  try {
    final rawCover = await reader.readPage(coverPageNumber);
    final encoded = await coverEncoder(
      rawCover,
      direction: meta.readingDirection,
    );
    if (encoded != null && encoded.isNotEmpty) {
      coverRelPath = 'covers/$safeFolder.png';
      final coverFile = await storage.resolveFile(coverRelPath);
      await coverFile.parent.create(recursive: true);
      await coverFile.writeAsBytes(encoded, flush: true);
    }
  } on Object {
    coverRelPath = null;
  }

  return db.insertImportedLocalBook(
    LocalBookImportDraft(
      bookId: bookId,
      seriesTitle: seriesTitle,
      bookName: bookName,
      number: number,
      numberSort: numberSort,
      summary: meta.summary ?? '',
      publisher: meta.publisher ?? '',
      authors: meta.authors,
      tags: meta.tags,
      readingDirection: meta.readingDirection,
      releaseDate: meta.releaseDate,
      storageKind: storageKind,
      relativePath: relativePath,
      sizeBytes: sizeBytes,
      coverThumbPath: coverRelPath,
      pages: reader.pages,
    ),
    generateSeriesId: generateSeriesId,
  );
}

String? _nonEmpty(String? s) =>
    (s == null || s.trim().isEmpty) ? null : s.trim();

Future<void> writeStreamToFile(Stream<List<int>> stream, File dest) async {
  final sink = dest.openWrite();
  try {
    await stream.pipe(sink);
  } finally {
    await sink.close();
  }
}

Future<void> tryDeleteImportDir(Directory dir) async {
  try {
    if (await dir.exists()) await dir.delete(recursive: true);
  } on FileSystemException {
    // 清理失败不覆盖主异常。
  }
}

String importBaseName(String path) {
  final norm = path.replaceAll(r'\', '/');
  final stripped = norm.endsWith('/')
      ? norm.substring(0, norm.length - 1)
      : norm;
  final idx = stripped.lastIndexOf('/');
  return idx < 0 ? stripped : stripped.substring(idx + 1);
}
