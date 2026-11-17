import 'package:flutter/services.dart';
import 'package:komga_domain/komga_domain.dart';

/// 根据逻辑尺寸推断设备形态。
///
/// 注意"手机横屏"（如 844×390）仍算 phone：判断平板看**短边**，
/// 否则横屏手机会被误判成平板布局。
///
/// 阈值取舍：1024×768 这类老 iPad / 墨水屏仍按 tablet 处理（它们是主力阅读设备），
/// 只有明显的大屏（≥1280 且短边 ≥700）才进入 desktopLike 三栏布局。
FormFactor formFactorFor(Size logicalSize) {
  final shortest = logicalSize.shortestSide;
  if (logicalSize.width >= 1280 && shortest >= 700)
    return FormFactor.desktopLike;
  if (logicalSize.width >= 600 && shortest >= 600) return FormFactor.tablet;
  return FormFactor.phone;
}

/// 一次设备探测的结果。
class DeviceProfile {
  const DeviceProfile({
    required this.logicalSize,
    this.eink = EinkInfo.unknown,
  });

  final Size logicalSize;
  final EinkInfo eink;

  FormFactor get formFactor => formFactorFor(logicalSize);
  bool get isEink => eink.isEink;

  DeviceProfile copyWith({Size? logicalSize, EinkInfo? eink}) => DeviceProfile(
    logicalSize: logicalSize ?? this.logicalSize,
    eink: eink ?? this.eink,
  );

  @override
  String toString() =>
      'DeviceProfile($formFactor, eink: ${eink.isEink}/${eink.vendor})';
}

/// 墨水屏探测。
///
/// 原生侧（Android）在 M5 实现：查厂商 SDK / 系统属性；
/// 当前实现只有通道骨架，探测失败一律返回 [EinkInfo.unknown]，**绝不阻塞启动**。
class EinkProbe {
  EinkProbe({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('komganative/device');

  final MethodChannel _channel;

  Future<EinkInfo> detect() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('eink');
      if (result == null) return EinkInfo.unknown;
      return EinkInfo(
        isEink: result['isEink'] == true,
        vendor: (result['vendor'] as String?) ?? 'unknown',
      );
    } on MissingPluginException {
      // 桌面/测试环境没有实现，属正常情况。
      return EinkInfo.unknown;
    } on PlatformException {
      return EinkInfo.unknown;
    }
  }
}
