import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/library_providers.dart';
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

class _CollectionsTab extends ConsumerWidget {
  const _CollectionsTab({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(collectionsProvider);
    if (async.hasError && !async.hasValue) {
      return _Error(
        topPadding: topPadding,
        message: async.error is ShelfFailure
            ? (async.error! as ShelfFailure).message
            : l10n.errorGeneric,
        onRetry: () => ref.invalidate(collectionsProvider),
      );
    }
    final value = async.value;
    if (value == null) {
      return _Loading(topPadding: topPadding);
    }
    if (value.items.isEmpty) {
      return _Empty(
        topPadding: topPadding,
        icon: Icons.collections_bookmark_outlined,
        text: l10n.collectionsEmpty,
      );
    }
    return RefreshIndicator(
      edgeOffset: topPadding,
      onRefresh: () async => ref.invalidate(collectionsProvider),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: topPadding + AppSpacing.xs,
          bottom: AppSizes.navBarClearance,
        ),
        children: <Widget>[
          AppListGroup(
            children: <Widget>[
              for (final collection in value.items)
                ListTile(
                  key: Key('collection-${collection.id}'),
                  leading: const Icon(Icons.collections_bookmark_outlined),
                  title: Text(collection.name),
                  subtitle: Text(l10n.seriesCount(collection.seriesCount)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    '/collections/${collection.id}',
                    extra: collection.name,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadListsTab extends ConsumerWidget {
  const _ReadListsTab({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(readListsProvider);
    if (async.hasError && !async.hasValue) {
      return _Error(
        topPadding: topPadding,
        message: async.error is ShelfFailure
            ? (async.error! as ShelfFailure).message
            : l10n.errorGeneric,
        onRetry: () => ref.invalidate(readListsProvider),
      );
    }
    final value = async.value;
    if (value == null) return _Loading(topPadding: topPadding);
    if (value.items.isEmpty) {
      return _Empty(
        topPadding: topPadding,
        icon: Icons.list_alt_outlined,
        text: l10n.readListsEmpty,
      );
    }
    return RefreshIndicator(
      edgeOffset: topPadding,
      onRefresh: () async => ref.invalidate(readListsProvider),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: topPadding + AppSpacing.xs,
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
