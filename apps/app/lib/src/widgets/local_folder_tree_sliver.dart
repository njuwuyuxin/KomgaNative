import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/providers/local_folder_tree_provider.dart';
import 'package:yomu/src/screens/reader_args.dart';
import 'package:yomu_design_system/yomu_design_system.dart';

/// 本地书架「按文件夹树浏览」Sliver 视图（LMB-10）。
class LocalFolderTreeSliver extends ConsumerWidget {
  const LocalFolderTreeSliver({this.query = '', super.key});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final treeAsync = ref.watch(
      localFolderTreeProvider(l10n.folderTreeImportedGroup),
    );
    final breadcrumb = ref.watch(localFolderBreadcrumbProvider);
    final crumbCtrl = ref.read(localFolderBreadcrumbProvider.notifier);

    final root = treeAsync.value;
    if (root == null) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final resolved = resolveFolderNode(root, breadcrumb);
    final node = resolved.node;
    final cleanQuery = query.trim().toLowerCase();

    final visibleFolders = cleanQuery.isEmpty
        ? node.subfolders
        : node.subfolders
              .where((f) => f.name.toLowerCase().contains(cleanQuery))
              .toList(growable: false);
    final visibleBooks = cleanQuery.isEmpty
        ? node.books
        : node.books
              .where((b) => b.book.name.toLowerCase().contains(cleanQuery))
              .toList(growable: false);

    return SliverList.list(
      children: <Widget>[
        _BreadcrumbBar(
          segments: resolved.resolvedPath,
          rootLabel: l10n.folderTreeRoot,
          onSelectDepth: crumbCtrl.popTo,
        ),
        if (visibleFolders.isEmpty && visibleBooks.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Center(
              child: Text(
                cleanQuery.isEmpty ? l10n.noBooksYet : l10n.noMatches,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          AppListGroup(
            key: const Key('local-folder-tree-list'),
            children: <Widget>[
              for (final folder in visibleFolders)
                ListTile(
                  key: Key('folder-node-${folder.path}'),
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    l10n.folderTreeBookCount(folder.totalBooksCount),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => crumbCtrl.enter(folder.name),
                ),
              for (final item in visibleBooks) _FolderBookTile(item: item),
            ],
          ),
      ],
    );
  }
}

class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar({
    required this.segments,
    required this.rootLabel,
    required this.onSelectDepth,
  });

  final List<String> segments;
  final String rootLabel;
  final void Function(int depth) onSelectDepth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      key: const Key('folder-tree-breadcrumbs'),
      height: AppSizes.minTouch,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: <Widget>[
          ActionChip(
            key: const Key('folder-crumb-root'),
            avatar: const Icon(Icons.home_outlined, size: AppSizes.iconXs),
            label: Text(rootLabel),
            onPressed: segments.isEmpty ? null : () => onSelectDepth(0),
          ),
          for (var i = 0; i < segments.length; i++) ...<Widget>[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                child: Icon(
                  Icons.chevron_right,
                  size: AppSizes.iconSm,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ActionChip(
              key: Key('folder-crumb-$i'),
              label: Text(segments[i]),
              onPressed: i == segments.length - 1
                  ? null
                  : () => onSelectDepth(i + 1),
            ),
          ],
        ],
      ),
    );
  }
}

class _FolderBookTile extends StatelessWidget {
  const _FolderBookTile({required this.item});

  final LocalFolderBookItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = item.book;
    final progress = book.readProgress;
    final subtitle = item.isCloudPlaceholder
        ? l10n.folderTreeCloudPlaceholder
        : progress == null
        ? l10n.bookPages(book.pagesCount)
        : book.isCompleted
        ? l10n.bookReadPages(book.pagesCount)
        : l10n.bookPageProgress(progress.page, book.pagesCount);

    return ListTile(
      key: Key('folder-book-${book.id}'),
      leading: Icon(
        item.isCloudPlaceholder
            ? Icons.cloud_download_outlined
            : Icons.menu_book_outlined,
      ),
      title: Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: book.isCompleted
          ? const Icon(Icons.check_circle_outline, size: AppSizes.iconMd)
          : const Icon(Icons.chevron_right),
      onTap: () {
        if (GoRouter.maybeOf(context) != null) {
          unawaited(
            context.push(
              '/reader/${book.id}',
              extra: ReaderArgs(book: book, direction: item.direction),
            ),
          );
        }
      },
    );
  }
}
