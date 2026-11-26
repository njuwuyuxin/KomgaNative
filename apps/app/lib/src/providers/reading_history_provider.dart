import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/reading_session_tracker.dart';
import 'package:yomu/src/providers/pinned_series_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_domain/yomu_domain.dart';

export 'package:yomu/src/data/progress/progress_database.dart'
    show ReadingSession;

/// 最近阅读会话（汇聚本机 `'local://device'` 与当前连接服务器，不同远程服务器之间严格隔离）。
final FutureProvider<List<ReadingSession>> readingSessionsProvider =
    FutureProvider<List<ReadingSession>>((Ref ref) {
      final activeScope = ref.watch(activeServerKeyProvider);
      final session = ref.watch(sessionProvider);
      final scopes = <String>{
        kLocalSourceKey,
        if (activeScope.isNotEmpty) activeScope,
        if (session is SessionConnected) session.server.address.baseUrl,
      };
      final db = ref.watch(progressDatabaseProvider);
      final sub = db.readingSessionsUpdates().listen(
        (_) => ref.invalidateSelf(),
      );
      ref.onDispose(sub.cancel);
      return db.readingSessionList(scopes: scopes);
    });

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

  Future<void> clear() async {
    try {
      final scope = _ref.read(activeServerKeyProvider);
      await _ref
          .read(progressDatabaseProvider)
          .clearReadingSessions(scope: scope);
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
