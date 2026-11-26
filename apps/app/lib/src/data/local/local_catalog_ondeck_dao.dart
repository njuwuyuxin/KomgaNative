import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// [ProgressDatabase] 的本地全局书籍搜索与「继续阅读 / 下一卷推导」查询扩展。
extension LocalCatalogOndeckDao on ProgressDatabase {
  /// 全局本地书籍关键词搜索。
  Future<PageResult<Book>> searchLocalBooks(
    String query, {
    int page = 0,
    int size = 20,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return PageResult<Book>(
        items: const <Book>[],
        totalElements: 0,
        page: page,
        size: size,
      );
    }
    final seriesById = <String, LocalSeriesRow>{
      for (final s in await select(localSeriesRows).get()) s.id: s,
    };
    final allBooks = await select(localBooksRows).get();
    final progressMap = await localProgressByBookIds(allBooks.map((b) => b.id));

    final matched = <Book>[];
    for (final row in allBooks) {
      final sTitle = seriesById[row.seriesId]?.title ?? '';
      if (row.name.toLowerCase().contains(q) ||
          sTitle.toLowerCase().contains(q) ||
          row.number.toLowerCase().contains(q)) {
        matched.add(
          mapLocalBook(row, seriesTitle: sTitle, progress: progressMap[row.id]),
        );
      }
    }

    return PageResult<Book>(
      items: sliceLocalPage(matched, page, size),
      totalElements: matched.length,
      page: page,
      size: size,
    );
  }

  /// 本机「继续阅读」：在读书按最近阅读时间倒序排前，刚读完某卷的系列自动推导下一卷未读兜底。
  Future<PageResult<Book>> localOndeck({int size = 20}) async {
    final allBooks = await select(localBooksRows).get();
    if (allBooks.isEmpty) {
      return PageResult<Book>(
        items: const <Book>[],
        totalElements: 0,
        page: 0,
        size: size,
      );
    }
    final seriesById = <String, LocalSeriesRow>{
      for (final s in await select(localSeriesRows).get()) s.id: s,
    };
    final progressMap = await localProgressByBookIds(allBooks.map((b) => b.id));

    final inProgress = <({Book book, DateTime updatedAt})>[];
    final activeSeriesIds = <String>{};
    final seriesLatestCompletedAt = <String, DateTime>{};
    final booksBySeries = <String, List<LocalBooksRow>>{};

    for (final row in allBooks) {
      booksBySeries.putIfAbsent(row.seriesId, () => <LocalBooksRow>[]).add(row);
      final prog = progressMap[row.id];
      if (prog == null) continue;
      if (!prog.completed) {
        activeSeriesIds.add(row.seriesId);
        inProgress.add((
          book: mapLocalBook(
            row,
            seriesTitle: seriesById[row.seriesId]?.title,
            progress: prog,
          ),
          updatedAt: prog.updatedAt,
        ));
      } else {
        final prev = seriesLatestCompletedAt[row.seriesId];
        if (prev == null || prog.updatedAt.isAfter(prev)) {
          seriesLatestCompletedAt[row.seriesId] = prog.updatedAt;
        }
      }
    }

    inProgress.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final upNext = <({Book book, DateTime completedAt})>[];
    for (final entry in seriesLatestCompletedAt.entries) {
      final sid = entry.key;
      if (activeSeriesIds.contains(sid)) continue;
      final siblings = booksBySeries[sid];
      if (siblings == null || siblings.isEmpty) continue;
      siblings.sort((a, b) {
        final c = a.numberSort.compareTo(b.numberSort);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
      for (final candidate in siblings) {
        if (!progressMap.containsKey(candidate.id)) {
          upNext.add((
            book: mapLocalBook(candidate, seriesTitle: seriesById[sid]?.title),
            completedAt: entry.value,
          ));
          break;
        }
      }
    }
    upNext.sort((a, b) => b.completedAt.compareTo(a.completedAt));

    final merged = <Book>[
      for (final item in inProgress) item.book,
      for (final item in upNext) item.book,
    ];
    final sliced = merged.take(size).toList(growable: false);
    return PageResult<Book>(
      items: sliced,
      totalElements: merged.length,
      page: 0,
      size: size,
    );
  }
}
