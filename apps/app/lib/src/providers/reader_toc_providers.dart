import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/progress/bookmarks_dao.dart';
import 'package:yomu/src/providers/pinned_series_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 按显式 `sourceKey` 寻址单本书的章节与页级书签。
typedef BookTocQuery = ({String? sourceKey, String bookId});

String _resolveTocScope(Ref ref, String? sourceKey) {
  if (sourceKey != null && sourceKey.isNotEmpty) return sourceKey;
  return ref.watch(activeServerKeyProvider);
}

/// 单本书内部章节目录（EPUB TOC / 多子目录 / `ComicInfo.xml` 书签，LMB-05）。
final bookChaptersProvider = FutureProvider.autoDispose
    .family<List<BookChapter>, BookTocQuery>((
      Ref ref,
      BookTocQuery query,
    ) async {
      final scope = _resolveTocScope(ref, query.sourceKey);
      if (!isLocalSourceKey(scope)) return const <BookChapter>[];
      final db = ref.watch(progressDatabaseProvider);
      return db.bookChapters(query.bookId);
    });

/// 单本书的通用页级书签实时流（同时覆盖本机漫画与多台 Komga 远程漫画）。
final bookBookmarksProvider = StreamProvider.autoDispose
    .family<List<PageBookmark>, BookTocQuery>((
      Ref ref,
      BookTocQuery query,
    ) async* {
      final db = ref.watch(progressDatabaseProvider);
      final scope = _resolveTocScope(ref, query.sourceKey);
      yield await db.pageBookmarks(scope: scope, bookId: query.bookId);
      await for (final _ in db.pageBookmarksUpdates()) {
        yield await db.pageBookmarks(scope: scope, bookId: query.bookId);
      }
    });

/// 页级书签变更控制器（Widget 不直接碰 DB，统一经本控制器派发）。
final Provider<PageBookmarkController> bookmarkControllerProvider =
    Provider<PageBookmarkController>(PageBookmarkController.new);

final class PageBookmarkController {
  const PageBookmarkController(this._ref);

  final Ref _ref;

  String _resolveScope(String? sourceKey) {
    if (sourceKey != null && sourceKey.isNotEmpty) return sourceKey;
    return _ref.read(activeServerKeyProvider);
  }

  /// 切换某页的书签状态；返回切换后是否已添加（`true` 新增，`false` 移除）。
  Future<bool> toggle({
    required String bookId,
    required int page,
    String? sourceKey,
    String note = '',
  }) {
    final db = _ref.read(progressDatabaseProvider);
    return db.togglePageBookmark(
      scope: _resolveScope(sourceKey),
      bookId: bookId,
      page: page,
      note: note,
    );
  }

  Future<void> remove({
    required String bookId,
    required int page,
    String? sourceKey,
  }) {
    final db = _ref.read(progressDatabaseProvider);
    return db.removePageBookmark(
      scope: _resolveScope(sourceKey),
      bookId: bookId,
      page: page,
    );
  }
}
