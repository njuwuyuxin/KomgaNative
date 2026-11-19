/// 平台差异的唯一入口。
///
/// 原则：**只有这里允许出现 MethodChannel / 原生判断**，其余代码用纯 Dart 的
/// 抽象值（[DeviceProfile] / [EinkInfo]），因此黄金图与单测不依赖真机。
library;

export 'src/device_profile.dart';
export 'src/hardware_keys.dart';
export 'src/network_probe.dart';
export 'src/wakelock.dart';
