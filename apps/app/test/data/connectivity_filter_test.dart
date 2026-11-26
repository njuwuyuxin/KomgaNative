import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komga_api/komga_api.dart';
import 'package:yomu/src/data/cache/connectivity_filter.dart';

class _FakeClock {
  DateTime current = DateTime.utc(2026, 11, 25, 12);
  final List<_ScheduledTimer> _timers = <_ScheduledTimer>[];

  DateTime now() => current;

  Timer schedule(Duration duration, void Function() callback) {
    final timer = _ScheduledTimer(current.add(duration), callback);
    _timers.add(timer);
    return timer;
  }

  void elapse(Duration delta) {
    current = current.add(delta);
    while (true) {
      final due =
          _timers
              .where(
                (_ScheduledTimer t) => t.isActive && !t.dueAt.isAfter(current),
              )
              .toList()
            ..sort(
              (_ScheduledTimer a, _ScheduledTimer b) =>
                  a.dueAt.compareTo(b.dueAt),
            );
      if (due.isEmpty) break;
      final next = due.first;
      next.fire();
    }
  }

  int get activeTimerCount =>
      _timers.where((_ScheduledTimer t) => t.isActive).length;
}

class _ScheduledTimer implements Timer {
  _ScheduledTimer(this.dueAt, this._callback);

  final DateTime dueAt;
  final void Function() _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;

  @override
  void cancel() {
    _active = false;
  }

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }
}

