import 'dart:math' as math;

import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 某一天读过的一本书（按 `scope + bookId` 去重，汇总当天时长并保留最新一次阅读时间）。
class ReadingDayBook {
  const ReadingDayBook({
    required this.scope,
    required this.bookId,
    required this.seriesId,
    required this.bookName,
    required this.minutes,
    required this.lastReadAt,
  });

  final String scope;
  final String bookId;
  final String seriesId;
  final String bookName;
  final int minutes;
  final DateTime lastReadAt;

  /// 该条历史是否归属本机书库（把源键归属判断留在数据层，UI 不直接探测原始键）。
  bool get isLocal => isLocalSourceKey(resolvedScope);

  /// 归一化后的内容源分区键（兼容历史空键）。
  String get resolvedScope => normalizeLegacySourceKey(scope);
}

/// 某一天的阅读量（Insights 热力图的一格）。
class ReadingDay {
  const ReadingDay({
    required this.date,
    required this.minutes,
    required this.books,
    this.readBooks = const <ReadingDayBook>[],
  });

  /// 本地日期（时分秒归零），用作热力图的横轴。
  final DateTime date;
  final int minutes;

  /// 这天读过几本不同的书。
  final int books;

  /// 当天读过的书（已去重，按当天最后阅读时间倒序）。
  final List<ReadingDayBook> readBooks;

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
    this.latestActiveDate,
    this.daysByDate = const <DateTime, ReadingDay>{},
  });

  final int currentStreak;
  final int longestStreak;

  /// 最近 [weeks] 周的热力图（按日期升序，末尾是今天）。
  final List<ReadingDay> days;

  /// 全部有效阅读会话中最近一天有阅读记录的本地日期。
  final DateTime? latestActiveDate;

  /// 所有有阅读记录的日期明细（key 为时分秒归零的本地日期）。
  final Map<DateTime, ReadingDay> daysByDate;

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
    final today = dateOnly(now ?? DateTime.now());
    final minutes = <DateTime, int>{};
    final booksByDay = <DateTime, Map<String, ReadingDayBook>>{};
    final weekStart = today.subtract(const Duration(days: 6));
    final monthStart = DateTime(today.year, today.month, 1);
    var weekMinutes = 0;
    var monthMinutes = 0;
    var totalMinutes = 0;
    final weekBooks = <String>{};
    final monthBooks = <String>{};
    DateTime? latestActiveDate;

    for (final session in sessions) {
      // 过滤坏行：时长为 0、或"未来"的会话（时区错乱的存档）都跳过。
      if (session.durationMs <= 0) continue;
      final started = session.startedAt;
      if (started.isAfter(today.add(const Duration(days: 1)))) continue;
      final day = dateOnly(started);
      // 向上取整到分钟：1 分钟以内的有效阅读不该显示成 0 分钟。
      final value = (session.durationMs / 60000).ceil();
      minutes[day] = (minutes[day] ?? 0) + value;
      if (latestActiveDate == null || day.isAfter(latestActiveDate)) {
        latestActiveDate = day;
      }

      final bookKey = '${session.scope}|${session.bookId}';
      final dayBooks = booksByDay.putIfAbsent(
        day,
        () => <String, ReadingDayBook>{},
      );
      final existing = dayBooks[bookKey];
      final lastAt = session.endedAt.isAfter(started)
          ? session.endedAt
          : started;
      if (existing == null) {
        dayBooks[bookKey] = ReadingDayBook(
          scope: session.scope,
          bookId: session.bookId,
          seriesId: session.seriesId,
          bookName: session.bookName,
          minutes: value,
          lastReadAt: lastAt,
        );
      } else {
        final newer = !lastAt.isBefore(existing.lastReadAt);
        dayBooks[bookKey] = ReadingDayBook(
          scope: existing.scope,
          bookId: existing.bookId,
          seriesId: newer ? session.seriesId : existing.seriesId,
          bookName: newer ? session.bookName : existing.bookName,
          minutes: existing.minutes + value,
          lastReadAt: newer ? lastAt : existing.lastReadAt,
        );
      }

      totalMinutes += value;
      if (!day.isBefore(weekStart)) {
        weekMinutes += value;
        weekBooks.add(bookKey);
      }
      if (!day.isBefore(monthStart)) {
        monthMinutes += value;
        monthBooks.add(bookKey);
      }
    }

    final daysByDate = <DateTime, ReadingDay>{};
    for (final entry in minutes.entries) {
      final list = booksByDay[entry.key]?.values.toList() ?? <ReadingDayBook>[];
      list.sort(
        (ReadingDayBook a, ReadingDayBook b) =>
            b.lastReadAt.compareTo(a.lastReadAt),
      );
      daysByDate[entry.key] = ReadingDay(
        date: entry.key,
        minutes: entry.value,
        books: list.length,
        readBooks: List<ReadingDayBook>.unmodifiable(list),
      );
    }

    final start = today.subtract(Duration(days: weeks * 7 - 1));
    final days = <ReadingDay>[
      for (var i = 0; i < weeks * 7; i++)
        () {
          final date = start.add(Duration(days: i));
          return daysByDate[date] ??
              ReadingDay(date: date, minutes: 0, books: 0);
        }(),
    ];

    return ReadingStats(
      currentStreak: _currentStreak(minutes, today),
      longestStreak: _longestStreak(minutes),
      days: days,
      latestActiveDate: latestActiveDate,
      daysByDate: Map<DateTime, ReadingDay>.unmodifiable(daysByDate),
      weekMinutes: weekMinutes,
      weekBooks: weekBooks.length,
      monthMinutes: monthMinutes,
      monthBooks: monthBooks.length,
      totalMinutes: totalMinutes,
    );
  }

  /// 查询某一天（本地日期）的阅读明细；当天无阅读时返回 0 分钟空记录。
  ReadingDay dayOf(DateTime date) {
    final normalized = dateOnly(date);
    return daysByDate[normalized] ??
        ReadingDay(date: normalized, minutes: 0, books: 0);
  }

  /// 生成 GitHub 样式的自然周热力图矩阵：`weeks` 列 × 7 行（周一到周日）。
  ///
  /// 最后一列是 [today] 所在的自然周，[today] 之后的未来日期用 `null` 占位。
  List<List<ReadingDay?>> heatmapWeeks({
    required DateTime today,
    required int weeks,
  }) {
    if (weeks <= 0) return const <List<ReadingDay?>>[];
    final normalizedToday = dateOnly(today);
    final currentWeekMonday = normalizedToday.subtract(
      Duration(days: normalizedToday.weekday - DateTime.monday),
    );
    final firstMonday = currentWeekMonday.subtract(
      Duration(days: (weeks - 1) * 7),
    );
    return <List<ReadingDay?>>[
      for (var col = 0; col < weeks; col++)
        <ReadingDay?>[
          for (var row = 0; row < 7; row++)
            () {
              final date = firstMonday.add(Duration(days: col * 7 + row));
              if (date.isAfter(normalizedToday)) return null;
              return dayOf(date);
            }(),
        ],
    ];
  }

  /// GitHub 样式 5 档热力等级：0 表示当天无阅读，1..4 表示由浅到深。
  static int heatmapLevel(ReadingDay day, int maxMinutes) {
    if (day.minutes <= 0) return 0;
    if (maxMinutes <= 0) return 4;
    final ratio = (day.minutes / maxMinutes).clamp(0.0, 1.0);
    if (ratio <= 0.25) return 1;
    if (ratio <= 0.50) return 2;
    if (ratio <= 0.75) return 3;
    return 4;
  }

  /// 根据可用宽度计算最适合横向铺满且格子舒展的周数（12..52 周）。
  static int heatmapWeekCountForWidth(
    double availableWidth, {
    required double cellTarget,
    required double gap,
    int minWeeks = 12,
    int maxWeeks = 52,
  }) {
    if (availableWidth <= 0 || cellTarget <= 0) return minWeeks;
    final raw = ((availableWidth + gap) / (cellTarget + gap)).floor();
    return raw.clamp(minWeeks, maxWeeks);
  }

  /// 本地日期归一化（时分秒归零）。
  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

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
}
