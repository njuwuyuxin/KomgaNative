/// 阅读器布局计算：纯函数、无 UI 依赖。
///
/// 为什么不用 `dart:ui` 的 Rect/Size：本包必须能在纯 Dart VM 下毫秒级测试，
/// 不引入 Flutter 引擎。Widget 层负责把 [RectD] 转成 `Rect`。
library;

export 'src/geometry.dart';
export 'src/layout.dart';
export 'src/preload.dart';
export 'src/spreads.dart';
export 'src/vertical.dart';
