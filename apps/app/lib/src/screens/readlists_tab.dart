import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/l10n/failure_text.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/collections_screen.dart';
import 'package:komga_native/src/widgets/load_more_footer.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读列表标签页（ARC-12 增量分页 + 拆分独立文件）。
class ReadListsTab extends ConsumerWidget {
  const ReadListsTab({required this.topPadding, super.key});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(readListsProvider);
    if (async.hasError && !async.hasValue) {
      return CollectionsTabError(
        topPadding: topPadding,
        message: l10n.failureTitle(failureKindOf(async.error)),
        onRetry: () => ref.invalidate(readListsProvider),
      );
    }
    final value = async.value;
    if (value == null) return CollectionsTabLoading(topPadding: topPadding);
    if (value.items.isEmpty) {
      return CollectionsTabEmpty(
        topPadding: topPadding,
        icon: Icons.list_alt_outlined,
        text: l10n.readListsEmpty,
      );
    }
    return RefreshIndicator(
      edgeOffset: topPadding,
      onRefresh: () async {
        ref.invalidate(readListsProvider);
        await ref.read(readListsProvider.future);
      },
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
          LoadMoreFooter(
            loaded: value.items.length,
            total: value.totalElements,
            onLoadMore: () =>
                unawaited(ref.read(readListsProvider.notifier).loadMore()),
          ),
        ],
      ),
    );
  }
}
