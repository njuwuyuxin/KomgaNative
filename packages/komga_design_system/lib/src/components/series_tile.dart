import 'package:material_ui/material_ui.dart';
import 'package:komga_design_system/src/components/pressable_scale.dart';
import 'package:komga_design_system/src/materials.dart';
import 'package:komga_design_system/src/shapes.dart';
import 'package:komga_design_system/src/tokens.dart';
import 'package:komga_domain/komga_domain.dart';

/// 系列封面卡片：书架网格的基本单元。
///
/// [cover] 负责真实封面（由调用方提供，设计系统不关心它从哪来）；
/// 为空时退化成「渐变色 + 首字」占位，因此断网/缺图也不会破版。
///
/// 质感（UI-P2-1）：封面用 [AppShapes.cover] 的连续圆角 + [AppShadows.cover]
/// 的柔和投影，进度条贴在封面**内侧**底部、角标是胶囊——"封面就是主视觉，
/// 界面元素越少越好"。
///
/// [semanticsLabel] 是读屏播报的整句文案。设计系统不持有 l10n，
/// 默认只播报标题；调用方（如 `SeriesShelfTile`）负责传入本地化的
/// "标题 + 已读进度"。
class SeriesTile extends StatelessWidget {
  const SeriesTile({
    required this.series,
    this.onTap,
    this.cover,
    this.semanticsLabel,
    super.key,
  });

  final Series series;
  final VoidCallback? onTap;

  /// 封面内容，铺满封面区域（通常是一张 `Image`）。
  final Widget? cover;

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
    final shape = AppShapes.of(context, AppShapes.cover);
    final shadows = AppShadows.of(context, AppShadows.cover);
    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticsLabel ?? series.title,
      onTap: onTap,
      // 读屏时只播报上面这一句，而不是把封面首字、角标、标题逐条念一遍。
      child: ExcludeSemantics(
        child: PressableScale(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 封面用 Expanded 吸收剩余高度：文本放大时压缩封面而不是撑破卡片。
                Expanded(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(shape: shape, shadows: shadows),
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
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  series.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 已读/总数：半透明胶囊，压在封面右下角。
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.read, required this.total});

  final int read;
  final int total;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        child: Text(
          '$read/$total',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// 没有封面时的占位：渐变底 + 标题首字。
///
/// 用标题算色相，让同一系列每次渲染颜色一致（黄金图才稳定）。
class _PlaceholderCover extends StatelessWidget {
  const _PlaceholderCover({required this.color, required this.initial});

  final Color color;
  final String initial;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[color, Color.lerp(color, Colors.black, 0.35)!],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: Theme.of(context).textTheme.displayMedium
              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
