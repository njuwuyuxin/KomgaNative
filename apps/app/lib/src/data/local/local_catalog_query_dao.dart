import 'package:drift/drift.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// [ProgressDatabase] 的本地书架、系列与章节列表查询扩展。
extension LocalCatalogQueryDao on ProgressDatabase {
  Future<LocalSeriesRow?> localSeriesRowById(String seriesId) => (select(
    localSeriesRows,
  )..where((t) => t.id.equals(seriesId))).getSingleOrNull();

  Future<LocalBooksRow?> localBookRowById(String bookId) => (select(
    localBooksRows,
  )..where((t) => t.id.equals(bookId))).getSingleOrNull();

  /// 返回当前本机书库中所有仍存在的书籍 ID 集合（轻量投影，用于历史页状态校验）。
  Future<Set<String>> existingLocalBookIds() async {
    final query = selectOnly(localBooksRows)
      ..addColumns(<Expression<Object>>[localBooksRows.id]);
    final rows = await query.get();
    return <String>{for (final row in rows) ?row.read(localBooksRows.id)};
  }

  Stream<Set<TableUpdate>> localBooksUpdates() =>
      tableUpdates(TableUpdateQuery.onTable(localBooksRows));

  Future<List<LocalPagesRow>> localPagesForBook(String bookId) =>
      (select(localPagesRows)
            ..where((t) => t.bookId.equals(bookId))
            ..orderBy(<OrderClauseGenerator<LocalPagesRows>>[
              (t) => OrderingTerm(expression: t.pageNumber),
            ]))
          .get();

  Future<Series?> localSeriesById(String seriesId) async {
    final row = await localSeriesRowById(seriesId);
    if (row == null) return null;
    final booksRows = await (select(
      localBooksRows,
    )..where((t) => t.seriesId.equals(seriesId))).get();
    final progressMap = await localProgressByBookIds(
      booksRows.map((b) => b.id),
    );
    return mapLocalSeries(row, booksRows, progressMap);
  }

  Future<Book?> localBookById(String bookId) async {
    final row = await localBookRowById(bookId);
    if (row == null) return null;
    final seriesRow = await localSeriesRowById(row.seriesId);
    final prog = await record(bookId, scope: kLocalSourceKey);
    return mapLocalBook(row, seriesTitle: seriesRow?.title, progress: prog);
  }

  /// 本机系列分页查询（支持关键词搜索、阅读状态过滤、标签过滤与 5 种排序）。
  Future<PageResult<Series>> queryLocalSeries({
    String? query,
    int page = 0,
    int size = 30,
    SeriesSort? sort,
    SeriesReadStatus? readStatus,
    String? tag,
  }) async {
    final seriesRows = await select(localSeriesRows).get();
    if (seriesRows.isEmpty) {
      return PageResult<Series>(
        items: const <Series>[],
        totalElements: 0,
        page: page,
        size: size,
      );
    }

    final allBooks = await select(localBooksRows).get();
    final booksBySeries = <String, List<LocalBooksRow>>{};
    for (final b in allBooks) {
      booksBySeries.putIfAbsent(b.seriesId, () => <LocalBooksRow>[]).add(b);
    }
    final progressMap = await localProgressByBookIds(allBooks.map((b) => b.id));

    final q = (query ?? '').trim().toLowerCase();
    final filterTag = (tag ?? '').trim().toLowerCase();

    final items = <({Series series, LocalSeriesRow row, bool anyStarted})>[];
    for (final row in seriesRows) {
      final sBooks = booksBySeries[row.id] ?? const <LocalBooksRow>[];
      final mapped = mapLocalSeries(row, sBooks, progressMap);
      if (q.isNotEmpty && !_matchesSeriesQuery(mapped, sBooks, q)) continue;
      if (filterTag.isNotEmpty &&
          !mapped.tags.any((t) => t.toLowerCase() == filterTag)) {
        continue;
      }
      final anyStarted = sBooks.any((b) => progressMap.containsKey(b.id));
      if (readStatus != null &&
          !_matchesSeriesReadStatus(
            readStatus,
            booksCount: mapped.booksCount,
            booksReadCount: mapped.booksReadCount,
            anyStarted: anyStarted,
          )) {
        continue;
      }
      items.add((series: mapped, row: row, anyStarted: anyStarted));
    }

    _sortSeriesTuples(items, sort ?? SeriesSort.titleAsc);
    final paged = sliceLocalPage(
      items.map((e) => e.series).toList(growable: false),
      page,
      size,
    );
    return PageResult<Series>(
      items: paged,
      totalElements: items.length,
      page: page,
      size: size,
    );
  }

