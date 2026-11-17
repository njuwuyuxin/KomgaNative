import 'package:material_ui/material_ui.dart';
import 'package:komga_design_system/src/tokens.dart';
import 'package:komga_domain/komga_domain.dart';

/// 系列封面卡片：书架网格的基本单元。
///
/// M0 用「渐变色 + 首字」占位，M1 接入 `/series/{id}/thumbnail`。
class SeriesTile extends StatelessWidget {
  const SeriesTile({required this.series, this.onTap, super.key});

  final Series series;
  final VoidCallback? onTap;

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
    return Semantics(
      container: true,
      button: onTap != null,
      label: '${series.title}，${series.booksReadCount}/${series.booksCount} 已读',
      onTap: onTap,
      // 读屏时只播报上面这一句，而不是把封面首字、角标、标题逐条念一遍。
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 封面用 Expanded 吸收剩余高度：文本放大时压缩封面而不是撑破卡片。
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          _placeholder,
                          Color.lerp(_placeholder, Colors.black, 0.35)!,
                        ],
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        Center(
                          child: Text(
                            _initial,
                            style: theme.textTheme.displayMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (series.booksCount > 0)
                          Positioned(
                            right: AppSpacing.xs,
                            bottom: AppSpacing.xs,
                            child: _CountBadge(
                              read: series.booksReadCount,
                              total: series.booksCount,
                            ),
                          ),
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
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.sm),
                child: LinearProgressIndicator(
                  value: series.progress,
                  minHeight: 3,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.read, required this.total});

  final int read;
  final int total;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2,
        ),
        child: Text(
          '$read/$total',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
