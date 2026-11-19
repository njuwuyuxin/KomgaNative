import 'dart:io';

/// 网络类型的粗分类（DLD-01）。
enum NetworkKind {
  /// 有 Wi-Fi 接口（`wlan*`）。
  wifi,

  /// 只有蜂窝接口（`rmnet*` / `ccmni*` / `pdp*`）。
  cellular,

  /// 判断不出来（桌面、模拟器命名不同、或查询失败）。
  ///
  /// **"判断不出来"绝不等于"不能用"**：拿不到信息时一律放行，
  /// 否则用户会在一个完全正常的网络下被拦住，还找不到原因。
  unknown,
}

/// 当前网络类型探测。
///
/// 为什么用网卡名而不是插件：本项目不新增依赖（AGENTS 的反模式清单），
/// `dart:io` 的 [NetworkInterface.list] 已经能区分 Wi-Fi 与蜂窝——
/// Android 上 Wi-Fi 是 `wlan0`、蜂窝是 `rmnet_data*`，iOS 上分别是 `en0` 与 `pdp_ip0`。
/// 这是**启发式**判断，不是系统 API 的权威答案：所以只要没看到明确的蜂窝特征，
/// 就当 `unknown` 放行。
abstract interface class NetworkProbe {
  Future<NetworkKind> current();
}

/// 真实实现：读本机网卡。
class SystemNetworkProbe implements NetworkProbe {
  const SystemNetworkProbe();

  @override
  Future<NetworkKind> current() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      var cellular = false;
      for (final item in interfaces) {
        final name = item.name.toLowerCase();
        // Wi-Fi 优先：同一台机器可能同时有 Wi-Fi 与蜂窝接口（通话中）。
        if (name.startsWith('wlan') || name.startsWith('en0')) {
          return NetworkKind.wifi;
        }
        if (name.startsWith('rmnet') ||
            name.startsWith('ccmni') ||
            name.startsWith('pdp_ip') ||
            name.startsWith('clat')) {
          cellular = true;
        }
      }
      return cellular ? NetworkKind.cellular : NetworkKind.unknown;
    } on Object {
      // 查不到就放行（见 [NetworkKind.unknown] 的注释）。
      return NetworkKind.unknown;
    }
  }
}
