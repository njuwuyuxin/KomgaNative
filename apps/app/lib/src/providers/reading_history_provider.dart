import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';
import 'package:komga_native/src/data/reading_session_tracker.dart';
import 'package:komga_native/src/providers/cache_providers.dart';

/// 最近的阅读会话（HIS-02 History 页用）。
final FutureProvider<List<ReadingSession>> readingSessionsProvider =
    FutureProvider<List<ReadingSession>>((Ref ref) {
      return ref.watch(httpCacheDatabaseProvider).readingSessionList();
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

  Future<void> record(ReadingSessionDraft draft) async {
    try {
      await _ref
          .read(httpCacheDatabaseProvider)
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
