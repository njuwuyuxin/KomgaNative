import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/reading_stats.dart';

/// HIS-03：Insights 的统计口径（连续天数/最长连续/周月汇总/热力图）。
void main() {
  final now = DateTime(2026, 11, 20, 15); // 本地时间，周五

  ReadingSession session({
    required String bookId,
    required DateTime startedAt,
    int minutes = 10,
  }) => ReadingSession(
    id: 0,
    scope: '',
    bookId: bookId,
    seriesId: 's1',
    bookName: 'Vol. $bookId',
    startedAt: startedAt,
    endedAt: startedAt.add(Duration(minutes: minutes)),
    durationMs: minutes * 60 * 1000,
    startPage: 1,
    endPage: 10,
    completed: false,
  );

  test('空数据不崩，全是 0', () {
    final stats = ReadingStats.fromSessions(const <ReadingSession>[], now: now);
    expect(stats.isEmpty, isTrue);
    expect(stats.currentStreak, 0);
    expect(stats.longestStreak, 0);
    expect(stats.days.length, 84, reason: '12 周 × 7 天');
    expect(stats.weekMinutes, 0);
  });

  test('今天读过：连续天数从今天往回数', () {
    final stats = ReadingStats.fromSessions(<ReadingSession>[
      session(bookId: 'b1', startedAt: DateTime(2026, 11, 20, 9)),
      session(bookId: 'b1', startedAt: DateTime(2026, 11, 19, 9)),
      session(bookId: 'b1', startedAt: DateTime(2026, 11, 18, 9)),
    ], now: now);
    expect(stats.currentStreak, 3);
    expect(stats.longestStreak, 3);
  });

  test('今天没读、昨天读了：连续天数不清零', () {
    final stats = ReadingStats.fromSessions(<ReadingSession>[
      session(bookId: 'b1', startedAt: DateTime(2026, 11, 19, 9)),
      session(bookId: 'b1', startedAt: DateTime(2026, 11, 18, 9)),
    ], now: now);
    expect(stats.currentStreak, 2);
  });

  test('中断两天就归零；最长连续保留历史最长', () {
    final stats = ReadingStats.fromSessions(<ReadingSession>[
      // 一段 4 天的连续（很久以前）。
      session(bookId: 'b1', startedAt: DateTime(2026, 10, 1, 9)),
      session(bookId: 'b1', startedAt: DateTime(2026, 10, 2, 9)),
      session(bookId: 'b1', startedAt: DateTime(2026, 10, 3, 9)),
      session(bookId: 'b1', startedAt: DateTime(2026, 10, 4, 9)),
      // 最近读过一次，但之后断了两天。
      session(bookId: 'b1', startedAt: DateTime(2026, 11, 17, 9)),
    ], now: now);
    expect(stats.currentStreak, 0, reason: '昨天和今天都没读');
    expect(stats.longestStreak, 4);
  });

  test('同一天多次阅读累加时长、书按去重算', () {
    final stats = ReadingStats.fromSessions(<ReadingSession>[
      session(bookId: 'b1', startedAt: DateTime(2026, 11, 20, 9), minutes: 5),
      session(bookId: 'b2', startedAt: DateTime(2026, 11, 20, 10), minutes: 7),
      session(bookId: 'b2', startedAt: DateTime(2026, 11, 20, 11), minutes: 3),
    ], now: now);
    expect(stats.weekMinutes, 15);
    expect(stats.weekBooks, 2, reason: 'b2 读了两次也只算一本');
    expect(stats.monthMinutes, 15);
    final today = stats.days.last;
    expect(today.minutes, 15);
    expect(today.books, 2);
  });

  test('跨日边界：23:59 与次日 00:01 算两天', () {
    final stats = ReadingStats.fromSessions(<ReadingSession>[
      session(bookId: 'b1', startedAt: DateTime(2026, 11, 19, 23, 59)),
      session(bookId: 'b1', startedAt: DateTime(2026, 11, 20, 0, 1)),
    ], now: now);
    expect(stats.currentStreak, 2);
    expect(stats.days[stats.days.length - 2].minutes, 10);
    expect(stats.days.last.minutes, 10);
  });

  test('坏数据（时长为 0 / 未来时间）被跳过', () {
    final stats = ReadingStats.fromSessions(<ReadingSession>[
      session(bookId: 'b1', startedAt: DateTime(2026, 11, 20, 9), minutes: 0),
      session(bookId: 'b2', startedAt: DateTime(2027, 1, 1, 9)),
      session(bookId: 'b3', startedAt: DateTime(2026, 11, 20, 10), minutes: 4),
    ], now: now);
    expect(stats.totalMinutes, 4);
    expect(stats.currentStreak, 1);
  });

  test('当天读过的书按去重汇总，按最近阅读时间倒序，并记录 latestActiveDate', () {
    final stats = ReadingStats.fromSessions(<ReadingSession>[
      session(bookId: 'b1', startedAt: DateTime(2026, 11, 18, 9), minutes: 6),
      session(bookId: 'b2', startedAt: DateTime(2026, 11, 19, 8), minutes: 5),
      session(bookId: 'b1', startedAt: DateTime(2026, 11, 19, 10), minutes: 7),
      session(bookId: 'b2', startedAt: DateTime(2026, 11, 19, 12), minutes: 9),
    ], now: now);

    expect(stats.latestActiveDate, DateTime(2026, 11, 19));
    final day = stats.dayOf(DateTime(2026, 11, 19));
    expect(day.minutes, 21);
    expect(day.books, 2);
    expect(
      day.readBooks.map((ReadingDayBook b) => (b.bookId, b.minutes)).toList(),
      <(String, int)>[('b2', 14), ('b1', 7)],
    );
    expect(stats.dayOf(DateTime(2026, 11, 20)).readBooks, isEmpty);
  });

  test('heatmapWeeks 按自然周周一..周日对齐，今天之后的格子为 null', () {
    // 2026-11-20 是周五（weekday == 5）。
    final stats = ReadingStats.fromSessions(<ReadingSession>[
      session(bookId: 'b1', startedAt: DateTime(2026, 11, 20, 9), minutes: 12),
    ], now: now);
    final weeks = stats.heatmapWeeks(today: now, weeks: 12);

    expect(weeks.length, 12);
    for (final col in weeks) {
      expect(col.length, 7);
    }
    // 第一列周一
    expect(weeks.first.first!.date.weekday, DateTime.monday);
    // 最后一列周一..周五有值，周六/周日为未来日期 null
    final lastCol = weeks.last;
    expect(lastCol[0]!.date, DateTime(2026, 11, 16));
    expect(lastCol[4]!.date, DateTime(2026, 11, 20));
    expect(lastCol[4]!.minutes, 12);
    expect(lastCol[5], isNull);
    expect(lastCol[6], isNull);
    expect(stats.heatmapWeeks(today: now, weeks: 0), isEmpty);
  });

  test('heatmapLevel 与 heatmapWeekCountForWidth 边界值', () {
    ReadingDay d(int minutes) =>
        ReadingDay(date: DateTime(2026, 11, 20), minutes: minutes, books: 1);

    expect(ReadingStats.heatmapLevel(d(0), 40), 0);
    expect(ReadingStats.heatmapLevel(d(10), 40), 1);
    expect(ReadingStats.heatmapLevel(d(20), 40), 2);
    expect(ReadingStats.heatmapLevel(d(30), 40), 3);
    expect(ReadingStats.heatmapLevel(d(40), 40), 4);
    expect(ReadingStats.heatmapLevel(d(5), 0), 4);

    expect(
      ReadingStats.heatmapWeekCountForWidth(0, cellTarget: 24, gap: 4),
      12,
    );
    expect(
      ReadingStats.heatmapWeekCountForWidth(326, cellTarget: 24, gap: 4),
      12,
    );
    expect(
      ReadingStats.heatmapWeekCountForWidth(960, cellTarget: 24, gap: 4),
      34,
    );
    expect(
      ReadingStats.heatmapWeekCountForWidth(5000, cellTarget: 24, gap: 4),
      52,
    );
  });
}
