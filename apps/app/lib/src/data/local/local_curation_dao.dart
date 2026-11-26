import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// [ProgressDatabase] 的本地收藏集（Collection）与阅读列表（ReadList）CRUD 扩展。
extension LocalCurationDao on ProgressDatabase {
  Future<PageResult<Collection>> queryLocalCollections({
    int page = 0,
    int size = 20,
  }) async {
    final rows =
        await (select(localCollectionsRows)
              ..orderBy(<OrderClauseGenerator<LocalCollectionsRows>>[
                (t) => OrderingTerm(expression: t.name),
              ]))
            .get();
    final all = rows.map(_mapCollection).toList(growable: false);
    return PageResult<Collection>(
      items: _slice(all, page, size),
      totalElements: all.length,
      page: page,
      size: size,
    );
  }

  Future<Collection?> localCollectionById(String collectionId) async {
    final row = await (select(
      localCollectionsRows,
    )..where((t) => t.id.equals(collectionId))).getSingleOrNull();
    return row == null ? null : _mapCollection(row);
  }

  Future<List<Collection>> localSeriesCollections(String seriesId) async {
    final rows = await select(localCollectionsRows).get();
    final result = <Collection>[];
    for (final row in rows) {
      final col = _mapCollection(row);
      if (col.seriesIds.contains(seriesId)) {
        result.add(col);
      }
    }
    return result;
  }

