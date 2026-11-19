import 'dart:async';

import 'package:komga_design_system/src/components/glass_control_colors.dart';
import 'package:komga_design_system/src/components/glass_surface.dart';
import 'package:komga_design_system/src/components/pressable_scale.dart';
import 'package:komga_design_system/src/haptics.dart';
import 'package:komga_design_system/src/materials.dart';
import 'package:komga_design_system/src/motion.dart';
import 'package:komga_design_system/src/shapes.dart';
import 'package:komga_design_system/src/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 一个分段选项。[key] 给测试 / 埋点定位用。
@immutable
class GlassSegment<T> {
  const GlassSegment({
    required this.value,
    required this.label,
    this.icon,
    this.key,
  });

  final T value;
  final String label;
  final IconData? icon;
  final Key? key;
}

/// 玻璃分段控件（iOS 的 UISegmentedControl 形态）。
///
/// 一条玻璃胶囊里放若干段，选中的那段嵌一块中性胶囊 + 主色文字。
/// 同时用于三处以上：收藏集/阅读列表切换、设置页的主题与语言、书架的库筛选
/// （库数量不定，改用 [scrollable] 横向滚动，宽度按内容）。
///
/// 墨水屏：选中段反白（墨底纸字），其余透明；圆角与阴影由 token 退化。
class GlassSegmentedControl<T> extends StatelessWidget {
  const GlassSegmentedControl({
    required this.segments,
    required this.selected,
    required this.onSelected,
    this.scrollable = false,
    super.key,
  });

  final List<GlassSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelected;

  /// true = 不拉伸、按内容排并允许横向滚动（选项数量不定时用）。
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      for (var i = 0; i < segments.length; i++)
        if (scrollable)
          Padding(
            padding: EdgeInsets.only(
              right: i == segments.length - 1 ? 0 : AppSpacing.xs,
            ),
            child: _GlassSegmentButton<T>(
              segment: segments[i],
              selected: segments[i].value == selected,
              scrollable: scrollable,
              onSelected: onSelected,
            ),
          )
        else
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: i == segments.length - 1 ? 0 : AppSpacing.xs,
              ),
              child: _GlassSegmentButton<T>(
                segment: segments[i],
                selected: segments[i].value == selected,
                scrollable: scrollable,
                onSelected: onSelected,
              ),
            ),
          ),
    ];

    final Widget content;
    if (scrollable) {
      // 横向滚动模式按内容定宽：库少的时候不该拉成一条空胶囊（平板上很明显）。
      content = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(AppSizes.glassControlInset),
        child: SizedBox(
          height: AppSizes.glassSegmentHeight - AppSizes.glassControlInset * 2,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: items,
          ),
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.all(AppSizes.glassControlInset),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: items,
        ),
      );
    }

    final surface = GlassSurface(
      shape: AppShapes.of(context, AppShapes.bar),
      shadows: AppShadows.card,
      child: SizedBox(height: AppSizes.glassSegmentHeight, child: content),
    );
    return scrollable
        ? Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            child: surface,
          )
        : surface;
  }
}

class _GlassSegmentButton<T> extends StatelessWidget {
  const _GlassSegmentButton({
    required this.segment,
    required this.selected,
    required this.scrollable,
    required this.onSelected,
  });

  final GlassSegment<T> segment;
  final bool selected;
  final bool scrollable;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final motion = AppMotion.of(context);
    final shape = AppShapes.of(context, AppShapes.bar);
    final colors = GlassControlColors.resolve(
      context,
      selected: selected,
      subdued: !selected,
    );

    void handleTap() {
      if (selected) return;
      unawaited(AppHaptics.selection());
      onSelected(segment.value);
    }

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: segment.label,
      onTap: handleTap,
      child: ExcludeSemantics(
        child: PressableScale(
          child: GestureDetector(
            key: segment.key,
            behavior: HitTestBehavior.opaque,
            onTap: handleTap,
            child: AnimatedContainer(
              duration: motion.quick,
              curve: motion.standardCurve,
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(
                horizontal: scrollable ? AppSpacing.md : AppSpacing.sm,
              ),
              decoration: ShapeDecoration(
                shape: shape,
                color: colors.fill ?? Colors.transparent,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (segment.icon != null) ...<Widget>[
                    Icon(
                      segment.icon,
                      size: AppSizes.iconXs,
                      color: colors.foreground,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Flexible(
                    child: Text(
                      segment.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: colors.foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
