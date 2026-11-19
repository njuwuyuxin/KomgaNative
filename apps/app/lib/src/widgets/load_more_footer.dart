import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// 列表被截断时的页脚："已显示 x / 共 y 条" + 可选"加载更多"。
///
/// 用同一个组件而不是每页各写一份：以前收藏集/阅读列表/搜索都直接取 20 条，
/// 第 21 条起静默消失，用户根本不知道还有更多（FIX-08）。
///
/// 没给 [onLoadMore] 时只显示说明文字：有些列表（搜索结果里的一屏）不打算
/// 无限加载，但至少要让用户知道被截断了。
class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({
    required this.loaded,
    required this.total,
    this.onLoadMore,
    this.unit = LoadMoreUnit.items,
    super.key,
  });

  final int loaded;
  final int total;
  final VoidCallback? onLoadMore;
  final LoadMoreUnit unit;

  @override
  Widget build(BuildContext context) {
    if (loaded >= total) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final label = switch (unit) {
      LoadMoreUnit.items => l10n.showingItems(loaded, total),
      LoadMoreUnit.books => l10n.showingBooks(loaded, total),
      LoadMoreUnit.series => l10n.showingSeries(loaded, total),
    };
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: onLoadMore == null
          ? Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Center(
              child: OutlinedButton.icon(
                key: const Key('load-more'),
                onPressed: onLoadMore,
                icon: const Icon(Icons.expand_more),
                label: Text(label),
              ),
            ),
    );
  }
}

/// 页脚文案里的单位。
enum LoadMoreUnit { items, books, series }
