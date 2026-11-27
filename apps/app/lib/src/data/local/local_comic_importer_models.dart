import 'dart:io';
import 'dart:typed_data';

import 'package:yomu/src/data/local/cover_thumbnail_generator.dart';
import 'package:yomu/src/data/local/local_catalog_edit_dao.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/local_import_cleanup.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

export 'package:yomu/src/data/local/local_import_cleanup.dart'
    show ImportCancellationToken, ImportCancelledException;

/// 单本导入失败的结构化原因（UI 按枚举展示本地化提示）。
enum ImportFailureReason {
  emptyFile,
  unsupportedFormat,
  encrypted,
  corrupted,
  noImages,
  textOnlyEpub,
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
    this.cancelled = false,
  });

  final List<String> importedSeriesIds;
  final List<String> importedBookIds;
  final List<ImportFailureItem> failures;
  final bool cancelled;

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
      ArchiveErrorKind.textOnlyEpub => ImportFailureReason.textOnlyEpub,
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
  String? seriesIdOverride,
  String? mountRootId,
  String? sourceRelativePath,
  int? sourceModifiedMs,
  DateTime? nowOverride,
}) async {
  final xmlBytes = reader.comicInfoBytes;
  final meta = xmlBytes != null
      ? parseComicInfoXml(xmlBytes)
      : (reader.embeddedMetadata ?? const ComicInfoMetadata());
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
    final rawCover =
        await reader.readCoverImage() ?? await reader.readPage(coverPageNumber);
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
  } on Exception {
    coverRelPath = null;
  }

  return db.insertImportedLocalBook(
    LocalBookImportDraft(
      bookId: bookId,
      seriesIdOverride: seriesIdOverride,
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
      chapters: reader.chapters,
      mountRootId: mountRootId,
      sourceRelativePath: sourceRelativePath,
      sourceModifiedMs: sourceModifiedMs,
    ),
    generateSeriesId: generateSeriesId,
    nowOverride: nowOverride,
  );
}

/// 将目录侧车封面图（`cover.*` / `folder.*` / `poster.*`）编码落盘并绑定为本地系列封面。
///
/// 未找到目标系列，或系列已锁定/已有自定义封面且 [overwriteExisting] 为 `false` 时返回 `null`。
Future<String?> applySidecarSeriesCover({
  required ProgressDatabase db,
  required LocalComicsStorage storage,
  required CoverThumbnailEncoder coverEncoder,
  required Uint8List imageBytes,
  String? seriesId,
  String? seriesTitle,
  bool overwriteExisting = false,
}) async {
  if (imageBytes.isEmpty) return null;
  final target = await db.findLocalSeriesForSidecarCover(
    seriesId: seriesId,
    seriesTitle: seriesTitle,
    overwriteExisting: overwriteExisting,
  );
  if (target == null) return null;

  final direction = ReadingDirection.values.firstWhere(
    (d) => d.name == target.readingDirection,
    orElse: () => ReadingDirection.unknown,
  );
  Uint8List? encoded;
  try {
    encoded = await coverEncoder(imageBytes, direction: direction);
  } on Exception {
    encoded = null;
  }
  final payload = (encoded != null && encoded.isNotEmpty)
      ? encoded
      : imageBytes;
  final safeSeries = target.id.replaceAll(':', '_');
  final relPath = 'covers/series_$safeSeries.png';
  final coverFile = await storage.resolveFile(relPath);
  await coverFile.parent.create(recursive: true);
  await coverFile.writeAsBytes(payload, flush: true);
  await db.setLocalSeriesCustomCoverPath(
    seriesId: target.id,
    coverRelativePath: relPath,
  );
  return target.id;
}

String? _nonEmpty(String? s) =>
    (s == null || s.trim().isEmpty) ? null : s.trim();

Future<void> writeStreamToFile(
  Stream<List<int>> stream,
  File dest, {
  ImportCancellationToken? cancelToken,
}) async {
  cancelToken?.throwIfCancelled();
  final sink = dest.openWrite();
  try {
    // 不用 stream.pipe(sink)：PlatformFile.readAsByteStream() 的运行时类型是
    // Stream<Uint8List>，而 IOSink 实现的是 StreamConsumer<List<int>>，
    // Dart 泛型协变检查会在 Stream<Uint8List>.pipe 上抛 TypeError。
    await for (final chunk in stream) {
      cancelToken?.throwIfCancelled();
      sink.add(chunk);
    }
    await sink.flush();
  } finally {
    await sink.close();
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
