import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/reader_screen.dart';
import 'package:komga_native/src/widgets/book_hero_tag.dart';
import 'package:komga_native/src/widgets/cover_image.dart';
import 'package:material_ui/material_ui.dart';

/// "正在读"页顶部的继续阅读卡片，以及它的加载/空/失败三态（FIX-05）。
///
/// 为什么单独拆出来：这一屏的继续卡、横向货架、按库货架是**三个独立的请求**，
/// 各自都可能先失败、后成功。把它们的三态集中在一处，页面本身只做编排，
/// 也就不会出现"加载中先渲染一个空卡片、数据回来再跳一下"的闪烁。
///
/// 三态规则（与书架一致）：
/// - 没有数据、没报错 → 骨架，**绝不**先画空态；
/// - 有数据 → 正常内容；此时若同时在刷新失败，只在下面补一条小提示，不清空；
/// - 没数据且报错（首次加载失败）→ 错误态 + 重试。
class ReadingNowContinue extends StatefulWidget {
  const ReadingNowContinue({
    required this.books,
    required this.hasError,
    required this.onRetry,
    super.key,
  });

  /// 在读过、还没读完的书；null = 还没有可用结果（加载中或已失败）。
  ///
  /// 刻意收成"列表 + 错误位"两个参数而不是 `AsyncValue`：`whenData` 会把
  /// 加载态携带的错误丢掉（Riverpod 3 首次失败是 `AsyncLoading` + `hasError`），
  /// 界面读 `hasError` 才是可靠的那一个。
  final List<Book>? books;

  /// 最近一次请求是否失败（即使还留着上一次的结果）。
  final bool hasError;

  final Future<void> Function() onRetry;

  @override
  State<ReadingNowContinue> createState() => _ReadingNowContinueState();
}

class _ReadingNowContinueState extends State<ReadingNowContinue> {
  /// 上一次拿到的**有效**结果。
  ///
  /// Riverpod 在 `invalidate` 之后会把旧值丢掉（刷新失败时 `AsyncError.value` 为空），
  /// 光看 `AsyncValue` 就会出现"刷新一次失败，卡片整张消失"。这里自己记一份，
  /// 只有真的拿到新结果才替换。
  List<Book>? _lastGood;

  @override
  Widget build(BuildContext context) {
    final fresh = widget.books;
    if (fresh != null) _lastGood = fresh;
    final items = fresh ?? _lastGood;
    if (items != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (items.isEmpty)
            const EmptyContinueCard()
          else
            ContinueCard(book: items.first),
          // 刷新失败但还有旧内容：保留卡片，只在下面提示一次。
          if (widget.hasError)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: RefreshFailureHint(onRetry: widget.onRetry),
            ),
        ],
      );
    }
    if (widget.hasError) {
      return ContinueFailure(onRetry: widget.onRetry);
    }
    return const ContinueSkeleton();
  }
}

/// 继续阅读的大卡片：封面 + 书名 + 进度 + 主按钮。
class ContinueCard extends ConsumerWidget {
  const ContinueCard({required this.book, super.key});

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
    final seriesTitle = book.seriesTitle;
    // 第一行是系列名（"Vol. 1" 单独出现没有信息量）；没有系列名时退回书名。
    final headline = seriesTitle ?? book.name;
    final progressLabel = progress == null
        ? l10n.bookPages(book.pagesCount)
        : l10n.bookPageProgress(progress.page, book.pagesCount);
    final detail = seriesTitle == null
        ? progressLabel
        : '${book.name} · $progressLabel';
    final shape = AppShapes.of(context, AppShapes.panel);
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
      label: '$headline, $detail',
      onTap: () => unawaited(_open(context, book, direction, heroTag)),
      child: ExcludeSemantics(
        child: PressableScale(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_open(context, book, direction, heroTag)),
            child: GlassSurface(
              shape: shape,
              shadows: AppShadows.card,
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
                            headline,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.of(context).headline,
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          GlassPillButton(
                            icon: Icons.play_arrow,
                            label: l10n.continueReading,
                            onPressed: () => unawaited(
                              _open(context, book, direction, heroTag),
                            ),
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
class EmptyContinueCard extends StatelessWidget {
  const EmptyContinueCard({super.key});

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

/// 继续卡骨架：与真卡片同尺寸，数据回来时不会跳版。
class ContinueSkeleton extends StatelessWidget {
  const ContinueSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: GlassSurface(
        key: const Key('reading-now-continue-skeleton'),
        shape: AppShapes.of(context, AppShapes.panel),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: AppSizes.shelfCover.width,
                height: AppSizes.shelfCover.height,
                child: const SkeletonBox(),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _SkeletonLine(
                      widthFactor: 0.45,
                      height: AppSizes.skeletonLineSm,
                    ),
                    SizedBox(height: AppSpacing.sm),
                    _SkeletonLine(widthFactor: 0.9),
                    SizedBox(height: AppSpacing.sm),
                    _SkeletonLine(
                      widthFactor: 0.7,
                      height: AppSizes.skeletonLineSm,
                    ),
                    SizedBox(height: AppSpacing.md),
                    _SkeletonLine(
                      widthFactor: 0.5,
                      height: AppSizes.skeletonLineLg,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 首次加载失败：给一句能看懂的话 + 重试，不假装"没有在读的书"。
class ContinueFailure extends StatelessWidget {
  const ContinueFailure({required this.onRetry, super.key});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: StatusView(
        key: const Key('reading-now-error'),
        icon: Icons.cloud_off_outlined,
        title: l10n.readingNowLoadFailed,
        message: l10n.readingNowLoadFailedHint,
        actionLabel: l10n.retry,
        onAction: () => unawaited(onRetry()),
      ),
    );
  }
}

/// 有旧内容、但这次刷新失败：一行小提示，不占整屏。
class RefreshFailureHint extends StatelessWidget {
  const RefreshFailureHint({required this.onRetry, super.key});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      key: const Key('reading-now-refresh-failed'),
      children: <Widget>[
        Icon(
          Icons.cloud_off_outlined,
          size: AppSizes.iconSm,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            l10n.readingNowRefreshFailed,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          onPressed: () => unawaited(onRetry()),
          child: Text(l10n.retry),
        ),
      ],
    );
  }
}

/// 一条横向货架的骨架：三张封面大小的色块。
class ShelfRowSkeleton extends StatelessWidget {
  const ShelfRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: SizedBox(
        key: const Key('reading-now-shelf-skeleton'),
        height: AppSizes.shelfRowHeight + AppSpacing.md,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          itemCount: 3,
          separatorBuilder: (BuildContext context, int index) =>
              const SizedBox(width: AppSpacing.sm),
          itemBuilder: (BuildContext context, int index) => SizedBox(
            width: AppSizes.shelfCover.width + AppSpacing.xl,
            child: const SkeletonBox(),
          ),
        ),
      ),
    );
  }
}

/// 骨架里的一条"文字"：宽度按可用宽度的比例给，换屏幕不用改数值。
class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({
    required this.widthFactor,
    this.height = AppSizes.skeletonLineLg,
  });

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: SizedBox(height: height, child: const SkeletonBox()),
    );
  }
}
