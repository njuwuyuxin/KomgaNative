import 'dart:math' as math;

import 'package:komga_native/src/data/progress/progress_database.dart';

/// 某一天的阅读量（Insights 热力图的一格）。
class ReadingDay {
  const ReadingDay({
    required this.date,
    required this.minutes,
    required this.books,
  });

  /// 本地日期（时分秒归零），用作热力图的横轴。
  final DateTime date;
  final int minutes;

  /// 这天读过几本不同的书。
  final int books;

  bool get isActive => minutes > 0;
}

/// 阅读统计（HIS-03）：连续天数、最长连续、热力图、周/月汇总。
///
/// 纯计算、不碰数据库也不碰 `DateTime.now()`（[now] 可注入），
/// 这样"跨日/时区"这类问题能在单测里直接钉住。
class ReadingStats {
  const ReadingStats({
    required this.currentStreak,
    required this.longestStreak,
    required this.days,
    required this.weekMinutes,
    required this.weekBooks,
    required this.monthMinutes,
    required this.monthBooks,
    required this.totalMinutes,
  });

  final int currentStreak;
  final int longestStreak;

  /// 最近 [weeks] 周的热力图（按日期升序，末尾是今天）。
  final List<ReadingDay> days;

  final int weekMinutes;
  final int weekBooks;
  final int monthMinutes;
  final int monthBooks;
  final int totalMinutes;

  bool get isEmpty => totalMinutes == 0;

  static const ReadingStats empty = ReadingStats(
    currentStreak: 0,
    longestStreak: 0,
    days: <ReadingDay>[],
    weekMinutes: 0,
    weekBooks: 0,
    monthMinutes: 0,
    monthBooks: 0,
    totalMinutes: 0,
  );

  /// 从会话列表算统计。会话可能来自旧版本/坏存档，坏行直接跳过。
  factory ReadingStats.fromSessions(
    Iterable<ReadingSession> sessions, {
    DateTime? now,
    int weeks = 12,
  }) {
    final today = _dateOnly(now ?? DateTime.now());
    final minutes = <DateTime, int>{};
    final booksByDay = <DateTime, Set<String>>{};

    for (final session in sessions) {
      if (session.durationMs <= 0) continue;
      final started = session.startedAt;
      if (started.isAfter(today.add(const Duration(days: 1)))) continue;
      final day = _dateOnly(started);
      // 向下取整到分钟：1 分钟的阅读不该显示成 0 分钟。
      minutes[day] = (minutes[day] ?? 0) + (session.durationMs / 60000).ceil();
      booksByDay.putIfAbsent(day, () => <String>{}).add(session.bookId);
    }

    final start = today.subtract(Duration(days: weeks * 7 - 1));
    final days = <ReadingDay>[
      for (var i = 0; i < weeks * 7; i++)
        () {
          final date = start.add(Duration(days: i));
          return ReadingDay(
            date: date,
            minutes: minutes[date] ?? 0,
            books: booksByDay[date]?.length ?? 0,
          );
        }(),
    ];

    final weekStart = today.subtract(const Duration(days: 6));
    final monthStart = DateTime(today.year, today.month, 1);
    var weekMinutes = 0;
    var monthMinutes = 0;
    var totalMinutes = 0;
    final weekBooks = <String>{};
    final monthBooks = <String>{};
    for (final session in sessions) {
      // 与热力图同一套过滤：时长为 0、或"未来"的会话（时区错乱的存档）都跳过。
      if (session.durationMs <= 0) continue;
      if (session.startedAt.isAfter(today.add(const Duration(days: 1)))) {
        continue;
      }
      final day = _dateOnly(session.startedAt);
      final value = (session.durationMs / 60000).ceil();
      totalMinutes += value;
      if (!day.isBefore(weekStart)) {
        weekMinutes += value;
        weekBooks.add(session.bookId);
      }
      if (!day.isBefore(monthStart)) {
        monthMinutes += value;
        monthBooks.add(session.bookId);
      }
    }

    return ReadingStats(
      currentStreak: _currentStreak(minutes, today),
      longestStreak: _longestStreak(minutes),
      days: days,
      weekMinutes: weekMinutes,
      weekBooks: weekBooks.length,
      monthMinutes: monthMinutes,
      monthBooks: monthBooks.length,
      totalMinutes: totalMinutes,
    );
  }

  /// 连续天数：今天读过就从今天数；今天还没读、昨天读过就从昨天数
  /// （否则每天早上一醒来"连续天数"就归零，体验很怪）。
  static int _currentStreak(Map<DateTime, int> minutes, DateTime today) {
    var cursor = today;
    if (!minutes.containsKey(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!minutes.containsKey(cursor)) return 0;
    }
    var streak = 0;
    while (minutes.containsKey(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static int _longestStreak(Map<DateTime, int> minutes) {
    if (minutes.isEmpty) return 0;
    final sorted = minutes.keys.toList()..sort();
    var longest = 1;
    var run = 1;
    for (var i = 1; i < sorted.length; i++) {
      final gap = sorted[i].difference(sorted[i - 1]).inDays;
      run = gap == 1 ? run + 1 : 1;
      longest = math.max(longest, run);
    }
    return longest;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
