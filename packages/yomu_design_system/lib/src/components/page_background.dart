import 'package:yomu_design_system/src/themes.dart';
import 'package:material_ui/material_ui.dart';

/// 页面底色：表面色 + 两团极淡的主色/第三色光晕（aurora）。
///
/// 为什么加它：液态玻璃要"有东西可透"才看得出是玻璃。纯平的白/黑底上，
/// 顶部标题栏只会像一块灰色圆角矩形。光晕只在顶角附近、透明度低于 16%，
/// 不影响文字对比度，也压不住封面。
///
/// 墨水屏直接透传：灰阶上的渐晕只会变成一层脏灰，纸色底更清楚。
class GlassPageBackground extends StatelessWidget {
  const GlassPageBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (AppTheme.isEink(theme)) return child;
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Stack(
      children: <Widget>[
        Positioned.fill(child: ColoredBox(color: scheme.surface)),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.95, -0.95),
                  radius: 1.15,
                  colors: <Color>[
                    scheme.primary.withValues(alpha: dark ? 0.20 : 0.13),
                    scheme.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(1.05, -0.35),
                  radius: 0.95,
                  colors: <Color>[
                    scheme.tertiary.withValues(alpha: dark ? 0.16 : 0.10),
                    scheme.tertiary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}
