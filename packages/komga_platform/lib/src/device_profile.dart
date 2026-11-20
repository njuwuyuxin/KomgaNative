import 'package:flutter/services.dart';
import 'package:komga_domain/komga_domain.dart';

/// 墨水屏探测。
///
/// 原生侧（Android）查厂商 SDK / 系统属性；
/// 桌面/测试环境无平台实现时一律返回 [EinkInfo.unknown]，**绝不阻塞启动**。
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
      return EinkInfo.unknown;
    } on PlatformException {
      return EinkInfo.unknown;
    }
  }
}
