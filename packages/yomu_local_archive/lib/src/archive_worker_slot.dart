import 'dart:async';
import 'dart:isolate';

/// 单个后台归档工作 Isolate 的生命周期与请求派发槽位。
final class ArchiveWorkerSlot {
  ArchiveWorkerSlot({required this.idleTimeout, required this.onClosed}) {
    _ready = _spawn();
  }

  final Duration idleTimeout;
  final void Function() onClosed;

  late final Future<SendPort> _ready;
  Isolate? _isolate;
  ReceivePort? _responses;
  ReceivePort? _exitPort;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  final Map<int, Timer> _taskTimers = <int, Timer>{};
  Timer? _idleTimer;
  int _nextId = 1;
  bool _closed = false;
  bool _draining = false;

  bool get isClosed => _closed;
  bool get isAcceptingWork => !_closed && !_draining;
  int get inFlight => _pending.length;

  Future<SendPort> _spawn() async {
    final responses = ReceivePort();
    final exitPort = ReceivePort();
    _responses = responses;
    _exitPort = exitPort;

    final handshake = Completer<SendPort>();
    responses.listen((Object? message) {
      if (!handshake.isCompleted && message is SendPort) {
        handshake.complete(message);
        return;
      }
      if (message is List<Object?> && message.length >= 3) {
        final id = message[0] as int;
        final ok = message[1] as bool;
        _taskTimers.remove(id)?.cancel();
        final completer = _pending.remove(id);
        if (_draining && _pending.isEmpty) {
          unawaited(close());
        } else {
          _scheduleIdleIfEmpty();
        }
        if (completer == null || completer.isCompleted) return;
        if (ok) {
          completer.complete(message[2]);
        } else {
          final error = message[2] ?? StateError('Archive worker task failed');
          final stack = message.length >= 4 && message[3] is String
              ? StackTrace.fromString(message[3]! as String)
              : StackTrace.current;
          completer.completeError(error, stack);
        }
      }
    });

    exitPort.listen((Object? _) {
      if (!handshake.isCompleted) {
        handshake.completeError(
          StateError('Archive worker isolate exited before handshake'),
        );
      }
      _failAllAndCleanup(StateError('Archive worker isolate terminated'));
    });

    final isolate = await Isolate.spawn<SendPort>(
      _archiveWorkerEntry,
      responses.sendPort,
      onExit: exitPort.sendPort,
      debugName: 'yomu_archive_worker',
    );
    _isolate = isolate;
    if (_closed) {
      isolate.kill(priority: Isolate.immediate);
      responses.close();
      exitPort.close();
      throw StateError('Archive worker closed during startup');
    }
    return handshake.future;
  }

  Future<Object?> execute(
    FutureOr<Object?> Function() task, {
    required Duration timeout,
  }) async {
    _idleTimer?.cancel();
    _idleTimer = null;
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _taskTimers[id] = Timer(timeout, () {
      _taskTimers.remove(id);
      final timedOut = _pending.remove(id);
      if (timedOut != null && !timedOut.isCompleted) {
        timedOut.completeError(
          TimeoutException('Archive worker task timed out', timeout),
        );
      }
      // N4: 停止向该槽位继续派发新任务；若同 Worker 上还有其他健康任务在跑，先排空不误杀，
      // 仅当在途任务全部结束（或无其他任务）时再回收 Isolate。
      _draining = true;
      if (_pending.isEmpty) {
        unawaited(
          close(reason: TimeoutException('Archive worker recycled', timeout)),
        );
      }
    });

    try {
      final sendPort = await _ready;
      if (_closed) {
        _taskTimers.remove(id)?.cancel();
        _pending.remove(id);
        throw StateError('Archive worker closed before dispatch');
      }
      sendPort.send(<Object?>[id, task]);
    } on Object catch (error, stackTrace) {
      _taskTimers.remove(id)?.cancel();
      _pending.remove(id);
      _scheduleIdleIfEmpty();
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
    return completer.future;
  }

  void _scheduleIdleIfEmpty() {
    if (_closed || _pending.isNotEmpty) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () => unawaited(close()));
  }

  Future<void> close({Object? reason}) async {
    if (_closed) return;
    _closed = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    onClosed();
    final hadPending = _pending.isNotEmpty;
    _failPending(reason ?? StateError('Archive worker shut down'));
    if (hadPending) {
      _isolate?.kill(priority: Isolate.immediate);
    } else {
      try {
        final sendPort = await _ready;
        sendPort.send(null);
      } on Object {
        // 启动阶段失败或已退出时直接强制回收即可。
        _isolate?.kill(priority: Isolate.immediate);
      }
    }
    _responses?.close();
    _exitPort?.close();
    _responses = null;
    _exitPort = null;
    _isolate = null;
  }

  void _failAllAndCleanup(Object error) {
    if (!_closed) {
      _closed = true;
      _idleTimer?.cancel();
      _idleTimer = null;
      onClosed();
      _responses?.close();
      _exitPort?.close();
      _responses = null;
      _exitPort = null;
      _isolate = null;
    }
    _failPending(error);
  }

  void _failPending(Object error) {
    for (final timer in _taskTimers.values) {
      timer.cancel();
    }
    _taskTimers.clear();
    if (_pending.isEmpty) return;
    final entries = List<Completer<Object?>>.of(_pending.values);
    _pending.clear();
    for (final completer in entries) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }
}

void _archiveWorkerEntry(SendPort replyPort) {
  final commands = ReceivePort();
  replyPort.send(commands.sendPort);

  commands.listen((Object? message) async {
    if (message == null) {
      commands.close();
      return;
    }
    if (message is! List<Object?> || message.length < 2) return;
    final id = message[0] as int;
    final task = message[1] as FutureOr<Object?> Function();
    try {
      final result = await task();
      replyPort.send(<Object?>[id, true, result]);
    } on Object catch (error, stackTrace) {
      try {
        replyPort.send(<Object?>[id, false, error, stackTrace.toString()]);
      } on ArgumentError {
        replyPort.send(<Object?>[
          id,
          false,
          StateError(error.toString()),
          stackTrace.toString(),
        ]);
      }
    }
  });
}
