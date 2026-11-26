import 'dart:async';
import 'dart:ui' show AppLifecycleState, VoidCallback;

import 'package:yomu/src/data/progress/progress_sync_service.dart';
import 'package:yomu/src/data/reading_session_tracker.dart';
import 'package:yomu/src/providers/reading_history_provider.dart';
import 'package:yomu/src/providers/series_read_provider.dart';
import 'package:yomu/src/widgets/reader_layout.dart';
import 'package:yomu/src/widgets/reader_progress_writer.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 阅读器会话计时、防抖进度落盘、隐身状态与退出/后台结算协作者（P3-1）。
///
/// 将生命周期副作用从 `_ReaderScreenState` 中抽离为独立可测对象，
/// 彻底替代共享私有状态的 `part + mixin` 切片。
class ReaderSessionCoordinator {
  ReaderSessionCoordinator({
    required this.bookId,
    required Book? initialBook,
    required ProgressSyncService progressSync,
    required ReadingSessionRecorder recorder,
    required ReaderProgressCommitter committer,
    required ReaderLayout? Function() resolveLiveLayout,
    required bool Function() isShowSessionTimeEnabled,
    required VoidCallback onSessionMinutesChanged,
    Duration progressDebounce = ReaderProgressWriter.defaultDelay,
  }) : _initialBook = initialBook,
       _progressSync = progressSync,
       _recorder = recorder,
       _committer = committer,
       _resolveLiveLayout = resolveLiveLayout,
       _isShowSessionTimeEnabled = isShowSessionTimeEnabled,
       _onSessionMinutesChanged = onSessionMinutesChanged {
    _progress = ReaderProgressWriter(
      delay: progressDebounce,
      write: (int page) => _progressSync.save(
        bookId,
        page: page,
        completed:
            ((!_settledLeave ? _resolveLiveLayout() : null) ?? _lastLayout)
                ?.isCompletedAt(page) ??
            false,
        scope: resolvedSourceKey,
      ),
    );
  }

  final String bookId;
  final Book? _initialBook;
  final ProgressSyncService _progressSync;
  final ReadingSessionRecorder _recorder;
  final ReaderProgressCommitter _committer;
  final ReaderLayout? Function() _resolveLiveLayout;
  final bool Function() _isShowSessionTimeEnabled;
  final VoidCallback _onSessionMinutesChanged;

  final ReadingSessionTracker _session = ReadingSessionTracker();
  late final ReaderProgressWriter _progress;

  Timer? _sessionTicker;
  int _shownSessionMinutes = 0;
  bool _incognito = false;
  bool _settledLeave = false;
  bool _settledSession = false;
  ReaderLayout? _lastLayout;
  Book? _lastBook;
  bool? _initialBookUnread;
  int _lastReadPage = 0;

  /// 当前书所属内容源标识（供进度落盘、会话记录与退出联动复用）。
  String? resolvedSourceKey;

  int get shownSessionMinutes => _shownSessionMinutes;
  bool get incognito => _incognito;
  bool get settledLeave => _settledLeave;
  Book? get lastBook => _lastBook;
  ReaderLayout? get lastLayout => _lastLayout;

  /// 启动本次阅读会话与 30 秒分钟跳变计时器。
  void start({required int initialPage}) {
    _session.start(page: initialPage);
    _sessionTicker?.cancel();
    _sessionTicker = Timer.periodic(
      const Duration(seconds: 30),
      (Timer _) => _tickSession(),
    );
  }

  void _tickSession() {
    if (!_isShowSessionTimeEnabled()) return;
    final minutes = _session.elapsed.inMinutes;
    if (minutes == _shownSessionMinutes) return;
    _shownSessionMinutes = minutes;
    _onSessionMinutesChanged();
  }

  /// 缓存最新书籍元信息与布局快照，供退出（`dispose` 时不再碰 `ref`）结算使用。
  void noteBookAndLayout(Book? book, ReaderLayout layout) {
    _lastLayout = layout;
    if (book != null) {
      _lastBook = book;
      _initialBookUnread ??= book.isUnread;
      _progressSync.noteBook(book);
    }
  }

  /// 记录翻页并调度防抖进度写入。
  void notePageChanged(int page) {
    _lastReadPage = page;
    _session.note(page: page);
    scheduleProgress(page);
  }

  /// 仅调度防抖进度写入（如跳页或双页手动分组）。
  void scheduleProgress(int page) {
    _lastReadPage = page;
    if (_incognito) return;
    _progress.schedule(page);
  }

  /// 切换隐身模式；开启时取消待落盘进度。
  bool toggleIncognito() {
    _incognito = !_incognito;
    if (_incognito) _progress.cancel();
    return _incognito;
  }

  /// 切后台/锁屏时暂停计时并立刻落盘；回到前台恢复计时。
  void handleAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _session.resume();
      return;
    }
    _session.pause();
    if (_incognito) return;
    final page = _exitProgressPage();
    if (page != null) unawaited(_progress.flush(page));
  }

  /// 计算切后台或退出阅读器时应当补写的页码（不需要补写时返回 null）。
  int? _exitProgressPage() {
    final pending = _progress.pendingPage;
    if (pending != null) return pending;
    if (_lastReadPage > 0) return _lastReadPage;
    final layout = _lastLayout;
    if ((_initialBookUnread ?? false) && layout != null && layout.total > 0) {
      return layout.page;
    }
    return null;
  }

  /// 退出阅读器时幂等落盘进度并通知书架/「正在读」联动刷新。
  void settleProgressOnLeave({required String? seriesId}) {
    if (_settledLeave) return;
    _settledLeave = true;
    final exitPage = _exitProgressPage();
    final isCompleted =
        !_incognito &&
        exitPage != null &&
        (_lastLayout?.isCompletedAt(exitPage) ?? false);
    final completedBook = isCompleted ? (_lastBook ?? _initialBook) : null;
    unawaited(
      _committer.settle(
        flushProgress: _flushProgressForLeave,
        bookId: bookId,
        seriesId: seriesId,
        sourceKey: resolvedSourceKey,
        completedBook: completedBook,
      ),
    );
  }

  Future<bool> _flushProgressForLeave() async {
    if (_incognito) {
      _progress.cancel();
      return _progress.hasWritten;
    }
    final targetPage = _exitProgressPage();
    if (targetPage != null) {
      await _progress.flush(targetPage);
    }
    return _progress.hasWritten;
  }

  void _settleSession({required bool completed}) {
    if (_settledSession) return;
    _settledSession = true;
    final book = _lastBook ?? _initialBook;
    if (_incognito) {
      _session.finish(
        bookId: bookId,
        seriesId: book?.seriesId ?? bookId,
        bookName: book?.name ?? bookId,
        completed: completed,
      );
      return;
    }
    final draft = _session.finish(
      bookId: bookId,
      seriesId: book?.seriesId ?? bookId,
      bookName: book?.name ?? bookId,
      completed: completed,
      page: _lastReadPage > 0 ? _lastReadPage : null,
    );
    if (draft == null) return;
    unawaited(_recorder.record(draft, scope: resolvedSourceKey));
  }

  /// 释放计时器并幂等收尾会话与进度。
  void dispose({required String? seriesId}) {
    _sessionTicker?.cancel();
    _sessionTicker = null;
    _settleSession(completed: false);
    settleProgressOnLeave(seriesId: seriesId);
    _progress.dispose();
  }
}
