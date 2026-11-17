/// 设计系统：token、主题、断点、基础组件。
///
/// 规则：**数值只从 token 取**，禁止在页面里写魔法数字；三套主题
/// （light / dark / eink）必须同时可渲染，黄金图按矩阵覆盖。
library;

export 'src/breakpoints.dart';
export 'src/components/series_tile.dart';
export 'src/components/status_view.dart';
export 'src/themes.dart';
export 'src/tokens.dart';
