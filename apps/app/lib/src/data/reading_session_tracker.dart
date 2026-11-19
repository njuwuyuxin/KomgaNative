import 'package:meta/meta.dart';

/// 一次阅读会话的草稿（HIS-01）：结算时写进 `reading_sessions`。
@immutable
class ReadingSessionDraft {
  const ReadingSessionDraft({
    required this.bookId,
    required this.seriesId,
    required this.bookName,
    required this.startedAt,
    required this.endedAt,
    required this.startPage,
    required this.endPage,
    required this.completed,
  });

  final String bookId;
  final String seriesId;
  final String bookName;
  final DateTime startedAt;
  final DateTime endedAt;
  final int startPage;
  final int endPage;

  /// 会话结束时这本书是否已读完。
  final bool completed;

  Duration get duration => endedAt.difference(startedAt);
}

/// 阅读时长统计（HIS-01）。
///
/// 只做**记账**，不碰 UI、不碰 DB：`ReaderScreen` 在进/出/切后台时喂它，
/// 它负责"这一次读了多久、从第几页到第几页"，以及"太短的不算"。
///
/// 为什么最短 10 秒：翻目录、误点、截图都会产生一次进出阅读器；
/// 把这些记进历史，Insights 的天数/时长会立刻失真。
class ReadingSessionTracker {
  ReadingSessionTracker({
    this.minDuration = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration minDuration;
  final DateTime Function() _clock;

  DateTime? _startedAt;
  int _startPage = 1;
  int _endPage = 1;
  DateTime? _pausedAt;

  bool get running => _startedAt != null;

  /// 本次已读时长（暂停中不增长）。
  ///
  /// chrome 里的"本次 12:30"用它，保证和退出后写进历史的那条会话同一口径。
  Duration get elapsed {
    final started = _startedAt;
    if (started == null) return Duration.zero;
    final end = _pausedAt ?? _clock();
    return end.difference(started);
  }

  /// 进入阅读器（或换书）时开始计时。已经在计时就忽略——一次阅读只算一条。
  void start({required int page}) {
    if (_startedAt != null) return;
    _startedAt = _clock();
    _startPage = page;
    _endPage = page;
    _pausedAt = null;
  }

  /// 翻页时更新"读到哪"。暂停中不更新（用户可能正在后台）。
  void note({required int page}) {
    if (_startedAt == null || _pausedAt != null) return;
    _endPage = page;
  }

  /// 切到后台：先把已读时长结算掉，避免后台挂着继续计时。
  ///
  /// 这里**不写入**，只把结束时间钉住；真正落库由 [finish] 统一做，
  /// 这样"后台 → 回来 → 退出"只产生一条会话。
  void pause() {
    if (_startedAt == null || _pausedAt != null) return;
    _pausedAt = _clock();
  }

  /// 回到前台：把暂停的那段排除掉，继续计时。
  void resume() {
    final paused = _pausedAt;
    if (paused == null || _startedAt == null) return;
    // 把起点整体后移，等于把暂停区间从时长里剪掉。
    _startedAt = _startedAt!.add(_clock().difference(paused));
    _pausedAt = null;
  }

  /// 结算：返回 null 表示这次太短、不算一条。
  ReadingSessionDraft? finish({
    required String bookId,
    required String seriesId,
    required String bookName,
    required bool completed,
    int? page,
  }) {
    final started = _startedAt;
    if (started == null) return null;
    final ended = _pausedAt ?? _clock();
    if (page != null) _endPage = page;

    _startedAt = null;
    _pausedAt = null;

    final draft = ReadingSessionDraft(
      bookId: bookId,
      seriesId: seriesId,
      bookName: bookName,
      startedAt: started,
      endedAt: ended,
      startPage: _startPage,
      endPage: _endPage,
      completed: completed,
    );
    if (draft.duration < minDuration) return null;
    return draft;
  }
}
