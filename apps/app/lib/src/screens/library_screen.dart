import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/reader_screen.dart';
import 'package:komga_native/src/session/session_controller.dart';
import 'package:komga_native/src/widgets/continue_reading_row.dart';
import 'package:komga_native/src/widgets/offline_banner.dart';
import 'package:komga_native/src/widgets/shelf_query_buttons.dart';
import 'package:komga_native/src/widgets/shelf_views.dart';
import 'package:material_ui/material_ui.dart';

/// 书架页：真实 `/api/v1/series` 数据 + 封面 + 分页 + 搜索 + 按库筛选。
///
/// 状态机在 [ShelfController] 里，这一层只负责把状态画出来并派发意图；
/// 具体视图组件在 `widgets/shelf_views.dart`（拆开是为了守住单文件行数上限）。
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() => _searching = !_searching);
    if (!_searching) {
      _searchController.clear();
      ref.read(shelfProvider.notifier).search('');
    }
  }

  Future<void> _openFromContinueRow(
    Book book,
    ReadingDirection direction,
  ) async {
    await context.push(
      '/reader/${book.id}',
      extra: ReaderArgs(book: book, direction: direction),
    );
    // 回来时进度变了：让"继续阅读"重新按 ondeck 排序（读完的书会消失）。
    ref.invalidate(ondeckProvider);
    unawaited(ref.read(shelfProvider.notifier).refreshInPlace());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(shelfProvider);
    final controller = ref.read(shelfProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.libraryTitle),
        actions: <Widget>[
          const ShelfSortButton(),
          const ShelfFilterButton(),
          IconButton(
            onPressed: _toggleSearch,
            icon: Icon(_searching ? Icons.close : Icons.search),
            tooltip: _searching ? l10n.closeSearch : l10n.search,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 断网时提示"看的是缓存"，并给一次重新联网的机会。
          OfflineBanner(onRetry: () => unawaited(controller.refresh())),
          ContinueReadingRow(
            onOpen: (Book book, ReadingDirection direction) =>
                unawaited(_openFromContinueRow(book, direction)),
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: TextField(
                key: const Key('shelf-search-field'),
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: controller.search,
                decoration: InputDecoration(
                  hintText: l10n.searchSeriesHint,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                ),
              ),
            ),
          LibraryFilterBar(
            selected: state.libraryId,
            onSelected: controller.selectLibrary,
          ),
          Expanded(
            child: _ShelfBody(
              state: state,
              onRefresh: () {
                ref.invalidate(ondeckProvider);
                return controller.refresh();
              },
              onLoadMore: controller.loadMore,
              onSignOut: () => ref.read(sessionProvider.notifier).signOut(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfBody extends StatelessWidget {
  const _ShelfBody({
    required this.state,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onSignOut,
  });

  final ShelfState state;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (state.loading && state.series.isEmpty) {
      return const ShelfSkeleton();
    }

    final failure = state.failure;
    if (failure != null && state.series.isEmpty) {
      final needsSignIn = failure is AuthFailure;
      return RefreshableStatus(
        onRefresh: onRefresh,
        status: StatusView(
          key: const Key('shelf-error'),
          icon: Icons.cloud_off_outlined,
          title: failure.message,
          message: failure.hint,
          actionLabel: needsSignIn ? l10n.signOut : l10n.retry,
          onAction: needsSignIn ? onSignOut : () => unawaited(onRefresh()),
        ),
      );
    }

    if (state.isEmpty) {
      return RefreshableStatus(
        onRefresh: onRefresh,
        status: StatusView(
          key: const Key('shelf-empty'),
          icon: Icons.auto_stories_outlined,
          title: state.query.isEmpty ? l10n.noSeriesYet : l10n.noMatches,
          message: state.query.isEmpty
              ? l10n.emptyShelfHint
              : l10n.noSearchMatchesHint,
        ),
      );
    }

    return ShelfGrid(
      state: state,
      onRefresh: onRefresh,
      onLoadMore: onLoadMore,
    );
  }
}
