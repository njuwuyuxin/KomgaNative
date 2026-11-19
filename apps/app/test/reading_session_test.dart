import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';
import 'package:komga_native/src/data/reading_session_tracker.dart';

/// HIS-01：阅读会话的记账规则与落库。
void main() {
  group('ReadingSessionTracker', () {
    late DateTime now;
    late ReadingSessionTracker tracker;

    setUp(() {
      now = DateTime.utc(2026, 11, 20, 10);
      tracker = ReadingSessionTracker(clock: () => now);
    });

    ReadingSessionDraft? finish({bool completed = false, int? page}) =>
        tracker.finish(
          bookId: 'b1',
          seriesId: 's1',
          bookName: 'Vol. 1',
          completed: completed,
          page: page,
        );

    test('一次阅读产生一条会话，页数从起点到终点', () {
      tracker.start(page: 3);
      now = now.add(const Duration(minutes: 2));
      tracker.note(page: 12);

      final draft = finish(page: 15)!;
      expect(draft.startPage, 3);
      expect(draft.endPage, 15);
      expect(draft.duration, const Duration(minutes: 2));
      expect(draft.completed, isFalse);
    });

    test('不足 10 秒不算（翻目录、误点都会进出一次阅读器）', () {
      tracker.start(page: 1);
      now = now.add(const Duration(seconds: 9));
      expect(finish(), isNull);
    });

    test('切后台的暂停时间不算进时长', () {
      tracker.start(page: 1);
      now = now.add(const Duration(seconds: 30));
      tracker.pause();

      // 后台待了 10 分钟。
      now = now.add(const Duration(minutes: 10));
      tracker.resume();
      now = now.add(const Duration(seconds: 30));

      final draft = finish()!;
      expect(draft.duration, const Duration(seconds: 60));
    });

    test('暂停中翻页不更新 endPage', () {
      tracker.start(page: 1);
      now = now.add(const Duration(seconds: 30));
      tracker.pause();
      // 暂停期间"翻页"（比如后台推送/系统恢复）不该改写读到哪。
      tracker.note(page: 9);
      expect(finish()!.endPage, 1);
    });

    test('重复 start 不会开第二段', () {
      tracker.start(page: 1);
      now = now.add(const Duration(seconds: 30));
      tracker.start(page: 5);
      expect(finish()!.startPage, 1);
    });

    test('finish 之后可以开始新的一次', () {
      tracker.start(page: 1);
      now = now.add(const Duration(seconds: 30));
      expect(finish(), isNotNull);
      expect(tracker.running, isFalse);

      tracker.start(page: 7);
      now = now.add(const Duration(seconds: 30));
      final second = finish()!;
      expect(second.startPage, 7);
    });
  });

  group('reading_sessions 表', () {
    late HttpCacheDatabase db;

    setUp(() => db = HttpCacheDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('写入后能按时间倒序列出，删除与清空生效', () async {
      final early = DateTime.utc(2026, 11, 19, 9);
      final late = DateTime.utc(2026, 11, 20, 9);
      await db.addReadingSession(
        bookId: 'b1',
        seriesId: 's1',
        bookName: 'Vol. 1',
        startedAt: early,
        endedAt: early.add(const Duration(minutes: 5)),
        durationMs: 5 * 60 * 1000,
        startPage: 1,
        endPage: 10,
        completed: true,
      );
      await db.addReadingSession(
        bookId: 'b2',
        seriesId: 's1',
        bookName: 'Vol. 2',
        startedAt: late,
        endedAt: late.add(const Duration(minutes: 7)),
        durationMs: 7 * 60 * 1000,
        startPage: 1,
        endPage: 3,
        completed: false,
      );

      final rows = await db.readingSessionList();
      expect(rows.map((ReadingSession r) => r.bookId), <String>['b2', 'b1']);

      await db.deleteReadingSession(rows.first.id);
      expect((await db.readingSessionList()).length, 1);

      await db.clearReadingSessions();
      expect(await db.readingSessionList(), isEmpty);
    });
  });
}
