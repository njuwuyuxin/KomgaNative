import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/shelf_view_options.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/pinned_series_provider.dart';
import 'package:yomu/src/widgets/cover_image.dart';
import 'package:yomu/src/widgets/series_context_menu.dart';
import 'package:yomu/src/widgets/series_hero_tag.dart';
import 'package:yomu/src/widgets/unread_badge.dart';
import 'package:material_ui/material_ui.dart';

export 'package:yomu/src/widgets/series_context_menu.dart';

/// 书架上的一个系列卡片。
class SeriesShelfTile extends ConsumerWidget {
  const SeriesShelfTile({
    required this.series,
    this.onTap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
    this.heroTag,
    super.key,
  });

  final Series series;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;
  final String? heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cover = ref.watch(seriesCoverProvider(series.id));
    final Uint8List? bytes = switch (cover) {
      AsyncData<Uint8List?>(:final value) => value,
      _ => null,
    };
    final tag = heroTag ?? seriesHeroTag(series.id);
    final pinned =
        ref.watch(pinnedSeriesIdsProvider).value?.contains(series.id) ?? false;
    final unread = series.booksCount - series.booksReadCount;

    final tile = SeriesTile(
      key: Key('series-${series.id}'),
      series: series,
      semanticsLabel:
          '${series.title}, '
          '${l10n.readOfTotal(series.booksReadCount, series.booksCount)}',
      selecting: selecting,
      selected: selected,
      topStartBadge: unread > 0 ? UnreadBadge(count: unread) : null,
      onTap: onTap,
      onLongPress:
          onLongPress ??
          () => unawaited(
            showSeriesMenu(context, ref, series, heroTag: tag, pinned: pinned),
          ),
      cover: bytes == null || bytes.isEmpty ? null : CoverImage(bytes: bytes),
    );

    if (AppTheme.isEink(Theme.of(context))) return tile;
    return Hero(
      tag: tag,
      child: Material(type: MaterialType.transparency, child: tile),
    );
  }
}

Widget _withUnreadBadge(Series series, Widget child) {
  final unread = series.booksCount - series.booksReadCount;
  if (unread <= 0) return child;
  return Stack(
    clipBehavior: Clip.none,
    children: <Widget>[
      child,
      Positioned(
        left: AppSpacing.xs,
        top: AppSpacing.xs,
        child: UnreadBadge(count: unread),
      ),
    ],
  );
}

/// 列表视图里的一行（UI-P2-7）。
class SeriesShelfRow extends ConsumerWidget {
  const SeriesShelfRow({
    required this.series,
    required this.coverSize,
    this.onTap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
    this.heroTag,
    this.trailing,
    super.key,
  });

  final Series series;
  final ShelfCoverSize coverSize;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;
  final String? heroTag;

  /// 行尾附加动作（例如收藏集详情页的「移出」按钮）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final eink = AppTheme.isEink(theme);
    final dark = theme.brightness == Brightness.dark;
    final motion = AppMotion.of(context);
    final showSelection = selecting || selected;
    final cover = ref.watch(seriesCoverProvider(series.id));
    final Uint8List? bytes = switch (cover) {
      AsyncData<Uint8List?>(:final value) => value,
      _ => null,
    };
    final coverShape = AppShapes.of(context, AppShapes.cover);
    final rowShape = AppShapes.of(context, AppShapes.card);
    final progressLabel = l10n.readOfTotal(
      series.booksReadCount,
      series.booksCount,
    );
    final tag = heroTag ?? seriesHeroTag(series.id);
    final pinned =
        ref.watch(pinnedSeriesIdsProvider).value?.contains(series.id) ?? false;

    final coverBox = AnimatedScale(
      scale: (!eink && selected) ? 0.94 : 1.0,
      duration: motion.quick,
      curve: motion.standardCurve,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: coverShape,
          shadows: selected
              ? AppShadows.selectedCover(
                  context,
                  color: theme.colorScheme.primary,
                )
              : AppShadows.of(context, AppShadows.cover),
        ),
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: coverShape),
          child: SizedBox.fromSize(
            size: coverSize.rowCover,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                bytes == null || bytes.isEmpty
                    ? ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                      )
                    : CoverImage(bytes: bytes),
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: motion.quick,
                    curve: motion.standardCurve,
                    child: ColoredBox(
                      color: eink
                          ? AppTheme.einkPaper.withValues(alpha: 0.32)
                          : Color.lerp(
                              Colors.black,
                              theme.colorScheme.primary,
                              0.4,
                            )!.withValues(alpha: dark ? 0.34 : 0.24),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final coverWidget = eink ? coverBox : Hero(tag: tag, child: coverBox);
    final rowFill = !selected
        ? Colors.transparent
        : eink
        ? AppTheme.einkInk.withValues(alpha: 0.08)
        : theme.colorScheme.primary.withValues(alpha: dark ? 0.18 : 0.10);

    final row = Semantics(
      container: true,
      button: onTap != null,
      selected: showSelection ? selected : null,
      label: '${series.title}, $progressLabel',
      onTap: onTap,
      child: ExcludeSemantics(
        child: PressableScale(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            child: AnimatedContainer(
              duration: motion.quick,
              curve: motion.standardCurve,
              decoration: ShapeDecoration(color: rowFill, shape: rowShape),
              child: InkWell(
                customBorder: rowShape,
                onTap: onTap,
                onLongPress:
                    onLongPress ??
                    () => unawaited(
                      showSeriesMenu(
                        context,
                        ref,
                        series,
                        heroTag: tag,
                        pinned: pinned,
                      ),
                    ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.sm - AppSpacing.xxs,
                  ),
                  child: Row(
                    children: <Widget>[
                      coverWidget,
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    series.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: selected && eink
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: selected
                                          ? (eink
                                                ? AppTheme.einkInk
                                                : theme.colorScheme.primary)
                                          : null,
                                    ),
                                  ),
                                ),
                                if (series.isCloud) ...<Widget>[
                                  const SizedBox(width: AppSpacing.xxs),
                                  Icon(
                                    Icons.cloud_outlined,
                                    size: AppSizes.iconXs,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              progressLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(
                        width: AppSizes.valueColumn,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          child: LinearProgressIndicator(
                            value: series.progress,
                            minHeight: AppSizes.progressBar,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      if (showSelection) ...<Widget>[
                        const SizedBox(width: AppSpacing.md),
                        SelectionBadge(
                          key: const Key('series-selection-badge'),
                          selected: selected,
                        ),
                      ],
                      if (trailing != null) ...<Widget>[
                        const SizedBox(width: AppSpacing.xs),
                        trailing!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return _withUnreadBadge(series, row);
  }
}
