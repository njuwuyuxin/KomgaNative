import 'package:yomu_design_system/src/motion.dart';
import 'package:yomu_design_system/src/shapes.dart';
import 'package:yomu_design_system/src/themes.dart';
import 'package:material_ui/material_ui.dart';

/// 骨架块：加载中的占位色块。
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({this.shape, super.key});

  /// 外形；为空时用卡片形状（会按主题退化）。
  final ShapeBorder? shape;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        // 墨水屏的 `surfaceContainerHighest` 没定义、退化成纸白（`ColorScheme`
        // 对容器色的兜底就是 surface），骨架会变成白底白块，加载中什么都看不见
        // （`series_loading@eink` 黄金图抓到过）。灰阶屏上用 12% 墨色，
        // 约等于浅灰，静态也看得出"这里在加载"。
        color: AppTheme.isEink(theme)
            ? AppTheme.einkInk.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest,
        shape: shape ?? AppShapes.of(context, AppShapes.card),
      ),
    );
  }
}

/// 微光：给骨架加一层缓慢扫过的高光（UI-P2-8）。
///
/// - 普通设备：一条柔和的亮带从左到右循环扫过；
/// - 墨水屏 / 系统"减少动态效果"：**完全不加**，保持静态骨架
///   （灰阶屏上的微光只会变成一层拖影，还费电）；
/// - 周期取 `AppMotion.shimmer`，不要在页面里写死。
class Shimmer extends StatefulWidget {
  const Shimmer({required this.child, super.key});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = AppMotion.of(context);
    if (!motion.enabled) {
      _controller?.dispose();
      _controller = null;
      return;
    }
    final controller = _controller ??= AnimationController(
      vsync: this,
      duration: motion.shimmer,
    );
    if (controller.duration != motion.shimmer) {
      controller.duration = motion.shimmer;
    }
    if (!controller.isAnimating) controller.repeat();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;
    return AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        // 3 段渐变、两端透明：亮带扫过时没有边界，不会看到"一条硬边在动"。
        final t = controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (Rect bounds) => LinearGradient(
            colors: const <Color>[
              Color(0x00FFFFFF),
              Color(0x33FFFFFF),
              Color(0x00FFFFFF),
            ],
            stops: const <double>[0.35, 0.5, 0.65],
            begin: Alignment(-2.6 + 5.2 * t, -0.4),
            end: Alignment(-1.6 + 5.2 * t, 0.4),
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}
