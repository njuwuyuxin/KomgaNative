import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_view_options.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:material_ui/material_ui.dart';

/// 书架网格的列宽自适应：按可用宽度塞尽可能多的列，而不是按断点写死列数。
///
/// 好处：手机 2 列、平板 5 列、墨水屏 4 列都是同一条规则算出来的，
/// 页面里不需要再判断"是不是平板"，窗口拉伸时密度也自然跟着变。
/// [size] 由用户选的封面档位决定（UI-P2-7）。
SliverGridDelegate shelfGridDelegate([
  ShelfCoverSize size = ShelfCoverSize.medium,
]) => SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: size.maxExtent,
  crossAxisSpacing: AppSpacing.md,
  mainAxisSpacing: AppSpacing.md,
  childAspectRatio: 0.6,
);

/// 底部状态：追加中 / 追加失败可重试 / 到底了。
class ShelfPagingFooter extends StatelessWidget {
  const ShelfPagingFooter({
    required this.state,
    required this.onRetry,
    super.key,
  });

  final ShelfState state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(
          child: SizedBox(
            width: AppSpacing.lg,
            height: AppSpacing.lg,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final failure = state.loadMoreFailure;
    if (failure != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Flexible(
              child: Text(
                failure.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              key: const Key('shelf-paging-retry'),
              onPressed: () => unawaited(onRetry()),
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    }

    if (!state.hasMore) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Center(
          child: Text(
            l10n.seriesCount(state.totalElements),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return const SizedBox(height: AppSpacing.md);
  }
}

/// 首屏加载时的骨架：微光扫过的色块（UI-P2-8）。
///
/// 墨水屏与"减少动态效果"下 [Shimmer] 自动退化成静态色块——
/// 灰阶屏上的微光只会变成一层拖影。
class ShelfSkeleton extends StatelessWidget {
  const ShelfSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: GridView.builder(
        key: const Key('shelf-skeleton'),
        padding: const EdgeInsets.all(AppSpacing.md),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: shelfGridDelegate(),
        // 两屏的量足够盖住首屏加载，多了纯属浪费。
        itemCount: 8,
        itemBuilder: (BuildContext context, int index) => const SkeletonBox(),
      ),
    );
  }
}

/// 库筛选条。只有一个库时不占空间（选了也等于没选）。
///
/// 玻璃分段控件而不是 `ChoiceChip`：Chip 的描边/水波纹是 Material 味，
/// 而且和标题栏、搜索框不是同一材质。库的个数不定，所以横向滚动、按内容排。
class LibraryFilterBar extends ConsumerWidget {
  const LibraryFilterBar({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final libraries = ref.watch(librariesProvider);
    final items = switch (libraries) {
      AsyncData<List<Library>>(:final value) => value,
      _ => const <Library>[],
    };
    if (items.length < 2) return const SizedBox.shrink();

    return Padding(
      key: const Key('library-filter'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: GlassSegmentedControl<String?>(
        scrollable: true,
        selected: selected,
        onSelected: onSelected,
        segments: <GlassSegment<String?>>[
          GlassSegment<String?>(value: null, label: l10n.all),
          for (final library in items)
            GlassSegment<String?>(value: library.id, label: library.name),
        ],
      ),
    );
  }
}
