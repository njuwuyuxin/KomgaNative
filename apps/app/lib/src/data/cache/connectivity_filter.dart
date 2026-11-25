import 'dart:async';

import 'package:komga_api/komga_api.dart';

typedef ClockNow = DateTime Function();
typedef TimerScheduler = Timer Function(Duration duration, void Function() cb);

/// 连接状态滞回滤波器：防止弱网并发请求导致离线提示高频闪动。
///
/// 判定与恢复规则：
/// - 装饰性请求（封面/页缩略图，[RequestPriority.decorative]）失败不单独拉响离线警报；
/// - 核心请求（[RequestPriority.primary]）连续失败达到 [offlineFailureThreshold] 次
///   立即进入离线；单次核心失败后开启 [offlineGraceWindow] 宽限窗口，若期间收到
///   任意成功响应则取消告警，到期仍无成功则确认离线；
/// - 进入离线后至少驻留 [minOfflineDwell] 才允许自动恢复，防止提示刚出现就闪没；
///   等待驻留期间若再次收到核心失败则取消本次恢复计划；
/// - 离线时 1 次核心成功或连续 [decorativeRecoveryThreshold] 次装饰成功确认恢复；
///   用户主动触发重试（[markRetryRequested]）且核心请求成功时可绕过最小驻留立刻恢复；
/// - 切换服务器 [scope] 时重置状态与计时器，不跨服务器串状态。
class ConnectivityFilter {
  ConnectivityFilter({
    required void Function(bool offline) onChanged,
    this.offlineFailureThreshold = 2,
    this.offlineGraceWindow = const Duration(milliseconds: 1800),
    this.minOfflineDwell = const Duration(milliseconds: 2500),
    this.decorativeRecoveryThreshold = 3,
    ClockNow? now,
    TimerScheduler? schedule,
  }) : assert(offlineFailureThreshold >= 1),
       assert(decorativeRecoveryThreshold >= 1),
       _onChanged = onChanged,
       _now = now ?? DateTime.now,
       _schedule = schedule ?? Timer.new;

  final void Function(bool offline) _onChanged;
  final ClockNow _now;
  final TimerScheduler _schedule;

  /// 核心请求连续失败达到此次数即刻切离线。
  final int offlineFailureThreshold;

  /// 首次核心失败后的宽限窗口：期间若无任何成功响应则确认离线。
  final Duration offlineGraceWindow;

  /// 进入离线状态后的最小驻留时长，避免提示一闪而逝。
  final Duration minOfflineDwell;

  /// 仅靠装饰性请求（缩略图）连续成功触发恢复所需次数。
  final int decorativeRecoveryThreshold;

  String? _activeScope;
  bool _offline = false;
  bool _disposed = false;
  int _consecutivePrimaryFailures = 0;
  int _consecutiveDecorativeSuccesses = 0;
  DateTime? _offlineSince;
  bool _retryPending = false;
  Timer? _offlineGraceTimer;
  Timer? _recoveryDwellTimer;

  bool get isOffline => _offline;

  void reportOffline(
    String scope, {
    RequestPriority priority = RequestPriority.primary,
  }) {
    if (_disposed) return;
    _syncScope(scope);
    _consecutiveDecorativeSuccesses = 0;

    if (priority == RequestPriority.decorative) return;

    if (_offline) {
      // 离线驻留/等待恢复期间再次发生核心失败，说明链路仍不稳，取消恢复计划。
      _recoveryDwellTimer?.cancel();
      _recoveryDwellTimer = null;
      _retryPending = false;
      return;
    }

    _consecutivePrimaryFailures++;
    if (_consecutivePrimaryFailures >= offlineFailureThreshold ||
        offlineGraceWindow <= Duration.zero) {
      _enterOffline();
      return;
    }

    _offlineGraceTimer ??= _schedule(offlineGraceWindow, () {
      _offlineGraceTimer = null;
      if (!_disposed && !_offline && _consecutivePrimaryFailures > 0) {
        _enterOffline();
      }
    });
  }

  void reportOnline(
    String scope, {
    RequestPriority priority = RequestPriority.primary,
  }) {
    if (_disposed) return;
    _syncScope(scope);

    // 任意成功响应都证明链路可通，清零待确认的离线宽限。
    _offlineGraceTimer?.cancel();
    _offlineGraceTimer = null;
    _consecutivePrimaryFailures = 0;

    if (!_offline) return;

    if (priority == RequestPriority.decorative) {
      _consecutiveDecorativeSuccesses++;
      if (_consecutiveDecorativeSuccesses < decorativeRecoveryThreshold) {
        return;
      }
    } else if (_retryPending) {
      _exitOffline();
      return;
    }

    final since = _offlineSince;
    if (since == null || minOfflineDwell <= Duration.zero) {
      _exitOffline();
      return;
    }

    final rawElapsed = _now().difference(since);
    final elapsed = rawElapsed.isNegative ? Duration.zero : rawElapsed;
    final remaining = minOfflineDwell - elapsed;
    if (remaining <= Duration.zero) {
      _exitOffline();
      return;
    }

    _recoveryDwellTimer ??= _schedule(remaining, () {
      _recoveryDwellTimer = null;
      if (!_disposed && _offline) {
        _exitOffline();
      }
    });
  }

  /// 用户显式点击「重试」时调用：下一次核心请求成功可绕过最小驻留立刻恢复。
  void markRetryRequested() {
    if (_disposed || !_offline) return;
    _retryPending = true;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelTimers();
  }

  void _syncScope(String scope) {
    if (_activeScope == null) {
      _activeScope = scope;
      return;
    }
    if (_activeScope == scope) return;

    _activeScope = scope;
    _cancelTimers();
    _consecutivePrimaryFailures = 0;
    _consecutiveDecorativeSuccesses = 0;
    _offlineSince = null;
    _retryPending = false;
    if (_offline) {
      _offline = false;
      _onChanged(false);
    }
  }

  void _enterOffline() {
    _cancelTimers();
    _consecutivePrimaryFailures = 0;
    _consecutiveDecorativeSuccesses = 0;
    _retryPending = false;
    if (_offline) return;
    _offline = true;
    _offlineSince = _now();
    _onChanged(true);
  }

  void _exitOffline() {
    _cancelTimers();
    _consecutivePrimaryFailures = 0;
    _consecutiveDecorativeSuccesses = 0;
    _retryPending = false;
    _offlineSince = null;
    if (!_offline) return;
    _offline = false;
    _onChanged(false);
  }

  void _cancelTimers() {
    _offlineGraceTimer?.cancel();
    _offlineGraceTimer = null;
    _recoveryDwellTimer?.cancel();
    _recoveryDwellTimer = null;
  }
}
