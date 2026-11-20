/// 平台差异的唯一入口。
///
/// 原则：**只有这里允许出现 MethodChannel / 原生判断**，其余代码用纯 Dart 的
/// 抽象值（如 [EinkInfo]），断点判断统一收敛至 `komga_design_system` 的 `WindowSizeClass`（AGENTS.md 不变量 6）。
library;

export 'src/device_profile.dart';
export 'src/hardware_keys.dart';
export 'src/network_probe.dart';
export 'src/wakelock.dart';
