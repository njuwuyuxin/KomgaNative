import 'dart:async';

import 'package:komga_design_system/src/components/glass_control_colors.dart';
import 'package:komga_design_system/src/components/glass_surface.dart';
import 'package:komga_design_system/src/components/pressable_scale.dart';
import 'package:komga_design_system/src/components/sliding_selection_track.dart';
import 'package:komga_design_system/src/haptics.dart';
import 'package:komga_design_system/src/materials.dart';
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
/// 选中胶囊由 [SlidingSelectionTrack] 统一绘制：切换选项时胶囊从旧段弹到
/// 新段（弹簧与 `PressableScale` 同源），文字颜色跟着同一进度过渡，
/// 不再是每段各自瞬间加深。
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
    final shape = AppShapes.of(context, AppShapes.bar);
    final selectedIndex = segments.indexWhere(
      (GlassSegment<T> segment) => segment.value == selected,
    );
    final selectedColors = GlassControlColors.resolve(context, selected: true);

    final surface = GlassSurface(
      shape: shape,
      shadows: AppShadows.card,
      child: SizedBox(
        height: AppSizes.glassSegmentHeight,
        child: SlidingSelectionTrack(
          itemCount: segments.length,
          selectedIndex: selectedIndex < 0 ? null : selectedIndex,
          padding: const EdgeInsets.all(AppSizes.glassControlInset),
          pillColor: selectedColors.fill ?? Colors.transparent,
          pillShape: shape,
          scrollable: scrollable,
          itemBuilder: (BuildContext context, int index, double selection) =>
              _GlassSegmentButton<T>(
                segment: segments[index],
                selected: index == selectedIndex,
                selection: selection,
                scrollable: scrollable,
                onSelected: onSelected,
              ),
        ),
      ),
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
    required this.selection,
    required this.scrollable,
    required this.onSelected,
  });

  final GlassSegment<T> segment;
  final bool selected;

  /// 选中进度（0 → 1），由滑块的弹簧驱动。
  final double selection;
  final bool scrollable;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColors = GlassControlColors.resolve(context, selected: true);
    final unselectedColors = GlassControlColors.resolve(context, subdued: true);
    final unselectedForeground = unselectedColors.foreground;
    final selectedForeground = selectedColors.foreground;
    // 端点直接返回原色：Color.lerp 会经过浮点色彩空间，稳态下像素会有
    // 肉眼看不见、但黄金图能抓到的差异。
    final Color foreground = selection <= 0
        ? unselectedForeground
        : selection >= 1
        ? selectedForeground
        : Color.lerp(unselectedForeground, selectedForeground, selection) ??
              selectedForeground;

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
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: scrollable ? AppSpacing.md : AppSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (segment.icon != null) ...<Widget>[
                    Icon(
                      segment.icon,
                      size: AppSizes.iconXs,
                      color: foreground,
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
                        color: foreground,
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
