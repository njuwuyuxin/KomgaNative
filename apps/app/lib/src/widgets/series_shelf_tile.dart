import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_view_options.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/series_read_provider.dart';
import 'package:komga_native/src/widgets/context_menu.dart';
import 'package:komga_native/src/widgets/cover_image.dart';
import 'package:material_ui/material_ui.dart';

/// 长按系列卡片能做的事（UI-P2-5）。
enum SeriesMenuAction { markRead, markUnread, viewDetails }

/// 书架上的一个系列卡片：把"封面字节 + Hero + 长按菜单"翻译成 [SeriesTile] 认的 widget。
///
/// 关键点：
/// - **没有封面时必须把 `cover` 传成 null**，让 [SeriesTile] 画占位图；
///   传一个空 widget 会把占位图顶掉，屏幕上就是一块白板；
/// - 封面出第一帧时淡入（[CoverImage]，UI-P2-1）；
/// - Hero（UI-P2-2）：tag 是 `series-<id>`，系列详情页头部用同一个 tag。
///   墨水屏关掉 Hero——灰阶屏上的共享元素只会变成一层拖影；
/// - 长按弹上下文菜单：整系列标记已读/未读、查看详情。
class SeriesShelfTile extends ConsumerWidget {
  const SeriesShelfTile({required this.series, this.onTap, super.key});

  final Series series;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cover = ref.watch(seriesCoverProvider(series.id));
    final Uint8List? bytes = switch (cover) {
      AsyncData<Uint8List?>(:final value) => value,
      _ => null,
    };

    final tile = SeriesTile(
      key: Key('series-${series.id}'),
      series: series,
      // 整张卡片是一个按钮：读屏只念这一句，不把封面首字/角标/标题分开念。
      semanticsLabel:
          '${series.title}, '
          '${l10n.readOfTotal(series.booksReadCount, series.booksCount)}',
      onTap: onTap,
      onLongPress: () => unawaited(showSeriesMenu(context, ref, series)),
      cover: bytes == null || bytes.isEmpty ? null : CoverImage(bytes: bytes),
    );

    if (AppTheme.isEink(Theme.of(context))) return tile;
    return Hero(tag: seriesHeroTag(series.id), child: tile);
  }
}

/// 系列封面的 Hero tag（书架 → 详情页头部）。
String seriesHeroTag(String seriesId) => 'series-$seriesId';

/// 列表视图里的一行（UI-P2-7）：封面 + 标题 + 进度，长按菜单与网格卡片一致。
///
/// 与 [SeriesShelfTile] 共用 `_SeriesMenu` 的逻辑，只是排版不同：
/// 列表适合"书名长、系列多"的书库，扫读比网格快。
class SeriesShelfRow extends ConsumerWidget {
  const SeriesShelfRow({
    required this.series,
    required this.coverSize,
    this.onTap,
    super.key,
  });

  final Series series;
  final ShelfCoverSize coverSize;
  final VoidCallback? onTap;

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

    final row = Semantics(
      container: true,
      button: onTap != null,
      label: '${series.title}, $progressLabel',
      onTap: onTap,
      child: ExcludeSemantics(
        child: PressableScale(
          child: InkWell(
            onTap: onTap,
            onLongPress: () => unawaited(showSeriesMenu(context, ref, series)),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: shape,
                      shadows: AppShadows.of(context, AppShadows.cover),
                    ),
                    child: ClipPath(
                      clipper: ShapeBorderClipper(shape: shape),
                      child: SizedBox.fromSize(
                        size: coverSize.rowCover,
                        child: bytes == null || bytes.isEmpty
                            ? ColoredBox(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                              )
                            : CoverImage(bytes: bytes),
                      ),
                    ),
                  ),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (AppTheme.isEink(theme)) return row;
    return Hero(tag: seriesHeroTag(series.id), child: row);
  }
}

/// 长按系列的上下文菜单（UI-P2-5），网格卡片与列表行共用。
Future<void> showSeriesMenu(
  BuildContext context,
  WidgetRef ref,
  Series series,
) async {
  final l10n = AppLocalizations.of(context);
  // 长按先给一次轻触反馈：菜单弹出前用户要知道"按到了"。
  unawaited(AppHaptics.light());
  final action = await showContextMenu<SeriesMenuAction>(
    context: context,
    anchor: context,
    entries: <ContextMenuEntry<SeriesMenuAction>>[
      ContextMenuEntry(
        value: SeriesMenuAction.markRead,
        label: l10n.markAllRead,
        icon: Icons.done_all,
      ),
      ContextMenuEntry(
        value: SeriesMenuAction.markUnread,
        label: l10n.markAllUnread,
        icon: Icons.remove_done,
      ),
      ContextMenuEntry(
        value: SeriesMenuAction.viewDetails,
        label: l10n.viewDetails,
        icon: Icons.info_outline,
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case SeriesMenuAction.viewDetails:
      await context.push('/series/${series.id}');
    case SeriesMenuAction.markRead:
      await ref
          .read(seriesReadProvider.notifier)
          .setRead(series.id, read: true);
    case SeriesMenuAction.markUnread:
      await ref
          .read(seriesReadProvider.notifier)
          .setRead(series.id, read: false);
  }
}
