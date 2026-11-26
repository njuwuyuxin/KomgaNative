import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/reading_session_tracker.dart';
import 'package:yomu/src/providers/pinned_series_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';

export 'package:yomu/src/data/progress/progress_database.dart'
    show ReadingSession;

/// 当前服务器的最近阅读会话（HIS-02 / ARC-07 / ARC-10 Drift 表更新流自动刷新）。
final FutureProvider<List<ReadingSession>> readingSessionsProvider =
    FutureProvider<List<ReadingSession>>((Ref ref) {
      final scope = ref.watch(activeServerKeyProvider);
      final db = ref.watch(progressDatabaseProvider);
      final sub = db.readingSessionsUpdates().listen(
        (_) => ref.invalidateSelf(),
      );
      ref.onDispose(sub.cancel);
      return db.readingSessionList(scope: scope);
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
    } on Object {
      // 见 [record]。
    }
  }

  Future<void> clear() async {
    try {
      final scope = _ref.read(activeServerKeyProvider);
      await _ref
          .read(progressDatabaseProvider)
          .clearReadingSessions(scope: scope);
    } on Object {
      // 见 [record]。
    }
  }

  Future<void> record(ReadingSessionDraft draft) async {
    try {
      final scope = _ref.read(activeServerKeyProvider);
      await _ref
          .read(progressDatabaseProvider)
          .addReadingSession(
            scope: scope,
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
    } on Object {
      // 见类注释：历史记录不该影响阅读本身。
    }
  }
}