  /// 系列内书籍列表（按卷号升/降序与阅读状态筛选）。
  Future<PageResult<Book>> queryLocalSeriesBooks(
    String seriesId, {
    int page = 0,
    int size = 100,
    BooksSort? sort,
    SeriesReadStatus? readStatus,
  }) async {
    final seriesRow = await localSeriesRowById(seriesId);
    final rows = await (select(
      localBooksRows,
    )..where((t) => t.seriesId.equals(seriesId))).get();
    final progressMap = await localProgressByBookIds(rows.map((b) => b.id));

    rows.sort((a, b) {
      final cmp = a.numberSort.compareTo(b.numberSort);
      if (cmp != 0) return sort == BooksSort.numberDesc ? -cmp : cmp;
      final nameCmp = a.name.compareTo(b.name);
      return sort == BooksSort.numberDesc ? -nameCmp : nameCmp;
    });

    final books = <Book>[];
    for (final row in rows) {
      final book = mapLocalBook(
        row,
        seriesTitle: seriesRow?.title,
        progress: progressMap[row.id],
      );
      if (readStatus != null && !_matchesBookReadStatus(readStatus, book)) {
        continue;
      }
      books.add(book);
    }

    return PageResult<Book>(
      items: sliceLocalPage(books, page, size),
      totalElements: books.length,
      page: page,
      size: size,
    );
  }

  Future<Map<String, LocalProgressData>> localProgressByBookIds(
    Iterable<String> ids,
  ) async {
    final list = ids.toSet().toList(growable: false);
    if (list.isEmpty) return const <String, LocalProgressData>{};
    final rows = await records(list, scope: kLocalSourceKey);
    return <String, LocalProgressData>{for (final r in rows) r.bookId: r};
  }
}

Series mapLocalSeries(
  LocalSeriesRow row,
  List<LocalBooksRow> books,
  Map<String, LocalProgressData> progressMap,
) {
  var readCount = 0;
  for (final b in books) {
    if (progressMap[b.id]?.completed ?? false) readCount++;
  }
  final direction = ReadingDirection.values.firstWhere(
    (d) => d.name == row.readingDirection,
    orElse: () => ReadingDirection.unknown,
  );
  return Series(
    id: row.id,
    libraryId: kLocalLibraryId,
    title: row.title,
    booksCount: books.length,
    booksReadCount: readCount,
    readingDirection: direction,
    summary: row.summary.isEmpty ? null : row.summary,
    authors: decodeJsonStringList(row.authorsJson),
    publisher: row.publisher.isEmpty ? null : row.publisher,
    releaseDate: row.releaseDate,
    tags: decodeJsonStringList(row.tagsJson),
    sourceKey: kLocalSourceKey,
  );
}

Book mapLocalBook(
  LocalBooksRow row, {
  String? seriesTitle,
  LocalProgressData? progress,
}) {
  return Book(
    id: row.id,
    seriesId: row.seriesId,
    name: row.name,
    seriesTitle: seriesTitle,
    number: row.number,
    pagesCount: row.pagesCount,
    mediaProfile: MediaProfile.divina,
    sizeBytes: row.sizeBytes,
    sourceKey: kLocalSourceKey,
    readProgress: progress == null
        ? null
        : ReadProgress(
            page: progress.page,
            completed: progress.completed,
            lastModified: progress.updatedAt.toUtc(),
          ),
  );
}

List<T> sliceLocalPage<T>(List<T> all, int page, int size) {
  if (size <= 0 || page < 0) return <T>[];
  final start = page * size;
  if (start >= all.length) return <T>[];
  return all.sublist(start, (start + size).clamp(start, all.length));
}

bool _matchesSeriesQuery(Series series, List<LocalBooksRow> books, String q) {
  if (series.title.toLowerCase().contains(q)) return true;
  if ((series.publisher ?? '').toLowerCase().contains(q)) return true;
  if (series.authors.any((a) => a.toLowerCase().contains(q))) return true;
  if (series.tags.any((t) => t.toLowerCase().contains(q))) return true;
  return books.any((b) => b.name.toLowerCase().contains(q));
}

bool _matchesSeriesReadStatus(
  SeriesReadStatus status, {
  required int booksCount,
  required int booksReadCount,
  required bool anyStarted,
}) {
  return switch (status) {
    SeriesReadStatus.unread => booksReadCount == 0 && !anyStarted,
    SeriesReadStatus.read => booksCount > 0 && booksReadCount >= booksCount,
    SeriesReadStatus.inProgress =>
      (booksReadCount > 0 && booksReadCount < booksCount) ||
          (booksReadCount == 0 && anyStarted),
  };
}

bool _matchesBookReadStatus(SeriesReadStatus status, Book book) {
  return switch (status) {
    SeriesReadStatus.unread => book.isUnread,
    SeriesReadStatus.read => book.isCompleted,
    SeriesReadStatus.inProgress => !book.isUnread && !book.isCompleted,
  };
}

void _sortSeriesTuples(
  List<({Series series, LocalSeriesRow row, bool anyStarted})> list,
  SeriesSort sort,
) {
  list.sort((a, b) {
    switch (sort) {
      case SeriesSort.titleAsc:
        return a.row.titleSort.compareTo(b.row.titleSort);
      case SeriesSort.titleDesc:
        return b.row.titleSort.compareTo(a.row.titleSort);
      case SeriesSort.recentlyAdded:
        return b.row.createdAt.compareTo(a.row.createdAt);
      case SeriesSort.booksCountDesc:
        final c = b.series.booksCount.compareTo(a.series.booksCount);
        return c != 0 ? c : a.row.titleSort.compareTo(b.row.titleSort);
      case SeriesSort.releaseDateDesc:
        final da = a.series.releaseDate;
        final db = b.series.releaseDate;
        if (da == null && db == null) {
          return a.row.titleSort.compareTo(b.row.titleSort);
        }
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
    }
  });
}
