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
class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.collectionsTitle),
          bottom: TabBar(
            tabs: <Widget>[
              Tab(text: l10n.collectionsTab),
              Tab(text: l10n.readListsTab),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[_CollectionsTab(), _ReadListsTab()],
        ),
      ),
    );
  }
}

class _CollectionsTab extends ConsumerWidget {
  const _CollectionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(collectionsProvider);
    if (async.hasError && !async.hasValue) {
      return _Error(
        message: async.error is ShelfFailure
            ? (async.error! as ShelfFailure).message
            : l10n.errorGeneric,
        onRetry: () => ref.invalidate(collectionsProvider),
      );
    }
    final value = async.value;
    if (value == null) return const Center(child: CircularProgressIndicator());
    if (value.items.isEmpty) {
      return _Empty(
        icon: Icons.collections_bookmark_outlined,
        text: l10n.collectionsEmpty,
      );
    }
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(collectionsProvider),
      child: ListView.separated(
        itemCount: value.items.length,
        separatorBuilder: (_, _) => const Divider(height: AppSizes.hairline),
        itemBuilder: (BuildContext context, int index) {
          final collection = value.items[index];
          return ListTile(
            key: Key('collection-${collection.id}'),
            leading: const Icon(Icons.collections_bookmark_outlined),
            title: Text(collection.name),
            subtitle: Text(l10n.seriesCount(collection.seriesCount)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(
              '/collections/${collection.id}',
              extra: collection.name,
            ),
          );
        },
      ),
    );
  }
}

class _ReadListsTab extends ConsumerWidget {
  const _ReadListsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(readListsProvider);
    if (async.hasError && !async.hasValue) {
      return _Error(
        message: async.error is ShelfFailure
            ? (async.error! as ShelfFailure).message
            : l10n.errorGeneric,
        onRetry: () => ref.invalidate(readListsProvider),
      );
    }
    final value = async.value;
    if (value == null) return const Center(child: CircularProgressIndicator());
    if (value.items.isEmpty) {
      return _Empty(icon: Icons.list_alt_outlined, text: l10n.readListsEmpty);
    }
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(readListsProvider),
      child: ListView.separated(
        itemCount: value.items.length,
        separatorBuilder: (_, _) => const Divider(height: AppSizes.hairline),
        itemBuilder: (BuildContext context, int index) {
          final list = value.items[index];
          return ListTile(
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
          );
        },
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
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
    );
  }
}
