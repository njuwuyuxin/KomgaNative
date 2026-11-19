/// 设计系统：token、主题、断点、基础组件。
///
/// 规则：**数值只从 token 取**，禁止在页面里写魔法数字；三套主题
/// （light / dark / eink）必须同时可渲染，黄金图按矩阵覆盖。
/// 动效 / 材质 / 形状 / 阴影 token 都自带墨水屏退化，页面不要自己判断。
library;

export 'src/breakpoints.dart';
export 'src/components/frosted_surface.dart';
export 'src/components/glass_optics_layers.dart';
export 'src/components/glass_surface.dart';
export 'src/components/pressable_scale.dart';
export 'src/components/series_tile.dart';
export 'src/components/skeleton.dart';
export 'src/components/status_view.dart';
export 'src/glass_optics.dart';
export 'src/haptics.dart';
export 'src/materials.dart';
export 'src/motion.dart';
export 'src/shapes.dart';
export 'src/themes.dart';
export 'src/tokens.dart';
export 'src/typography.dart';
