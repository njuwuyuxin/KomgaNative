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
import 'package:komga_native/src/screens/series_detail_args.dart';
import 'package:komga_native/src/widgets/context_menu.dart';
import 'package:komga_native/src/widgets/cover_image.dart';
import 'package:komga_native/src/widgets/series_hero_tag.dart';
import 'package:material_ui/material_ui.dart';

/// 长按系列卡片能做的事（UI-P2-5）。
enum SeriesMenuAction { markRead, markUnread, viewDetails }

/// 书架上的一个系列卡片：把"封面字节 + Hero + 长按菜单"翻译成 [SeriesTile] 认的 widget。
///
/// 关键点：
/// - **没有封面时必须把 `cover` 传成 null**，让 [SeriesTile] 画占位图；
///   传一个空 widget 会把占位图顶掉，屏幕上就是一块白板；
/// - 封面出第一帧时淡入（[CoverImage]，UI-P2-1）；
/// - Hero（UI-P2-2）：tag 默认是 `series-<id>`，系列详情页头部用同一个 tag。
///   墨水屏关掉 Hero——灰阶屏上的共享元素只会变成一层拖影；
/// - 同一页面上同一个系列可能出现多次（"正在读"页的多条货架），这时调用方要传
///   [heroTag]（见 `seriesHeroTag`），否则飞行起点/终点会是另一份的位置；
/// - 长按弹上下文菜单：整系列标记已读/未读、查看详情。
class SeriesShelfTile extends ConsumerWidget {
  const SeriesShelfTile({
    required this.series,
    this.onTap,
    this.heroTag,
    super.key,
  });

  final Series series;
  final VoidCallback? onTap;

  /// 这张卡片的 Hero tag；null = 默认 `series-<id>`（页面上只有一份时）。
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

    final tile = SeriesTile(
      key: Key('series-${series.id}'),
      series: series,
      // 整张卡片是一个按钮：读屏只念这一句，不把封面首字/角标/标题分开念。
      semanticsLabel:
          '${series.title}, '
          '${l10n.readOfTotal(series.booksReadCount, series.booksCount)}',
      onTap: onTap,
      onLongPress: () =>
          unawaited(showSeriesMenu(context, ref, series, heroTag: tag)),
      cover: bytes == null || bytes.isEmpty ? null : CoverImage(bytes: bytes),
    );

    if (AppTheme.isEink(Theme.of(context))) return tile;
    // Hero 飞行时子组件会被放进 Overlay，而 Overlay 里**没有 Material 祖先**；
    // `SeriesTile` 内部有 InkWell（debug 会断言 "No Material widget found"，
    // 表现是退出时红一下）。透明 Material 只补祖先、不画任何东西。
    return Hero(
      tag: tag,
      child: Material(type: MaterialType.transparency, child: tile),
    );
  }
}

/// 列表视图里的一行（UI-P2-7）：封面 + 标题 + 进度，长按菜单与网格卡片一致。
///
/// 与 [SeriesShelfTile] 共用 `_SeriesMenu` 的逻辑，只是排版不同：
/// 列表适合"书名长、系列多"的书库，扫读比网格快。
class SeriesShelfRow extends ConsumerWidget {
  const SeriesShelfRow({
    required this.series,
    required this.coverSize,
    this.onTap,
    this.heroTag,
    super.key,
  });

  final Series series;
  final ShelfCoverSize coverSize;
  final VoidCallback? onTap;

  /// 这张行的 Hero tag；null = 默认 `series-<id>`。
  final String? heroTag;

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

    final row = Semantics(
      container: true,
      button: onTap != null,
      label: '${series.title}, $progressLabel',
      onTap: onTap,
      child: ExcludeSemantics(
        child: PressableScale(
          child: InkWell(
            onTap: onTap,
            onLongPress: () =>
                unawaited(showSeriesMenu(context, ref, series, heroTag: tag)),
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
    // 同上：退出时的飞行层没有 Material 祖先，而这一行里有 InkWell。
    return Hero(
      tag: tag,
      child: Material(type: MaterialType.transparency, child: row),
    );
  }
}

/// 长按系列的上下文菜单（UI-P2-5），网格卡片与列表行共用。
///
/// [heroTag] 是这张卡片的 Hero tag：从"查看详情"进系列页时带过去，
/// 否则详情页会用默认 tag，与多份副本页面上的源卡片对不上。
Future<void> showSeriesMenu(
  BuildContext context,
  WidgetRef ref,
  Series series, {
  String? heroTag,
}) async {
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
      await context.push(
        '/series/${series.id}',
        extra: SeriesDetailArgs(heroTag: heroTag),
      );
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
