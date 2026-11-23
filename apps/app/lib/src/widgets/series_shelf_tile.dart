import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_view_options.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/pinned_series_provider.dart';
import 'package:komga_native/src/widgets/cover_image.dart';
import 'package:komga_native/src/widgets/series_context_menu.dart';
import 'package:komga_native/src/widgets/series_hero_tag.dart';
import 'package:komga_native/src/widgets/unread_badge.dart';
import 'package:material_ui/material_ui.dart';

export 'package:komga_native/src/widgets/series_context_menu.dart';

/// 书架上的一个系列卡片。
class SeriesShelfTile extends ConsumerWidget {
  const SeriesShelfTile({
    required this.series,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.heroTag,
    super.key,
  });

  final Series series;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
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

    final tile = SeriesTile(
      key: Key('series-${series.id}'),
      series: series,
      semanticsLabel:
          '${series.title}, '
          '${l10n.readOfTotal(series.booksReadCount, series.booksCount)}',
      onTap: onTap,
      onLongPress:
          onLongPress ??
          () => unawaited(
            showSeriesMenu(context, ref, series, heroTag: tag, pinned: pinned),
          ),
      cover: bytes == null || bytes.isEmpty ? null : CoverImage(bytes: bytes),
    );
    final badged = _withSelection(
      context,
      _withUnreadBadge(series, tile),
      selected,
    );

    if (AppTheme.isEink(Theme.of(context))) return badged;
    return Hero(
      tag: tag,
      child: Material(type: MaterialType.transparency, child: badged),
    );
  }
}

Widget _withSelection(BuildContext context, Widget child, bool selected) {
  if (!selected) return child;
  final eink = AppTheme.isEink(Theme.of(context));
  return DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(AppRadii.md),
      border: Border.all(
        color: eink ? AppTheme.einkInk : Theme.of(context).colorScheme.primary,
        width: AppSizes.hairline,
      ),
    ),
    child: child,
  );
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
    this.selected = false,
    this.heroTag,
    this.trailing,
    super.key,
  });

  final Series series;
  final ShelfCoverSize coverSize;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final String? heroTag;

  /// 行尾附加动作（例如收藏集详情页的「移出」按钮）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cover = ref.watch(seriesCoverProvider(series.id));
    final Uint8List? bytes = switch (cover) {
      AsyncData<Uint8List?>(:final value) => value,
      _ => null,
    };
    final shape = AppShapes.of(context, AppShapes.cover);
    final progressLabel = l10n.readOfTotal(
      series.booksReadCount,
      series.booksCount,
    );
    final tag = heroTag ?? seriesHeroTag(series.id);
    final pinned =
        ref.watch(pinnedSeriesIdsProvider).value?.contains(series.id) ?? false;

    final coverBox = DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: AppShadows.of(context, AppShadows.cover),
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: SizedBox.fromSize(
          size: coverSize.rowCover,
          child: bytes == null || bytes.isEmpty
              ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
              : CoverImage(bytes: bytes),
        ),
      ),
    );
    final coverWidget = AppTheme.isEink(theme)
        ? coverBox
        : Hero(tag: tag, child: coverBox);

    final row = Semantics(
      container: true,
      button: onTap != null,
      label: '${series.title}, $progressLabel',
      onTap: onTap,
      child: ExcludeSemantics(
        child: PressableScale(
          child: InkWell(
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
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
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
                        Text(
                          series.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
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
    );

    return _withSelection(context, _withUnreadBadge(series, row), selected);
  }
}
