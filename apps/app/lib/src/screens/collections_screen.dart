import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/widgets/collection_covers.dart';
import 'package:komga_native/src/widgets/load_more_footer.dart';
import 'package:material_ui/material_ui.dart';

/// 收藏集 / 阅读列表入口（UI-P3-8）。
///
/// 两个 tab 共用一条列表：收藏集进系列网格，阅读列表进书列表。
/// 数据都来自 Komga 服务端策展，不在本地另存一份。
///
/// 顶部是一条玻璃标题栏：左边返回圆球、中间分段控件（收藏集 / 阅读列表）。
/// 列表铺到屏幕顶、从玻璃下面穿过，所以内容自己留出 `glassHeaderClearance`。
class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({super.key});

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final topInset =
        MediaQuery.paddingOf(context).top + AppSizes.glassHeaderClearance;

    return Scaffold(
      body: GlassPageBackground(
        child: Stack(
          children: <Widget>[
            TabBarView(
              controller: _tab,
              children: <Widget>[
                _CollectionsTab(topPadding: topInset),
                _ReadListsTab(topPadding: topInset),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: GlassHeader(
                    bar: AnimatedBuilder(
                      animation: _tab,
                      builder: (BuildContext context, _) =>
                          GlassSegmentedControl<int>(
                            segments: <GlassSegment<int>>[
                              GlassSegment<int>(
                                value: 0,
                                label: l10n.collectionsTab,
                              ),
                              GlassSegment<int>(
                                value: 1,
                                label: l10n.readListsTab,
                              ),
                            ],
                            selected: _tab.index,
                            onSelected: _tab.animateTo,
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionsTab extends ConsumerStatefulWidget {
  const _CollectionsTab({required this.topPadding});

  final double topPadding;

  @override
  ConsumerState<_CollectionsTab> createState() => _CollectionsTabState();
}

/// 收藏集列表的排序方式（UI-02）：都在本地排。
enum CollectionSort { name, seriesCount, recent }

class _CollectionsTabState extends ConsumerState<_CollectionsTab> {
  /// 已请求的条数；点"加载更多"加一页（FIX-08）。
  int _size = kListPageSize;

  String _query = '';
  CollectionSort _sort = CollectionSort.name;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = collectionsProvider(_size);
    final async = ref.watch(provider);
    if (async.hasError && !async.hasValue) {
      return _Error(
        topPadding: widget.topPadding,
        message: async.error is ShelfFailure
            ? (async.error! as ShelfFailure).message
            : l10n.errorGeneric,
        onRetry: () => ref.invalidate(provider),
      );
    }
    final value = async.value;
    if (value == null) {
      return _Loading(topPadding: widget.topPadding);
    }
    if (value.items.isEmpty) {
      return _Empty(
        topPadding: widget.topPadding,
        icon: Icons.collections_bookmark_outlined,
        text: l10n.collectionsEmpty,
      );
    }
    final query = _query.trim().toLowerCase();
    final visible =
        <KomgaCollection>[
          for (final collection in value.items)
            if (query.isEmpty || collection.name.toLowerCase().contains(query))
              collection,
        ]..sort((KomgaCollection a, KomgaCollection b) {
          switch (_sort) {
            case CollectionSort.name:
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            case CollectionSort.seriesCount:
              return b.seriesCount.compareTo(a.seriesCount);
            case CollectionSort.recent:
              final left = a.lastModifiedDate ?? a.createdDate;
              final right = b.lastModifiedDate ?? b.createdDate;
              if (left == null && right == null) return 0;
              if (left == null) return 1;
              if (right == null) return -1;
              return right.compareTo(left);
          }
        });
    return Column(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(
            top: widget.topPadding + AppSpacing.xs,
            left: AppSpacing.md,
            right: AppSpacing.md,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('collections-search'),
                  onChanged: (String value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: l10n.searchCollectionsHint,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                key: const Key('collections-sort'),
                tooltip: l10n.sort,
                onPressed: () => unawaited(_pickSort(context, l10n)),
                icon: const Icon(Icons.sort),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            edgeOffset: widget.topPadding,
            onRefresh: () async => ref.invalidate(provider),
            child: visible.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: <Widget>[
                      SizedBox(height: widget.topPadding),
                      _Empty(
                        topPadding: 0,
                        icon: Icons.search_off,
                        text: l10n.noMatches,
                      ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(
                      top: AppSpacing.xs,
                      bottom: AppSizes.navBarClearance,
                    ),
                    children: <Widget>[
                      AppListGroup(
                        children: <Widget>[
                          for (final collection in visible)
                            ListTile(
                              key: Key('collection-${collection.id}'),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                              ),
                              leading: CollectionCovers(
                                collectionId: collection.id,
                                name: collection.name,
                                seriesIds: collection.seriesIds,
                              ),
                              title: Text(collection.name),
                              subtitle: Text(
                                l10n.seriesCount(collection.seriesCount),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push(
                                '/collections/${collection.id}',
                                extra: collection.name,
                              ),
                            ),
                        ],
                      ),
                      LoadMoreFooter(
                        loaded: value.items.length,
                        total: value.totalElements,
                        onLoadMore: () =>
                            setState(() => _size += kListPageSize),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  /// 搜索/排序菜单（UI-02）：本地对已加载的收藏集排序。
  ///
  /// 不调服务端排序：收藏集的"系列数""最近修改"都不在服务端排序字段里，
  /// 与其发一个被静默忽略的参数，不如在本地排得明明白白。
  Future<void> _pickSort(BuildContext context, AppLocalizations l10n) async {
    final picked = await showModalBottomSheet<CollectionSort>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final option in CollectionSort.values)
              ListTile(
                key: Key('collections-sort-${option.name}'),
                title: Text(_sortLabel(l10n, option)),
                leading: Icon(
                  option == _sort
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                onTap: () => Navigator.of(context).pop(option),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  String _sortLabel(AppLocalizations l10n, CollectionSort option) =>
      switch (option) {
        CollectionSort.name => l10n.sortName,
        CollectionSort.seriesCount => l10n.sortSeriesCount,
        CollectionSort.recent => l10n.sortRecent,
      };
}

class _ReadListsTab extends ConsumerStatefulWidget {
  const _ReadListsTab({required this.topPadding});

  final double topPadding;

  @override
  ConsumerState<_ReadListsTab> createState() => _ReadListsTabState();
}

class _ReadListsTabState extends ConsumerState<_ReadListsTab> {
  int _size = kListPageSize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = readListsProvider(_size);
    final async = ref.watch(provider);
    if (async.hasError && !async.hasValue) {
      return _Error(
        topPadding: widget.topPadding,
        message: async.error is ShelfFailure
            ? (async.error! as ShelfFailure).message
            : l10n.errorGeneric,
        onRetry: () => ref.invalidate(provider),
      );
    }
    final value = async.value;
    if (value == null) return _Loading(topPadding: widget.topPadding);
    if (value.items.isEmpty) {
      return _Empty(
        topPadding: widget.topPadding,
        icon: Icons.list_alt_outlined,
        text: l10n.readListsEmpty,
      );
    }
    return RefreshIndicator(
      edgeOffset: widget.topPadding,
      onRefresh: () async => ref.invalidate(provider),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: widget.topPadding + AppSpacing.xs,
          bottom: AppSizes.navBarClearance,
        ),
        children: <Widget>[
          AppListGroup(
            children: <Widget>[
              for (final list in value.items)
                ListTile(
                  key: Key('readlist-${list.id}'),
                  leading: const Icon(Icons.list_alt_outlined),
                  title: Text(list.name),
                  subtitle: Text(
                    list.summary.isEmpty
                        ? l10n.bookCount(list.bookCount)
                        : '${l10n.bookCount(list.bookCount)} · ${list.summary}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      context.push('/readlists/${list.id}', extra: list.name),
                ),
            ],
          ),
          LoadMoreFooter(
            loaded: value.items.length,
            total: value.totalElements,
            onLoadMore: () => setState(() => _size += kListPageSize),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({
    required this.topPadding,
    required this.message,
    required this.onRetry,
  });

  final double topPadding;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              GlassPillButton(
                label: l10n.retry,
                icon: Icons.refresh,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.topPadding,
    required this.icon,
    required this.text,
  });

  final double topPadding;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: AppSizes.iconLg,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(text, style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}
