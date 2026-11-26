import 'package:drift/drift.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// [ProgressDatabase] 的单书内部章节目录与通用页级书签 DAO（LMB-05）。
extension BookmarksDao on ProgressDatabase {
  /// 读取本地书籍持久化的内部章节列表（按 `chapterIndex` 排序）。
  Future<List<BookChapter>> bookChapters(String bookId) async {
    final rows =
        await (select(localBookChaptersRows)
              ..where((t) => t.bookId.equals(bookId))
              ..orderBy(<OrderClauseGenerator<LocalBookChaptersRows>>[
                (t) => OrderingTerm(expression: t.chapterIndex),
              ]))
            .get();
    return <BookChapter>[
      for (final r in rows) BookChapter(title: r.title, startPage: r.startPage),
    ];
  }

  /// 读取某本书的页级书签列表（按页码升序）。
  Future<List<PageBookmark>> pageBookmarks({
    required String scope,
    required String bookId,
  }) async {
    final rows =
        await (select(pageBookmarksRows)
              ..where((t) => t.scope.equals(scope) & t.bookId.equals(bookId))
              ..orderBy(<OrderClauseGenerator<PageBookmarksRows>>[
                (t) => OrderingTerm(expression: t.page),
              ]))
            .get();
    return <PageBookmark>[
      for (final r in rows)
        PageBookmark(
          scope: r.scope,
          bookId: r.bookId,
          page: r.page,
          note: r.note,
          createdAt: r.createdAt,
        ),
    ];
  }

  /// 切换某页的书签状态；返回切换后是否已添加（`true` 新增，`false` 移除）。
  Future<bool> togglePageBookmark({
    required String scope,
    required String bookId,
    required int page,
    String note = '',
    DateTime? nowOverride,
  }) async {
    final existing =
        await (select(pageBookmarksRows)..where(
              (t) =>
                  t.scope.equals(scope) &
                  t.bookId.equals(bookId) &
                  t.page.equals(page),
            ))
            .getSingleOrNull();
    if (existing != null) {
      await removePageBookmark(scope: scope, bookId: bookId, page: page);
      return false;
    }
    await into(pageBookmarksRows).insertOnConflictUpdate(
      PageBookmarksRowsCompanion.insert(
        scope: Value<String>(scope),
        bookId: bookId,
        page: page,
        note: Value<String>(note),
        createdAt: (nowOverride ?? DateTime.now()).toUtc(),
      ),
    );
    return true;
  }

  Future<void> removePageBookmark({
    required String scope,
    required String bookId,
    required int page,
  }) =>
      (delete(pageBookmarksRows)..where(
            (t) =>
                t.scope.equals(scope) &
                t.bookId.equals(bookId) &
                t.page.equals(page),
          ))
          .go();

  Stream<Set<TableUpdate>> pageBookmarksUpdates() =>
      tableUpdates(TableUpdateQuery.onTable(pageBookmarksRows));
}
