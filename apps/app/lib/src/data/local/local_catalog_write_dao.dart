import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

/// 导入单本本地漫画时提交给数据库的完整入库草稿。
final class LocalBookImportDraft {
  const LocalBookImportDraft({
    required this.bookId,
    required this.seriesTitle,
    required this.bookName,
    required this.storageKind,
    required this.relativePath,
    required this.sizeBytes,
    required this.pages,
    this.seriesIdOverride,
    this.number = '',
    this.numberSort = 0,
    this.summary = '',
    this.publisher = '',
    this.authors = const <String>[],
    this.tags = const <String>[],
    this.readingDirection = ReadingDirection.unknown,
    this.releaseDate,
    this.coverThumbPath,
    this.chapters = const <ArchiveChapter>[],
    this.mountRootId,
    this.sourceRelativePath,
    this.sourceModifiedMs,
    this.isCloudPlaceholder = false,
  });

  final String bookId;
  final String? seriesIdOverride;
  final String seriesTitle;
  final String bookName;
  final String number;
  final double numberSort;
  final String summary;
  final String publisher;
  final List<String> authors;
  final List<String> tags;
  final ReadingDirection readingDirection;
  final DateTime? releaseDate;
  final String storageKind;
  final String relativePath;
  final int sizeBytes;
  final String? coverThumbPath;
  final List<ArchivePageEntry> pages;
  final List<ArchiveChapter> chapters;
  final String? mountRootId;
  final String? sourceRelativePath;
  final int? sourceModifiedMs;
  final bool isCloudPlaceholder;
}

/// 生成规范化排序标题（去除英文冠词前缀并转小写）。
String normalizeTitleSort(String raw) {
  final trimmed = raw.trim().toLowerCase();
  for (final prefix in const <String>['the ', 'a ', 'an ']) {
    if (trimmed.startsWith(prefix) && trimmed.length > prefix.length) {
      return trimmed.substring(prefix.length).trimLeft();
    }
  }
  return trimmed;
}

List<String> decodeJsonStringList(String raw) {
  if (raw.isEmpty) return const <String>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List<Object?>) {
      return decoded.whereType<String>().toList(growable: false);
    }
  } on FormatException {
    // 坏字段安全回退为空列表。
  }
  return const <String>[];
}

/// [ProgressDatabase] 的本地漫画入库、存储统计与变更流扩展。
extension LocalCatalogWriteDao on ProgressDatabase {
  Stream<Set<TableUpdate>> localCatalogUpdates() => tableUpdates(
    TableUpdateQuery.onAllTables(<TableInfo<Table, Object?>>[
      localSeriesRows,
      localBooksRows,
      localProgress,
    ]),
  );

  Stream<Set<TableUpdate>> localCurationUpdates() => tableUpdates(
    TableUpdateQuery.onAllTables(<TableInfo<Table, Object?>>[
      localCollectionsRows,
      localReadListsRows,
    ]),
  );

