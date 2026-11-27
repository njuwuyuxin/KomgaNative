import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:yomu_local_archive/src/archive_worker_slot.dart';

/// 归档 CPU 密集型任务卸载到后台 Isolate 的字节阈值配置（P2-2）。
///
/// 小块数据（如数 KB 的缩略图或单页测试夹具）直接同步处理以避免消息派发开销；
/// 真实大漫画页（通常 1~10 MB）与大目录/大 TAR 自动经长驻工作 Isolate 池 +
/// `TransferableTypedData` 卸载到工作线程，既不阻塞 UI 线程，又避免每页重建 Isolate。
const int kZipInflateIsolateThreshold = 64 * 1024;
const int kZipCryptoIsolateThreshold = 32 * 1024;
const int kCentralDirectoryIsolateThreshold = 32 * 1024;
const int kTarScanIsolateThreshold = 256 * 1024;

/// 单个后台归档任务（单页解压/解密等）的默认超时时间（P2-2），防止异常输入或损坏流永久挂死。
const Duration kDefaultArchiveTaskTimeout = Duration(seconds: 30);

/// 整本目录/大 TAR 头部顺序扫描任务的宽松超时时间（N4），避免慢速 SD 卡读取数 GB 归档时被 30s 误杀。
const Duration kArchiveScanTaskTimeout = Duration(minutes: 5);

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
  Duration? timeout,
}) async {
  if (input.length < thresholdBytes) {
    return parse(input);
  }
  final packet = TransferableTypedData.fromList(<Uint8List>[input]);
  return offloadArchiveTask<T>(() {
    final materialized = packet.materialize().asUint8List();
    return parse(materialized);
  }, timeout: timeout);
}

/// 在长驻后台 Worker 池中执行任意可跨 Isolate 传输的同步或异步归档任务。
Future<T> offloadArchiveTask<T>(
  FutureOr<T> Function() task, {
  Duration? timeout,
}) {
  return _defaultArchiveWorkerPool.run<T>(task, timeout: timeout);
}

/// 返回当前默认后台归档 Worker 池的累计创建次数、存活数量与完成任务数。
ArchiveWorkerStats archiveWorkerStats() => _defaultArchiveWorkerPool.stats;

/// 主动关闭默认后台归档 Worker 池（释放空闲 Isolate 并立即失败所有在途任务；后续再次调用会按需重新懒启动）。
Future<void> shutdownArchiveWorker() => _defaultArchiveWorkerPool.shutdown();

final _ArchiveWorkerPool _defaultArchiveWorkerPool = _ArchiveWorkerPool(
  maxWorkers: 2,
  idleTimeout: const Duration(seconds: 20),
  defaultTaskTimeout: kDefaultArchiveTaskTimeout,
);

/// 按需懒启动、空闲自动回收的小型长驻 Isolate 工作池。
final class _ArchiveWorkerPool {
  _ArchiveWorkerPool({
    required this.maxWorkers,
    required this.idleTimeout,
    required this.defaultTaskTimeout,
  });

  final int maxWorkers;
  final Duration idleTimeout;
  final Duration defaultTaskTimeout;

  final List<ArchiveWorkerSlot> _workers = <ArchiveWorkerSlot>[];
  int _totalSpawns = 0;
  int _completedTasks = 0;
  int _roundRobin = 0;

  ArchiveWorkerStats get stats => (
    totalSpawns: _totalSpawns,
    activeWorkers: _workers.length,
    completedTasks: _completedTasks,
  );

  Future<T> run<T>(FutureOr<T> Function() task, {Duration? timeout}) async {
    final slot = _acquireSlot();
    final raw = await slot.execute(
      () => task(),
      timeout: timeout ?? defaultTaskTimeout,
    );
    _completedTasks++;
    return raw as T;
  }

  ArchiveWorkerSlot _acquireSlot() {
    _workers.removeWhere((ArchiveWorkerSlot w) => w.isClosed);

    final accepting = _workers
        .where((ArchiveWorkerSlot w) => w.isAcceptingWork)
        .toList(growable: false);

    // 优先复用当前完全空闲的已存活 worker，避免重复 spawn。
    for (final worker in accepting) {
      if (worker.inFlight == 0) return worker;
    }

    // 池未满且已有 worker 忙碌（或正在排空）时再按需扩容（例如翻页与预读并行）。
    if (accepting.length < maxWorkers) {
      _totalSpawns++;
      late final ArchiveWorkerSlot created;
      created = ArchiveWorkerSlot(
        idleTimeout: idleTimeout,
        onClosed: () => _workers.remove(created),
      );
      _workers.add(created);
      return created;
    }

    // 全部可用 worker 均在忙时选择当前积压最少的一条（同载轮询）。
    var best = accepting[_roundRobin % accepting.length];
    for (var i = 1; i < accepting.length; i++) {
      final candidate = accepting[(_roundRobin + i) % accepting.length];
      if (candidate.inFlight < best.inFlight) {
        best = candidate;
      }
    }
    _roundRobin = (_roundRobin + 1) % accepting.length;
    return best;
  }

  Future<void> shutdown() async {
    final snapshot = List<ArchiveWorkerSlot>.of(_workers);
    _workers.clear();
    for (final slot in snapshot) {
      await slot.close();
    }
  }
}
