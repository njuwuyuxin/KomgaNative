import 'dart:isolate';
import 'dart:typed_data';

/// 归档 CPU 密集型任务卸载到后台 Isolate 的字节阈值配置（P2-2）。
///
/// 小块数据（如数 KB 的缩略图或单页测试夹具）直接同步处理以避免 Isolate 派发开销；
/// 真实大漫画页（通常 1~10 MB）与大目录/大 TAR 自动经 `Isolate.run` + `TransferableTypedData`
/// 卸载到工作线程，杜绝阻塞 UI 线程掉帧。
const int kZipInflateIsolateThreshold = 64 * 1024;
const int kZipCryptoIsolateThreshold = 32 * 1024;
const int kCentralDirectoryIsolateThreshold = 32 * 1024;
const int kTarScanIsolateThreshold = 256 * 1024;

/// 借助 [TransferableTypedData] 将 `Uint8List` 零拷贝送入后台 Isolate 执行变换并零拷贝取回。
Future<Uint8List> offloadBytesTransform(
  Uint8List input,
  Uint8List Function(Uint8List bytes) transform, {
  required int thresholdBytes,
}) async {
  if (input.length < thresholdBytes) {
    return transform(input);
  }
  final packet = TransferableTypedData.fromList(<Uint8List>[input]);
  final resultPacket = await Isolate.run<TransferableTypedData>(() {
    final materialized = packet.materialize().asUint8List();
    final out = transform(materialized);
    return TransferableTypedData.fromList(<Uint8List>[out]);
  });
  return resultPacket.materialize().asUint8List();
}

/// 将产生非字节结果对象的 CPU 密集型解析卸载到后台 Isolate（以 [TransferableTypedData] 传参）。
Future<T> offloadBytesParse<T>(
  Uint8List input,
  T Function(Uint8List bytes) parse, {
  required int thresholdBytes,
}) async {
  if (input.length < thresholdBytes) {
    return parse(input);
  }
  final packet = TransferableTypedData.fromList(<Uint8List>[input]);
  return Isolate.run<T>(() {
    final materialized = packet.materialize().asUint8List();
    return parse(materialized);
  });
}
