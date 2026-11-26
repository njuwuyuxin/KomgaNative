import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

/// 归档 CPU 密集型任务卸载到后台 Isolate 的字节阈值配置（P2-2）。
///
/// 小块数据（如数 KB 的缩略图或单页测试夹具）直接同步处理以避免消息派发开销；
/// 真实大漫画页（通常 1~10 MB）与大目录/大 TAR 自动经长驻工作 Isolate 池 +
/// `TransferableTypedData` 卸载到工作线程，既不阻塞 UI 线程，又避免每页重建 Isolate。
const int kZipInflateIsolateThreshold = 64 * 1024;
const int kZipCryptoIsolateThreshold = 32 * 1024;
const int kCentralDirectoryIsolateThreshold = 32 * 1024;
const int kTarScanIsolateThreshold = 256 * 1024;

/// 后台归档工作 Isolate 池的运行统计（用于诊断与单测验证复用行为）。
typedef ArchiveWorkerStats = ({
  int totalSpawns,
  int activeWorkers,
  int completedTasks,
});

/// 借助 [TransferableTypedData] 将 `Uint8List` 零拷贝送入长驻后台 Worker 执行变换并零拷贝取回。
Future<Uint8List> offloadBytesTransform(
  Uint8List input,
  Uint8List Function(Uint8List bytes) transform, {
  required int thresholdBytes,
}) async {
  if (input.length < thresholdBytes) {
    return transform(input);
  }
  final packet = TransferableTypedData.fromList(<Uint8List>[input]);
  final resultPacket = await offloadArchiveTask<TransferableTypedData>(() {
    final materialized = packet.materialize().asUint8List();
    final out = transform(materialized);
    return TransferableTypedData.fromList(<Uint8List>[out]);
  });
  return resultPacket.materialize().asUint8List();
}

/// 将产生非字节结果对象的 CPU 密集型解析卸载到长驻后台 Worker（以 [TransferableTypedData] 传参）。
Future<T> offloadBytesParse<T>(
  Uint8List input,
  T Function(Uint8List bytes) parse, {
  required int thresholdBytes,
}) async {
  if (input.length < thresholdBytes) {
    return parse(input);
  }
  final packet = TransferableTypedData.fromList(<Uint8List>[input]);
  return offloadArchiveTask<T>(() {
    final materialized = packet.materialize().asUint8List();
    return parse(materialized);
  });
}

/// 在长驻后台 Worker 池中执行任意可跨 Isolate 传输的同步或异步归档任务。
Future<T> offloadArchiveTask<T>(FutureOr<T> Function() task) {
  return _defaultArchiveWorkerPool.run<T>(task);
}

/// 返回当前默认后台归档 Worker 池的累计创建次数、存活数量与完成任务数。
ArchiveWorkerStats archiveWorkerStats() => _defaultArchiveWorkerPool.stats;

/// 主动关闭默认后台归档 Worker 池（释放空闲 Isolate；后续再次调用会按需重新懒启动）。
Future<void> shutdownArchiveWorker() => _defaultArchiveWorkerPool.shutdown();

final _ArchiveWorkerPool _defaultArchiveWorkerPool = _ArchiveWorkerPool(
  maxWorkers: 2,
  idleTimeout: const Duration(seconds: 20),
);

/// 按需懒启动、空闲自动回收的小型长驻 Isolate 工作池。
final class _ArchiveWorkerPool {
  _ArchiveWorkerPool({required this.maxWorkers, required this.idleTimeout});

  final int maxWorkers;
  final Duration idleTimeout;

  final List<_ArchiveWorkerSlot> _workers = <_ArchiveWorkerSlot>[];
  int _totalSpawns = 0;
  int _completedTasks = 0;
  int _roundRobin = 0;

  ArchiveWorkerStats get stats => (
    totalSpawns: _totalSpawns,
    activeWorkers: _workers.length,
    completedTasks: _completedTasks,
  );

  Future<T> run<T>(FutureOr<T> Function() task) async {
    final slot = _acquireSlot();
    final raw = await slot.execute(() => task());
    _completedTasks++;
    return raw as T;
  }

  _ArchiveWorkerSlot _acquireSlot() {
    _workers.removeWhere((_ArchiveWorkerSlot w) => w.isClosed);

    // 优先复用当前完全空闲的已存活 worker，避免重复 spawn。
    for (final worker in _workers) {
      if (worker.inFlight == 0) return worker;
    }

    // 池未满且已有 worker 忙碌时再按需扩容（例如翻页与预读并行）。
    if (_workers.length < maxWorkers) {
      _totalSpawns++;
      late final _ArchiveWorkerSlot created;
      created = _ArchiveWorkerSlot(
        idleTimeout: idleTimeout,
        onClosed: () => _workers.remove(created),
      );
      _workers.add(created);
      return created;
    }

    // 全部 worker 均在忙时选择当前积压最少的一条（同载轮询）。
    var best = _workers[_roundRobin % _workers.length];
    for (var i = 1; i < _workers.length; i++) {
      final candidate = _workers[(_roundRobin + i) % _workers.length];
      if (candidate.inFlight < best.inFlight) {
        best = candidate;
      }
    }
    _roundRobin = (_roundRobin + 1) % _workers.length;
    return best;
  }

  Future<void> shutdown() async {
    final snapshot = List<_ArchiveWorkerSlot>.of(_workers);
    _workers.clear();
    for (final slot in snapshot) {
      await slot.close();
    }
  }
}

final class _ArchiveWorkerSlot {
  _ArchiveWorkerSlot({required this.idleTimeout, required this.onClosed}) {
    _ready = _spawn();
  }

  final Duration idleTimeout;
  final void Function() onClosed;

  late final Future<SendPort> _ready;
  Isolate? _isolate;
  ReceivePort? _responses;
  ReceivePort? _exitPort;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  Timer? _idleTimer;
  int _nextId = 1;
  bool _closed = false;

  bool get isClosed => _closed;
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
        final completer = _pending.remove(id);
        _scheduleIdleIfEmpty();
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

  Future<Object?> execute(FutureOr<Object?> Function() task) async {
    _idleTimer?.cancel();
    _idleTimer = null;
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;

    try {
      final sendPort = await _ready;
      if (_closed) {
        _pending.remove(id);
        throw StateError('Archive worker closed before dispatch');
      }
      sendPort.send(<Object?>[id, task]);
    } on Object catch (error, stackTrace) {
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

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    onClosed();
    try {
      final sendPort = await _ready;
      sendPort.send(null);
    } on Object {
      // 启动阶段失败或已退出时直接强制回收即可。
      _isolate?.kill(priority: Isolate.immediate);
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
