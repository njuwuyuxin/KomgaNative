import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/reading_session_tracker.dart';
import 'package:yomu/src/providers/pinned_series_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_domain/yomu_domain.dart';

export 'package:yomu/src/data/progress/progress_database.dart'
    show ReadingSession;

Set<String> _readingSessionScopes({
  required String activeScope,
  required SessionState session,
}) => <String>{
  kLocalSourceKey,
  if (activeScope.isNotEmpty) activeScope,
  if (session is SessionConnected) session.server.address.baseUrl,
};

/// 最近阅读会话（汇聚本机 `'local://device'` 与当前连接服务器，不同远程服务器之间严格隔离）。
final FutureProvider<List<ReadingSession>> readingSessionsProvider =
    FutureProvider<List<ReadingSession>>((Ref ref) {
      final activeScope = ref.watch(activeServerKeyProvider);
      final session = ref.watch(sessionProvider);
      final scopes = _readingSessionScopes(
        activeScope: activeScope,
        session: session,
      );
      final db = ref.watch(progressDatabaseProvider);
      final sub = db.readingSessionsUpdates().listen(
        (_) => ref.invalidateSelf(),
      );
      ref.onDispose(sub.cancel);
      return db.readingSessionList(scopes: scopes);
    });

/// 当前本机书库中仍然存在的书籍 ID 集合（随 `local_books_rows` 变更自动刷新）。
///
/// 用于在保留 `reading_sessions`（保住 `InsightsScreen` 统计与热力图）的前提下，
/// 于「最近阅读」过滤已删本机书并在「阅读历史」标记已移除状态。
final FutureProvider<Set<String>> existingLocalBookIdsProvider =
    FutureProvider<Set<String>>((Ref ref) {
      final db = ref.watch(progressDatabaseProvider);
      final sub = db.localBooksUpdates().listen((_) => ref.invalidateSelf());
      ref.onDispose(sub.cancel);
      return db.existingLocalBookIds();
    });

/// 判断一条阅读会话是否指向已从本机书库移除的书籍。
///
/// 仅当 `session.scope` 明确为本机源且 [existingLocalBookIds] 已加载完毕时才判定为已移除；
/// 加载中（`null`）或远程服务器/旧版空 scope 记录一律视为可用，避免误标。
bool isRemovedLocalSession(
  ReadingSession session,
  Set<String>? existingLocalBookIds,
) {
  if (existingLocalBookIds == null) return false;
  if (!isLocalSourceKey(session.scope)) return false;
  return !existingLocalBookIds.contains(session.bookId);
}

/// 写入一次阅读会话（HIS-01；写入/删除后由 Drift 流自动通知所有监听页）。
final Provider<ReadingSessionRecorder> readingSessionRecorderProvider =
    Provider<ReadingSessionRecorder>((Ref ref) {
      return ReadingSessionRecorder(ref);
    });

class ReadingSessionRecorder {
  ReadingSessionRecorder(this._ref);

  final Ref _ref;

  Future<void> delete(int id) async {
    try {
      await _ref.read(progressDatabaseProvider).deleteReadingSession(id);
    } on Object catch (error) {
      // 见 [record]。
      debugPrint('ReadingSessionRecorder: delete($id) failed: $error');
    }
  }

  Future<void> deleteMany(Iterable<int> ids) async {
    try {
      await _ref.read(progressDatabaseProvider).deleteReadingSessions(ids);
    } on Object catch (error) {
      // 见 [record]。
      debugPrint('ReadingSessionRecorder: deleteMany failed: $error');
    }
  }

  Future<void> clear() async {
    try {
      final scopes = _readingSessionScopes(
        activeScope: _ref.read(activeServerKeyProvider),
        session: _ref.read(sessionProvider),
      );
      await _ref
          .read(progressDatabaseProvider)
          .clearReadingSessions(scopes: scopes);
    } on Object catch (error) {
      // 见 [record]。
      debugPrint('ReadingSessionRecorder: clear failed: $error');
    }
  }

  Future<void> record(ReadingSessionDraft draft, {String? scope}) async {
    try {
      final String targetScope = scope ?? _ref.read(activeServerKeyProvider);
      await _ref
          .read(progressDatabaseProvider)
          .addReadingSession(
            scope: targetScope,
            bookId: draft.bookId,
            seriesId: draft.seriesId,
            bookName: draft.bookName,
            startedAt: draft.startedAt,
            endedAt: draft.endedAt,
            durationMs: draft.duration.inMilliseconds,
            startPage: draft.startPage,
            endPage: draft.endPage,
            completed: draft.completed,
          );
    } on Object catch (error) {
      // 历史记录不该影响阅读本身。
      debugPrint(
        'ReadingSessionRecorder: record(${draft.bookId}) failed: $error',
      );
    }
  }
}