void main() {
  const scopeA = 'https://komga-a.example.com';
  const scopeB = 'https://komga-b.example.com';

  late _FakeClock clock;
  late List<bool> transitions;
  late ConnectivityFilter filter;

  setUp(() {
    clock = _FakeClock();
    transitions = <bool>[];
    filter = ConnectivityFilter(
      onChanged: transitions.add,
      now: clock.now,
      schedule: clock.schedule,
    );
  });

  tearDown(() => filter.dispose());

  test('初始在线；任意次数 decorative（封面/缩略图）失败不触发离线', () {
    expect(filter.isOffline, isFalse);

    for (var i = 0; i < 10; i++) {
      filter.reportOffline(scopeA, priority: RequestPriority.decorative);
    }
    clock.elapse(const Duration(seconds: 10));

    expect(filter.isOffline, isFalse);
    expect(transitions, isEmpty);
    expect(clock.activeTimerCount, 0);
  });

  test('单次 primary 失败不立刻切离线；宽限期内有任意成功即取消告警', () {
    filter.reportOffline(scopeA);
    expect(filter.isOffline, isFalse);
    expect(clock.activeTimerCount, 1);

    clock.elapse(const Duration(milliseconds: 800));
    filter.reportOnline(scopeA, priority: RequestPriority.decorative);

    clock.elapse(const Duration(seconds: 5));
    expect(filter.isOffline, isFalse);
    expect(transitions, isEmpty);
    expect(clock.activeTimerCount, 0);
  });

  test('单次 primary 失败且宽限期到期无成功 → 确认进入离线', () {
    filter.reportOffline(scopeA);
    clock.elapse(const Duration(milliseconds: 1799));
    expect(filter.isOffline, isFalse);

    clock.elapse(const Duration(milliseconds: 1));
    expect(filter.isOffline, isTrue);
    expect(transitions, <bool>[true]);
  });

  test('连续 2 次 primary 失败 → 立即确认离线且取消宽限定时器', () {
    filter.reportOffline(scopeA);
    expect(filter.isOffline, isFalse);

    filter.reportOffline(scopeA);
    expect(filter.isOffline, isTrue);
    expect(transitions, <bool>[true]);
    expect(clock.activeTimerCount, 0);
  });

  test('离线后未满最小驻留期收到成功 → 推迟至驻留期满再恢复，防闪烁', () {
    filter
      ..reportOffline(scopeA)
      ..reportOffline(scopeA);
    expect(filter.isOffline, isTrue);

    clock.elapse(const Duration(milliseconds: 400));
    filter.reportOnline(scopeA);
    expect(filter.isOffline, isTrue);

    clock.elapse(const Duration(milliseconds: 2099));
    expect(filter.isOffline, isTrue);

    clock.elapse(const Duration(milliseconds: 1));
    expect(filter.isOffline, isFalse);
    expect(transitions, <bool>[true, false]);
  });

  test('等待驻留恢复期间再次发生 primary 失败 → 取消恢复计划、继续保持离线', () {
    filter
      ..reportOffline(scopeA)
      ..reportOffline(scopeA);

    clock.elapse(const Duration(milliseconds: 500));
    filter.reportOnline(scopeA);
    expect(clock.activeTimerCount, 1);

    clock.elapse(const Duration(milliseconds: 500));
    filter.reportOffline(scopeA);
    expect(clock.activeTimerCount, 0);

    clock.elapse(const Duration(seconds: 5));
    expect(filter.isOffline, isTrue);
    expect(transitions, <bool>[true]);
  });

  test('离线且已超过最小驻留期 → 1 次 primary 成功立刻恢复', () {
    filter
      ..reportOffline(scopeA)
      ..reportOffline(scopeA);

    clock.elapse(const Duration(milliseconds: 2500));
    filter.reportOnline(scopeA);

    expect(filter.isOffline, isFalse);
    expect(transitions, <bool>[true, false]);
    expect(clock.activeTimerCount, 0);
  });

  test('离线时仅靠 decorative 成功需连续 3 次（中途失败会清零计数）且满驻留才恢复', () {
    filter
      ..reportOffline(scopeA)
      ..reportOffline(scopeA);
    clock.elapse(const Duration(seconds: 3));

    filter
      ..reportOnline(scopeA, priority: RequestPriority.decorative)
      ..reportOnline(scopeA, priority: RequestPriority.decorative);
    expect(filter.isOffline, isTrue);

    // 任意失败打断连续装饰成功计数。
    filter.reportOffline(scopeA, priority: RequestPriority.decorative);
    filter
      ..reportOnline(scopeA, priority: RequestPriority.decorative)
      ..reportOnline(scopeA, priority: RequestPriority.decorative);
    expect(filter.isOffline, isTrue);

    filter.reportOnline(scopeA, priority: RequestPriority.decorative);
    expect(filter.isOffline, isFalse);
    expect(transitions, <bool>[true, false]);
  });

  test('用户主动点击重试后 primary 成功 → 绕过最小驻留立刻恢复', () {
    filter
      ..reportOffline(scopeA)
      ..reportOffline(scopeA);
    clock.elapse(const Duration(milliseconds: 200));

    filter.markRetryRequested();
    filter.reportOnline(scopeA);

    expect(filter.isOffline, isFalse);
    expect(transitions, <bool>[true, false]);
  });

  test('切换服务器 scope 时重置离线态与挂起定时器', () {
    filter
      ..reportOffline(scopeA)
      ..reportOffline(scopeA);
    expect(filter.isOffline, isTrue);

    filter.reportOnline(scopeB);
    expect(filter.isOffline, isFalse);
    expect(transitions, <bool>[true, false]);
    expect(clock.activeTimerCount, 0);
  });

  test('系统时钟回拨时安全按完整驻留期等待，不立刻闪退也不抛错', () {
    filter
      ..reportOffline(scopeA)
      ..reportOffline(scopeA);

    clock.current = clock.current.subtract(const Duration(seconds: 30));
    filter.reportOnline(scopeA);
    expect(filter.isOffline, isTrue);

    clock.elapse(const Duration(milliseconds: 2500));
    expect(filter.isOffline, isFalse);
  });

  test('dispose 取消所有挂起定时器并忽略后续事件', () {
    filter.reportOffline(scopeA);
    expect(clock.activeTimerCount, 1);

    filter.dispose();
    expect(clock.activeTimerCount, 0);

    filter
      ..reportOffline(scopeA)
      ..reportOffline(scopeA);
    clock.elapse(const Duration(seconds: 10));
    expect(filter.isOffline, isFalse);
    expect(transitions, isEmpty);
  });
}
