import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 一次本地删除事务完成后需要在磁盘上清理的相对路径清单。
final class DeletedLocalPaths {
  const DeletedLocalPaths({
    this.bookRelativePaths = const <String>[],
    this.coverRelativePaths = const <String>[],
    this.seriesDeleted = false,
  });

  final List<String> bookRelativePaths;
  final List<String> coverRelativePaths;
  final bool seriesDeleted;
}

/// [ProgressDatabase] 的本地书籍/系列事务性删除扩展（LMA-09）。
extension LocalCatalogDeleteDao on ProgressDatabase {
  /// 从数据库删除单本本地书籍（若所属系列变空则同步删除系列、置顶与空收藏集引用）。
  Future<DeletedLocalPaths?> deleteLocalBookFromDb(String bookId) {
    return transaction(() async {
      final bookRow = await (select(
        localBooksRows,
      )..where((t) => t.id.equals(bookId))).getSingleOrNull();
      if (bookRow == null) return null;

      await (delete(
        localPagesRows,
      )..where((t) => t.bookId.equals(bookId))).go();
      await (delete(
        localBookChaptersRows,
      )..where((t) => t.bookId.equals(bookId))).go();
      await (delete(localBooksRows)..where((t) => t.id.equals(bookId))).go();
      await (delete(localProgress)..where(
            (t) => t.scope.equals(kLocalSourceKey) & t.bookId.equals(bookId),
          ))
          .go();
      await (delete(pageBookmarksRows)..where(
            (t) => t.scope.equals(kLocalSourceKey) & t.bookId.equals(bookId),
          ))
          .go();

      await _scrubBookFromReadLists(bookId);

      final covers = <String>[
        if (bookRow.coverThumbPath != null &&
            bookRow.coverThumbPath!.isNotEmpty)
          bookRow.coverThumbPath!,
      ];

      final remaining =
          await (select(localBooksRows)
                ..where((t) => t.seriesId.equals(bookRow.seriesId))
                ..orderBy(<OrderClauseGenerator<LocalBooksRows>>[
                  (t) => OrderingTerm(expression: t.numberSort),
                ]))
              .get();

      var seriesDeleted = false;
      final seriesRow = await (select(
        localSeriesRows,
      )..where((t) => t.id.equals(bookRow.seriesId))).getSingleOrNull();

      if (remaining.isEmpty) {
        seriesDeleted = true;
        if (seriesRow?.customCoverPath != null &&
            seriesRow!.customCoverPath!.isNotEmpty) {
          covers.add(seriesRow.customCoverPath!);
        }
        await (delete(
          localSeriesRows,
        )..where((t) => t.id.equals(bookRow.seriesId))).go();
        await (delete(pinnedSeriesRows)..where(
              (t) =>
                  t.serverId.equals(kLocalSourceKey) &
                  t.seriesId.equals(bookRow.seriesId),
            ))
            .go();
        await _scrubSeriesFromCollections(bookRow.seriesId);
      } else if (seriesRow != null && seriesRow.coverBookId == bookId) {
        await (update(
          localSeriesRows,
        )..where((t) => t.id.equals(seriesRow.id))).write(
          LocalSeriesRowsCompanion(
            coverBookId: Value<String?>(remaining.first.id),
            updatedAt: Value<DateTime>(DateTime.now().toUtc()),
          ),
        );
      }

      return DeletedLocalPaths(
        // 外部原位挂载书绝不返回源路径供物理删除，只删受管沙盒内的文件与缩略图（LMB-08）。
        bookRelativePaths: bookRow.mountRootId == null
            ? <String>[bookRow.relativePath]
            : const <String>[],
        coverRelativePaths: covers,
        seriesDeleted: seriesDeleted,
      );
    });
  }

  /// 从数据库删除整个本地系列及其名下所有书籍、进度、置顶与收藏集引用。
  Future<DeletedLocalPaths?> deleteLocalSeriesFromDb(String seriesId) {
    return transaction(() async {
      final seriesRow = await (select(
        localSeriesRows,
      )..where((t) => t.id.equals(seriesId))).getSingleOrNull();
      final books = await (select(
        localBooksRows,
      )..where((t) => t.seriesId.equals(seriesId))).get();
      if (seriesRow == null && books.isEmpty) return null;

      final bookPaths = <String>[];
      final coverPaths = <String>[
        if (seriesRow?.customCoverPath != null &&
            seriesRow!.customCoverPath!.isNotEmpty)
          seriesRow.customCoverPath!,
      ];

      for (final b in books) {
        if (b.mountRootId == null) {
          bookPaths.add(b.relativePath);
        }
        if (b.coverThumbPath != null && b.coverThumbPath!.isNotEmpty) {
          coverPaths.add(b.coverThumbPath!);
        }
        await (delete(
          localPagesRows,
        )..where((t) => t.bookId.equals(b.id))).go();
        await (delete(
          localBookChaptersRows,
        )..where((t) => t.bookId.equals(b.id))).go();
        await (delete(localProgress)..where(
              (t) => t.scope.equals(kLocalSourceKey) & t.bookId.equals(b.id),
            ))
            .go();
        await (delete(pageBookmarksRows)..where(
              (t) => t.scope.equals(kLocalSourceKey) & t.bookId.equals(b.id),
            ))
            .go();
        await _scrubBookFromReadLists(b.id);
      }

      await (delete(
        localBooksRows,
      )..where((t) => t.seriesId.equals(seriesId))).go();
      await (delete(localSeriesRows)..where((t) => t.id.equals(seriesId))).go();
      await (delete(pinnedSeriesRows)..where(
            (t) =>
                t.serverId.equals(kLocalSourceKey) &
                t.seriesId.equals(seriesId),
          ))
          .go();
      await _scrubSeriesFromCollections(seriesId);

      return DeletedLocalPaths(
        bookRelativePaths: bookPaths,
        coverRelativePaths: coverPaths,
        seriesDeleted: true,
      );
    });
  }

  Future<void> _scrubSeriesFromCollections(String seriesId) async {
    final rows = await select(localCollectionsRows).get();
    for (final row in rows) {
      final current = decodeJsonStringList(row.seriesIdsJson);
      if (!current.contains(seriesId)) continue;
      final next = current
          .where((id) => id != seriesId)
          .toList(growable: false);
      if (next.isEmpty) {
        await (delete(
          localCollectionsRows,
        )..where((t) => t.id.equals(row.id))).go();
      } else {
        await (update(
          localCollectionsRows,
        )..where((t) => t.id.equals(row.id))).write(
          LocalCollectionsRowsCompanion(
            seriesIdsJson: Value<String>(jsonEncode(next)),
            updatedAt: Value<DateTime>(DateTime.now().toUtc()),
          ),
        );
      }
    }
  }

  Future<void> _scrubBookFromReadLists(String bookId) async {
    final rows = await select(localReadListsRows).get();
    for (final row in rows) {
      final current = decodeJsonStringList(row.bookIdsJson);
      if (!current.contains(bookId)) continue;
      final next = current.where((id) => id != bookId).toList(growable: false);
      if (next.isEmpty) {
        await (delete(
          localReadListsRows,
        )..where((t) => t.id.equals(row.id))).go();
      } else {
        await (update(
          localReadListsRows,
        )..where((t) => t.id.equals(row.id))).write(
          LocalReadListsRowsCompanion(
            bookIdsJson: Value<String>(jsonEncode(next)),
            updatedAt: Value<DateTime>(DateTime.now().toUtc()),
          ),
        );
      }
    }
  }
}