  /// 事务性入库一本本地漫画：若存在同名未锁定系列则自动归并追加分卷，否则新建系列。
  Future<({String seriesId, String bookId})> insertImportedLocalBook(
    LocalBookImportDraft draft, {
    required String Function() generateSeriesId,
    DateTime? nowOverride,
  }) {
    return transaction(() async {
      final now = (nowOverride ?? DateTime.now()).toUtc();
      final normSort = normalizeTitleSort(draft.seriesTitle);

      LocalSeriesRow? existingSeries;
      if (draft.seriesIdOverride != null) {
        existingSeries =
            await (select(localSeriesRows)
                  ..where((t) => t.id.equals(draft.seriesIdOverride!)))
                .getSingleOrNull();
      } else {
        final candidates = await (select(
          localSeriesRows,
        )..where((t) => t.titleSort.equals(normSort))).get();
        for (final row in candidates) {
          if (row.title.trim().toLowerCase() ==
              draft.seriesTitle.trim().toLowerCase()) {
            existingSeries = row;
            break;
          }
        }
      }

      final String seriesId;
      if (existingSeries == null) {
        seriesId = draft.seriesIdOverride ?? generateSeriesId();
        await into(localSeriesRows).insert(
          LocalSeriesRowsCompanion.insert(
            id: seriesId,
            title: draft.seriesTitle.trim(),
            titleSort: normSort,
            summary: Value<String>(draft.summary),
            publisher: Value<String>(draft.publisher),
            authorsJson: Value<String>(jsonEncode(draft.authors)),
            tagsJson: Value<String>(jsonEncode(draft.tags)),
            readingDirection: Value<String>(draft.readingDirection.name),
            coverBookId: Value<String?>(draft.bookId),
            releaseDate: Value<DateTime?>(draft.releaseDate),
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else {
        seriesId = existingSeries.id;
        if (!existingSeries.metadataLocked) {
          final mergedAuthors = <String>{
            ...decodeJsonStringList(existingSeries.authorsJson),
            ...draft.authors,
          }.toList(growable: false);
          final mergedTags = <String>{
            ...decodeJsonStringList(existingSeries.tagsJson),
            ...draft.tags,
          }.toList(growable: false);
          final nextDir =
              existingSeries.readingDirection ==
                      ReadingDirection.unknown.name &&
                  draft.readingDirection != ReadingDirection.unknown
              ? draft.readingDirection.name
              : existingSeries.readingDirection;
          await (update(
            localSeriesRows,
          )..where((t) => t.id.equals(seriesId))).write(
            LocalSeriesRowsCompanion(
              summary:
                  existingSeries.summary.isEmpty && draft.summary.isNotEmpty
                  ? Value<String>(draft.summary)
                  : const Value.absent(),
              publisher:
                  existingSeries.publisher.isEmpty && draft.publisher.isNotEmpty
                  ? Value<String>(draft.publisher)
                  : const Value.absent(),
              authorsJson: Value<String>(jsonEncode(mergedAuthors)),
              tagsJson: Value<String>(jsonEncode(mergedTags)),
              readingDirection: Value<String>(nextDir),
              coverBookId: existingSeries.coverBookId == null
                  ? Value<String?>(draft.bookId)
                  : const Value.absent(),
              releaseDate:
                  existingSeries.releaseDate == null &&
                      draft.releaseDate != null
                  ? Value<DateTime?>(draft.releaseDate)
                  : const Value.absent(),
              updatedAt: Value<DateTime>(now),
            ),
          );
        } else {
          await (update(localSeriesRows)..where((t) => t.id.equals(seriesId)))
              .write(LocalSeriesRowsCompanion(updatedAt: Value<DateTime>(now)));
        }
      }

      await into(localBooksRows).insertOnConflictUpdate(
        LocalBooksRowsCompanion.insert(
          id: draft.bookId,
          seriesId: seriesId,
          name: draft.bookName,
          number: Value<String>(draft.number),
          numberSort: Value<double>(draft.numberSort),
          pagesCount: draft.pages.length,
          sizeBytes: draft.sizeBytes,
          storageKind: draft.storageKind,
          relativePath: draft.relativePath,
          coverThumbPath: Value<String?>(draft.coverThumbPath),
          mountRootId: Value<String?>(draft.mountRootId),
          sourceRelativePath: Value<String?>(draft.sourceRelativePath),
          sourceModifiedMs: Value<int?>(draft.sourceModifiedMs),
          isCloudPlaceholder: Value<bool>(draft.isCloudPlaceholder),
          releaseDate: Value<DateTime?>(draft.releaseDate),
          createdAt: now,
        ),
      );

      await (delete(
        localPagesRows,
      )..where((t) => t.bookId.equals(draft.bookId))).go();
      await (delete(
        localBookChaptersRows,
      )..where((t) => t.bookId.equals(draft.bookId))).go();
      await batch((Batch b) {
        b.insertAll(localPagesRows, <LocalPagesRowsCompanion>[
          for (final p in draft.pages)
            LocalPagesRowsCompanion.insert(
              bookId: draft.bookId,
              pageNumber: p.number,
              entryName: p.entryName,
              localHeaderOffset: Value<int>(p.localHeaderOffset),
              compressedSize: Value<int>(p.compressedSize),
              uncompressedSize: Value<int>(p.uncompressedSize),
              compressionMethod: Value<int>(p.compressionMethod),
              width: Value<int?>(p.width),
              height: Value<int?>(p.height),
              mediaType: Value<String?>(p.mediaType),
            ),
        ]);
        if (draft.chapters.isNotEmpty) {
          b.insertAll(localBookChaptersRows, <LocalBookChaptersRowsCompanion>[
            for (var i = 0; i < draft.chapters.length; i++)
              LocalBookChaptersRowsCompanion.insert(
                bookId: draft.bookId,
                chapterIndex: i,
                title: draft.chapters[i].title,
                startPage: draft.chapters[i].startPage,
              ),
          ]);
        }
      });

      return (seriesId: seriesId, bookId: draft.bookId);
    });
  }

  /// 本机已导入漫画的册数与总字节数。
  Future<({int booksCount, int totalBytes})> localStorageUsage() async {
    final rows = await select(localBooksRows).get();
    var total = 0;
    for (final row in rows) {
      total += row.sizeBytes;
    }
    return (booksCount: rows.length, totalBytes: total);
  }
}
