import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_native/src/data/progress/progress_database.dart';
import 'package:komga_native/src/data/reading_session_tracker.dart';
import 'package:komga_native/src/providers/progress_providers.dart';

export 'package:komga_native/src/data/progress/progress_database.dart'
    show ReadingSession;

/// 最近的阅读会话（HIS-02 History 页用，存储于用户库 `komga_native.sqlite`）。
final FutureProvider<List<ReadingSession>> readingSessionsProvider =
    FutureProvider<List<ReadingSession>>((Ref ref) {
      return ref.watch(progressDatabaseProvider).readingSessionList();
    });

/// 写入一次阅读会话（HIS-01）。
///
/// 写失败只影响"历史少一条"，绝不能打断退出阅读器这件事。
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
      _ref.invalidate(readingSessionsProvider);
    } on Object {
      // 见 [record]。
    }
  }

  Future<void> clear() async {
    try {
      await _ref.read(progressDatabaseProvider).clearReadingSessions();
      _ref.invalidate(readingSessionsProvider);
    } on Object {
      // 见 [record]。
    }
  }

  Future<void> record(ReadingSessionDraft draft) async {
    try {
      await _ref
          .read(progressDatabaseProvider)
          .addReadingSession(
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
      _ref.invalidate(readingSessionsProvider);
    } on Object {
      // 见类注释：历史记录不该影响阅读本身。
    }
  }
}