  Future<Collection> insertLocalCollection({
    required String id,
    required String name,
    required List<String> seriesIds,
    bool ordered = false,
  }) async {
    final now = DateTime.now().toUtc();
    final uniqueIds = _dedupIds(seriesIds);
    await into(localCollectionsRows).insert(
      LocalCollectionsRowsCompanion.insert(
        id: id,
        name: name.trim(),
        ordered: Value<bool>(ordered),
        seriesIdsJson: Value<String>(jsonEncode(uniqueIds)),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return Collection(
      id: id,
      name: name.trim(),
      ordered: ordered,
      seriesIds: uniqueIds,
      createdDate: now,
      lastModifiedDate: now,
      sourceKey: kLocalSourceKey,
    );
  }

  Future<void> modifyLocalCollection(
    String collectionId, {
    String? name,
    bool? ordered,
    List<String>? seriesIds,
  }) async {
    final now = DateTime.now().toUtc();
    await (update(
      localCollectionsRows,
    )..where((t) => t.id.equals(collectionId))).write(
      LocalCollectionsRowsCompanion(
        name: name != null ? Value<String>(name.trim()) : const Value.absent(),
        ordered: ordered != null ? Value<bool>(ordered) : const Value.absent(),
        seriesIdsJson: seriesIds != null
            ? Value<String>(jsonEncode(_dedupIds(seriesIds)))
            : const Value.absent(),
        updatedAt: Value<DateTime>(now),
      ),
    );
  }

  Future<void> removeLocalCollection(String collectionId) => (delete(
    localCollectionsRows,
  )..where((t) => t.id.equals(collectionId))).go();

  Future<PageResult<Series>> queryLocalCollectionSeries(
    String collectionId, {
    int page = 0,
    int size = 20,
  }) async {
    final col = await localCollectionById(collectionId);
    if (col == null || col.seriesIds.isEmpty) {
      return PageResult<Series>(
        items: const <Series>[],
        totalElements: 0,
        page: page,
        size: size,
      );
    }
    final resolved = <Series>[];
    for (final sid in col.seriesIds) {
      final s = await localSeriesById(sid);
      if (s != null) resolved.add(s);
    }
    if (!col.ordered) {
      resolved.sort(
        (a, b) =>
            normalizeTitleSort(a.title).compareTo(normalizeTitleSort(b.title)),
      );
    }
    return PageResult<Series>(
      items: _slice(resolved, page, size),
      totalElements: resolved.length,
      page: page,
      size: size,
    );
  }

  Future<PageResult<ReadList>> queryLocalReadLists({
    int page = 0,
    int size = 20,
  }) async {
    final rows =
        await (select(localReadListsRows)
              ..orderBy(<OrderClauseGenerator<LocalReadListsRows>>[
                (t) => OrderingTerm(expression: t.name),
              ]))
            .get();
    final all = rows.map(_mapReadList).toList(growable: false);
    return PageResult<ReadList>(
      items: _slice(all, page, size),
      totalElements: all.length,
      page: page,
      size: size,
    );
  }

  Future<ReadList?> localReadListById(String readListId) async {
    final row = await (select(
      localReadListsRows,
    )..where((t) => t.id.equals(readListId))).getSingleOrNull();
    return row == null ? null : _mapReadList(row);
  }

  Future<List<ReadList>> localBookReadLists(String bookId) async {
    final rows = await select(localReadListsRows).get();
    final result = <ReadList>[];
    for (final row in rows) {
      final rl = _mapReadList(row);
      if (rl.bookIds.contains(bookId)) {
        result.add(rl);
      }
    }
    return result;
  }

  Future<ReadList> insertLocalReadList({
    required String id,
    required String name,
    String summary = '',
    required List<String> bookIds,
    bool ordered = false,
  }) async {
    final now = DateTime.now().toUtc();
    final uniqueIds = _dedupIds(bookIds);
    await into(localReadListsRows).insert(
      LocalReadListsRowsCompanion.insert(
        id: id,
        name: name.trim(),
        summary: Value<String>(summary.trim()),
        ordered: Value<bool>(ordered),
        bookIdsJson: Value<String>(jsonEncode(uniqueIds)),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return ReadList(
      id: id,
      name: name.trim(),
      summary: summary.trim(),
      ordered: ordered,
      bookIds: uniqueIds,
      createdDate: now,
      lastModifiedDate: now,
      sourceKey: kLocalSourceKey,
    );
  }

  Future<void> modifyLocalReadList(
    String readListId, {
    String? name,
    String? summary,
    bool? ordered,
    List<String>? bookIds,
  }) async {
    final now = DateTime.now().toUtc();
    await (update(
      localReadListsRows,
    )..where((t) => t.id.equals(readListId))).write(
      LocalReadListsRowsCompanion(
        name: name != null ? Value<String>(name.trim()) : const Value.absent(),
        summary: summary != null
            ? Value<String>(summary.trim())
            : const Value.absent(),
        ordered: ordered != null ? Value<bool>(ordered) : const Value.absent(),
        bookIdsJson: bookIds != null
            ? Value<String>(jsonEncode(_dedupIds(bookIds)))
            : const Value.absent(),
        updatedAt: Value<DateTime>(now),
      ),
    );
  }

  Future<void> removeLocalReadList(String readListId) =>
      (delete(localReadListsRows)..where((t) => t.id.equals(readListId))).go();

  Future<PageResult<Book>> queryLocalReadListBooks(
    String readListId, {
    int page = 0,
    int size = 20,
  }) async {
    final rl = await localReadListById(readListId);
    if (rl == null || rl.bookIds.isEmpty) {
      return PageResult<Book>(
        items: const <Book>[],
        totalElements: 0,
        page: page,
        size: size,
      );
    }
    final resolved = <Book>[];
    for (final bid in rl.bookIds) {
      final b = await localBookById(bid);
      if (b != null) resolved.add(b);
    }
    return PageResult<Book>(
      items: _slice(resolved, page, size),
      totalElements: resolved.length,
      page: page,
      size: size,
    );
  }
}

Collection _mapCollection(LocalCollectionsRow row) => Collection(
  id: row.id,
  name: row.name,
  ordered: row.ordered,
  seriesIds: decodeJsonStringList(row.seriesIdsJson),
  createdDate: row.createdAt.toUtc(),
  lastModifiedDate: row.updatedAt.toUtc(),
  sourceKey: kLocalSourceKey,
);

ReadList _mapReadList(LocalReadListsRow row) => ReadList(
  id: row.id,
  name: row.name,
  summary: row.summary,
  ordered: row.ordered,
  bookIds: decodeJsonStringList(row.bookIdsJson),
  createdDate: row.createdAt.toUtc(),
  lastModifiedDate: row.updatedAt.toUtc(),
  sourceKey: kLocalSourceKey,
);

List<String> _dedupIds(Iterable<String> raw) {
  final seen = <String>{};
  return <String>[
    for (final id in raw)
      if (id.isNotEmpty && seen.add(id)) id,
  ];
}

List<T> _slice<T>(List<T> all, int page, int size) {
  if (size <= 0 || page < 0) return <T>[];
  final start = page * size;
  if (start >= all.length) return <T>[];
  return all.sublist(start, (start + size).clamp(start, all.length));
}
