import 'package:material_ui/material_ui.dart';
import 'package:yomu_design_system/src/components/pressable_scale.dart';
import 'package:yomu_design_system/src/components/selection_badge.dart';
import 'package:yomu_design_system/src/materials.dart';
import 'package:yomu_design_system/src/motion.dart';
import 'package:yomu_design_system/src/shapes.dart';
import 'package:yomu_design_system/src/themes.dart';
import 'package:yomu_design_system/src/tokens.dart';
import 'package:yomu_domain/yomu_domain.dart';

part 'series_tile_parts.dart';

/// 系列封面卡片：书架网格的基本单元。
///
/// [cover] 负责真实封面（由调用方提供，设计系统不关心它从哪来）；
/// 为空时退化成「渐变色 + 首字」占位，因此断网/缺图也不会破版。
///
/// 质感（UI-P2-1）：封面用 [AppShapes.cover] 的连续圆角 + [AppShadows.cover]
/// 的柔和投影，进度条贴在封面**内侧**底部、角标是胶囊——"封面就是主视觉，
/// 界面元素越少越好"。
///
/// 多选态（[selecting] / [selected]）：不在整卡外画硬线框，改为在封面右上角
/// 显示圆形选择指示器；选中时封面轻微内收（0.94）并叠加方向性柔光遮罩、主色弥散
/// 光晕与实心对勾，标题同步轻染主色（墨水屏退化为纯黑白高对比对勾 + 轻白罩，不缩放）。
///
/// [semanticsLabel] 是读屏播报的整句文案。设计系统不持有 l10n，
/// 默认只播报标题；调用方（如 `SeriesShelfTile`）负责传入本地化的
/// "标题 + 已读进度"。
class SeriesTile extends StatelessWidget {
  const SeriesTile({
    required this.series,
    this.onTap,
    this.onLongPress,
    this.cover,
    this.topStartBadge,
    this.selecting = false,
    this.selected = false,
    this.semanticsLabel,
    super.key,
  });

  static const double _selectedCoverScale = 0.94;

  final Series series;
  final VoidCallback? onTap;

  /// 长按（打开上下文菜单，UI-P2-5）。按下的缩放反馈由 [PressableScale] 负责。
  final VoidCallback? onLongPress;

  /// 封面内容，铺满封面区域（通常是一张 `Image`）。
  final Widget? cover;

  /// 封面左上角角标（如未读本数）：放进封面内部随封面同步按压与选中缩放。
  final Widget? topStartBadge;

  /// 是否处于批量管理模式：为 true 时未选卡片也展示右上角空心选择环。
  final bool selecting;

  /// 当前卡片是否被选中。
  final bool selected;

  /// 读屏播报文案；为空时只播报标题（不硬编码任何语言的"已读"）。
  final String? semanticsLabel;

  static const List<Color> _placeholderColors = <Color>[
    Color(0xFF4F6BFF),
    Color(0xFF2FA37C),
    Color(0xFFB4622F),
    Color(0xFF8A4FBF),
    Color(0xFFB03A4A),
    Color(0xFF3C7A9E),
  ];

  Color get _placeholder {
    var sum = 0;
    for (final unit in series.title.codeUnits) {
      sum += unit;
    }
    return _placeholderColors[sum % _placeholderColors.length];
  }

  String get _initial {
    final trimmed = series.title.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eink = AppTheme.isEink(theme);
    final dark = theme.brightness == Brightness.dark;
    final motion = AppMotion.of(context);
    final shape = AppShapes.of(context, AppShapes.cover);
    final showSelection = selecting || selected;
    final shadows = selected
        ? AppShadows.selectedCover(context, color: theme.colorScheme.primary)
        : AppShadows.of(context, AppShadows.cover);
    final baseTitleStyle =
        theme.textTheme.titleSmall ?? const TextStyle(fontSize: 14);
    final titleStyle = baseTitleStyle.copyWith(
      fontWeight: selected && eink ? FontWeight.w700 : FontWeight.w600,
      color: selected
          ? (eink ? AppTheme.einkInk : theme.colorScheme.primary)
          : null,
    );

    return Semantics(
      container: true,
      button: onTap != null,
      selected: showSelection ? selected : null,
      label: semanticsLabel ?? series.title,
      onTap: onTap,
      // 读屏时只播报上面这一句，而不是把封面首字、角标、标题逐条念一遍。
      child: ExcludeSemantics(
        child: PressableScale(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onLongPress: onLongPress,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 封面用 Expanded 吸收剩余高度：文本放大时压缩封面而不是撑破卡片。
                Expanded(
                  child: AnimatedScale(
                    scale: (!eink && selected) ? _selectedCoverScale : 1.0,
                    duration: motion.quick,
                    curve: motion.standardCurve,
                    child: AnimatedContainer(
                      duration: motion.quick,
                      curve: motion.standardCurve,
                      decoration: ShapeDecoration(
                        shape: shape,
                        shadows: shadows,
                      ),
                      child: ClipPath(
                        clipper: ShapeBorderClipper(shape: shape),
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            cover ??
                                _PlaceholderCover(
                                  color: _placeholder,
                                  initial: _initial,
                                ),
                            if (series.booksCount > 0) ...<Widget>[
                              // 进度条贴在封面内侧底部：比放在标题下面更"像书"，
                              // 也不占额外的垂直空间。
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: LinearProgressIndicator(
                                  value: series.progress,
                                  minHeight: AppSizes.progressBar,
                                  backgroundColor: Colors.black.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: AppSpacing.xs,
                                bottom: AppSpacing.sm,
                                child: _CountBadge(
                                  read: series.booksReadCount,
                                  total: series.booksCount,
                                ),
                              ),
                            ],
                            if (topStartBadge != null)
                              Positioned(
                                left: AppSpacing.xs,
                                top: AppSpacing.xs,
                                child: topStartBadge!,
                              ),
                            IgnorePointer(
                              child: AnimatedOpacity(
                                opacity: selected ? 1 : 0,
                                duration: motion.quick,
                                curve: motion.standardCurve,
                                child: _SelectedCoverVeil(
                                  eink: eink,
                                  dark: dark,
                                ),
                              ),
                            ),
                            Positioned(
                              right: AppSpacing.sm,
                              top: AppSpacing.sm,
                              child: IgnorePointer(
                                child: AnimatedSwitcher(
                                  duration: motion.quick,
                                  switchInCurve: motion.emphasizedCurve,
                                  switchOutCurve: motion.exitCurve,
                                  transitionBuilder:
                                      (
                                        Widget child,
                                        Animation<double> animation,
                                      ) => FadeTransition(
                                        opacity: animation,
                                        child: ScaleTransition(
                                          scale: Tween<double>(
                                            begin: 0.7,
                                            end: 1.0,
                                          ).animate(animation),
                                          child: child,
                                        ),
                                      ),
                                  child: showSelection
                                      ? SelectionBadge(
                                          key: const Key(
                                            'series-selection-badge',
                                          ),
                                          selected: selected,
                                          onCover: true,
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AnimatedDefaultTextStyle(
                        duration: motion.quick,
                        curve: motion.standardCurve,
                        style: titleStyle,
                        child: Text(
                          series.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (series.isCloud) ...<Widget>[
                      const SizedBox(width: AppSpacing.xxs),
                      Icon(
                        Icons.cloud_outlined,
                        key: Key('series-cloud-${series.id}'),
                        size: AppSizes.iconXs,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
