import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:material_ui/material_ui.dart';

/// 搜索页的空态（SCH-01）。
///
/// 以前这里只有一行"输入关键字搜索"——等于什么都没有。现在：
/// 有历史 → 最近搜索（点一下回填，右侧 ✕ 删单条，右上角清空）；
/// 没历史 → 用"正在读"的系列名给出可点的引导，别让用户对着空白页发呆。
///
/// 注意外层是 sliver：这里只返回普通 Column，滚动交给整页
/// （用 ListView 套进 `SliverFillRemaining` 会触发 viewport 的 intrinsic 断言）。
class SearchEmptyState extends ConsumerWidget {
  const SearchEmptyState({
    required this.history,
    required this.onPick,
    required this.onRemove,
    required this.onClear,
    super.key,
  });

  final List<String> history;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (history.isEmpty) return _Guidance(onPick: onPick);

    return Column(
      key: const Key('search-history'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.searchRecent,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              TextButton(
                key: const Key('search-history-clear'),
                onPressed: onClear,
                child: Text(l10n.searchHistoryClear),
              ),
            ],
          ),
        ),
        for (final term in history)
          ListTile(
            key: Key('search-history-$term'),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
            ),
            leading: Icon(
              Icons.history,
              size: AppSizes.iconSm,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(term, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              key: Key('search-history-remove-$term'),
              tooltip: l10n.remove,
              icon: const Icon(Icons.close, size: AppSizes.iconSm),
              onPressed: () => onRemove(term),
            ),
            onTap: () => onPick(term),
          ),
      ],
    );
  }
}

/// 没有任何历史时的引导：拿"正在读"的系列名当搜索建议。
///
/// 为什么用正在读而不是"热门标签"：标签来自服务端聚合、当前没有可靠的
/// "热门"接口（按 API 真值规则不编），而"正在读"是本地已有且一定相关的东西。
class _Guidance extends ConsumerWidget {
  const _Guidance({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final page = ref.watch(ondeckProvider).value;
    final ondeck = page?.items ?? const <Book>[];

    // 用系列名去重（同一系列的几本书只要一条建议）。
    final titles = <String>{
      for (final book in ondeck)
        if (book.seriesTitle?.trim().isNotEmpty ?? false)
          book.seriesTitle!.trim(),
    }.take(5).toList();

    return Padding(
      key: const Key('search-guidance'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.md,
        AppSizes.navBarClearance,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.search,
            size: AppSpacing.xxl,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.searchEmptyTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.searchEmptyHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (titles.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.searchTryThese,
                style: theme.textTheme.labelLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                for (final title in titles)
                  GlassPillButton(
                    key: Key('search-suggestion-$title'),
                    label: title,
                    onPressed: () => onPick(title),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
