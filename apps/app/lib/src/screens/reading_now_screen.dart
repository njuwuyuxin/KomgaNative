import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/reader_screen.dart';
import 'package:komga_native/src/screens/series_detail_args.dart';
import 'package:komga_native/src/widgets/book_hero_tag.dart';
import 'package:komga_native/src/widgets/cover_image.dart';
import 'package:komga_native/src/widgets/series_hero_tag.dart';
import 'package:komga_native/src/widgets/series_shelf_tile.dart';
import 'package:material_ui/material_ui.dart';

/// "正在读"首页（UI-P2-6）。
///
/// 三块内容，从上到下：
/// 1. **大号继续阅读卡片**：Komga 的 ondeck 第一本（"上次看到哪"）；
/// 2. **最近添加**：按 `createdDate,desc` 的系列横向货架；
/// 3. **按库分组**：每个库一条横向货架。
///
/// 为什么是系列而不是书：`/api/v1/series?sort=createdDate,desc` 是验证过的端点，
/// "按添加时间列书"的那个没有 fixture（见 `docs/series-queries.md`），不猜。
///
/// 空/失败都**不占位**：这一页是"锦上添花"的入口，断网时应该只看到书架入口
/// 还能用，而不是整页报错。
class ReadingNowScreen extends ConsumerWidget {
  const ReadingNowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ondeck = ref.watch(ondeckProvider).value?.items ?? const <Book>[];
    final libraries = ref.watch(librariesProvider).value ?? const <Library>[];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(ondeckProvider);
          ref.invalidate(recentSeriesProvider);
          for (final library in libraries) {
            ref.invalidate(libraryShelfProvider(library.id));
          }
        },
        child: CustomScrollView(
          key: const Key('reading-now-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverAppBar.large(title: Text(l10n.readingNow)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: ondeck.isEmpty
                    ? const _EmptyContinueCard()
                    : _ContinueCard(book: ondeck.first),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                child: Text(
                  l10n.recentlyAdded,
                  style: AppTypography.of(context).title,
                ),
              ),
            ),
            _SeriesShelf(
              key: const Key('reading-now-recent'),
              heroScope: 'reading-now-recent',
              series: ref.watch(recentSeriesProvider).value ?? const <Series>[],
            ),
            for (final library in libraries) ...<Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.xs,
                  ),
                  child: Text(
                    library.name,
                    style: AppTypography.of(context).title,
                  ),
                ),
              ),
              _SeriesShelf(
                key: Key('reading-now-library-${library.id}'),
                heroScope: 'reading-now-library-${library.id}',
                series:
                    ref.watch(libraryShelfProvider(library.id)).value ??
                    const <Series>[],
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
          ],
        ),
      ),
    );
  }
}

/// 继续阅读的大卡片：封面 + 书名 + 进度 + 主按钮。
class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final Uint8List? bytes = ref.watch(bookCoverProvider(book.id)).value;
    // 阅读方向存在系列元数据里，不在书上；这里多一次按系列的查询（有 family 缓存）。
    // 不查的话，日漫从"正在读"进来会按 LTR 打开（老"继续阅读"行就有这一步）。
    final direction =
        ref
            .watch(seriesDetailProvider(book.seriesId))
            .value
            ?.readingDirection ??
        ReadingDirection.unknown;
    final progress = book.readProgress;
    final label = progress == null
        ? l10n.bookPages(book.pagesCount)
        : l10n.continueReadingProgress(progress.page, book.pagesCount);
    final shape = AppShapes.of(context, AppShapes.card);
    // 墨水屏 / 减少动态效果不做 Hero；其余情况把 tag 一路带到阅读器开场。
    final heroTag =
        AppTheme.isEink(theme) ||
            (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
        ? null
        : bookHeroTag(book.id);
    final cover = ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: SizedBox(
        width: AppSizes.shelfCover.width,
        height: AppSizes.shelfCover.height,
        child: bytes == null
            ? const ColoredBox(color: Colors.black12)
            : CoverImage(bytes: bytes),
      ),
    );

    return Semantics(
      key: const Key('reading-now-continue'),
      container: true,
      button: true,
      // 整张卡片是一个按钮：读屏只念"书名 + 进度"，不逐条念封面/标签/页码。
      label: '${book.name}, $label',
      onTap: () => unawaited(_open(context, book, direction, heroTag)),
      child: ExcludeSemantics(
        child: PressableScale(
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.md),
            onTap: () => unawaited(_open(context, book, direction, heroTag)),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: shape,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: <Widget>[
                    heroTag == null ? cover : Hero(tag: heroTag, child: cover),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            l10n.pickUpWhereYouLeftOff,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            book.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.of(context).headline,
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          FilledButton(
                            onPressed: () => unawaited(
                              _open(context, book, direction, heroTag),
                            ),
                            child: Text(l10n.continueReading),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    Book book,
    ReadingDirection direction,
    String? heroTag,
  ) async {
    await context.push(
      '/reader/${book.id}',
      extra: ReaderArgs(book: book, direction: direction, heroTag: heroTag),
    );
  }
}

/// 没有在读的书：给一句说明，不摆一个大空壳。
class _EmptyContinueCard extends StatelessWidget {
  const _EmptyContinueCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: StatusView(
        key: const Key('reading-now-empty'),
        icon: Icons.auto_stories_outlined,
        title: l10n.readingNowEmpty,
        message: l10n.readingNowEmptyHint,
      ),
    );
  }
}

/// 一条横向货架：系列卡片。
///
/// [heroScope] 区分同一页面上同一个系列的多份副本（"最近添加"与按库货架会重叠）。
/// 每条货架一个 scope，详情页通过 `SeriesDetailArgs` 记住被点的那一份，
/// 封面才会从手指下的卡片飞出去、退出时也飞回同一张。
class _SeriesShelf extends StatelessWidget {
  const _SeriesShelf({
    required this.series,
    required this.heroScope,
    super.key,
  });

  final List<Series> series;
  final String heroScope;

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty)
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: SizedBox(
        height: AppSizes.shelfRowHeight + AppSpacing.md,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          itemCount: series.length,
          separatorBuilder: (BuildContext context, int index) =>
              const SizedBox(width: AppSpacing.sm),
          itemBuilder: (BuildContext context, int index) {
            final item = series[index];
            final heroTag = seriesHeroTag(item.id, scope: heroScope);
            return SizedBox(
              width: AppSizes.shelfCover.width + AppSpacing.xl,
              child: SeriesShelfTile(
                series: item,
                heroTag: heroTag,
                onTap: () => unawaited(
                  context.push(
                    '/series/${item.id}',
                    extra: SeriesDetailArgs(heroTag: heroTag),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
