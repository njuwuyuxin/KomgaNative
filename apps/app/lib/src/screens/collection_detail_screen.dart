import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/l10n/failure_text.dart';
import 'package:komga_native/src/data/shelf_view_options.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/widgets/load_more_footer.dart';
import 'package:komga_native/src/widgets/series_shelf_tile.dart';
import 'package:material_ui/material_ui.dart';

/// 收藏集里的系列（UI-P3-8）。
///
/// 支持"加载更多"（FIX-08）：收藏集可能有上百个系列，之前只取 20 个，
/// 第 21 个起静默消失。
class CollectionDetailScreen extends ConsumerStatefulWidget {
  const CollectionDetailScreen({
    required this.collectionId,
    this.title,
    super.key,
  });

  final String collectionId;
  final String? title;

  @override
  ConsumerState<CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState
    extends ConsumerState<CollectionDetailScreen> {
  int _size = kListPageSize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = (collectionId: widget.collectionId, size: _size);
    final async = ref.watch(collectionSeriesProvider(query));
    return Scaffold(
      body: GlassPageBackground(
        child: CustomScrollView(
          slivers: <Widget>[
            GlassHeaderSliver(
              header: GlassHeader(
                leading: GlassIconButton(
                  icon: Icons.chevron_left,
                  label: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => context.pop(),
                ),
                title: Text(widget.title ?? l10n.collectionFallback),
              ),
            ),
            _SeriesSliver(
              async: async,
              onRetry: () => ref.invalidate(collectionSeriesProvider(query)),
              onLoadMore: () => setState(() => _size += kListPageSize),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppSizes.navBarClearance),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeriesSliver extends StatelessWidget {
  const _SeriesSliver({
    required this.async,
    required this.onRetry,
    required this.onLoadMore,
  });

  final AsyncValue<PageResult<Series>> async;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (async.hasError && !async.hasValue) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: StatusView(
          icon: Icons.cloud_off_outlined,
          title: l10n.failureTitle(failureKindOf(async.error)),
          actionLabel: l10n.retry,
          onAction: onRetry,
        ),
      );
    }
    final page = async.value;
    if (page == null) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (page.items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: StatusView(
          icon: Icons.collections_bookmark_outlined,
          title: l10n.collectionsEmpty,
        ),
      );
    }
    return SliverList.list(
      key: const Key('collection-series-list'),
      children: <Widget>[
        for (final series in page.items)
          SeriesShelfRow(
            series: series,
            coverSize: ShelfCoverSize.medium,
            onTap: () => context.push('/series/${series.id}'),
          ),
        LoadMoreFooter(
          loaded: page.items.length,
          total: page.totalElements,
          unit: LoadMoreUnit.series,
          onLoadMore: onLoadMore,
        ),
      ],
    );
  }
}
