import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/progress/bookmarks_dao.dart';
import 'package:yomu/src/providers/komga_session_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu_domain/yomu_domain.dart';

String _bookmarkScopeFor(Ref ref, String bookId) {
  if (bookId.startsWith('local:')) return kLocalSourceKey;
  return ref.watch(komgaSessionProvider)?.address.baseUrl ?? '';
}

/// 单本书内部章节目录（EPUB TOC / 多子目录 / `ComicInfo.xml` 书签，LMB-05）。
final bookChaptersProvider = FutureProvider.autoDispose
    .family<List<BookChapter>, String>((Ref ref, String bookId) async {
      if (!bookId.startsWith('local:')) return const <BookChapter>[];
      final db = ref.watch(progressDatabaseProvider);
      return db.bookChapters(bookId);
    });

/// 单本书的通用页级书签实时流（同时覆盖本机漫画与 Komga 远程漫画）。
final bookBookmarksProvider = StreamProvider.autoDispose
    .family<List<PageBookmark>, String>((Ref ref, String bookId) async* {
      final db = ref.watch(progressDatabaseProvider);
      final scope = _bookmarkScopeFor(ref, bookId);
      yield await db.pageBookmarks(scope: scope, bookId: bookId);
      await for (final _ in db.pageBookmarksUpdates()) {
        yield await db.pageBookmarks(scope: scope, bookId: bookId);
      }
    });

/// 页级书签变更控制器（Widget 不直接碰 DB，统一经本控制器派发）。
final Provider<PageBookmarkController> bookmarkControllerProvider =
    Provider<PageBookmarkController>((Ref ref) => PageBookmarkController(ref));

final class PageBookmarkController {
  const PageBookmarkController(this._ref);

  final Ref _ref;

  String _currentScope(String bookId) {
    if (bookId.startsWith('local:')) return kLocalSourceKey;
    return _ref.read(komgaSessionProvider)?.address.baseUrl ?? '';
  }

  /// 切换某页的书签状态；返回切换后是否已添加（`true` 新增，`false` 移除）。
  Future<bool> toggle({
    required String bookId,
    required int page,
    String note = '',
  }) {
    final db = _ref.read(progressDatabaseProvider);
    return db.togglePageBookmark(
      scope: _currentScope(bookId),
      bookId: bookId,
      page: page,
      note: note,
    );
  }

  Future<void> remove({required String bookId, required int page}) {
    final db = _ref.read(progressDatabaseProvider);
    return db.removePageBookmark(
      scope: _currentScope(bookId),
      bookId: bookId,
      page: page,
    );
  }
}
