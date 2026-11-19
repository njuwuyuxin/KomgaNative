import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/data/shelf_view_options.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/widgets/series_shelf_tile.dart';
import 'package:material_ui/material_ui.dart';

/// 收藏集里的系列（UI-P3-8）。
class CollectionDetailScreen extends ConsumerWidget {
  const CollectionDetailScreen({
    required this.collectionId,
    this.title,
    super.key,
  });

  final String collectionId;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(collectionSeriesProvider(collectionId));
    return Scaffold(
      appBar: AppBar(title: Text(title ?? l10n.collectionFallback)),
      body: _SeriesList(
        async: async,
        onRetry: () {
          ref.invalidate(collectionSeriesProvider(collectionId));
        },
      ),
    );
  }
}

class _SeriesList extends StatelessWidget {
  const _SeriesList({required this.async, required this.onRetry});

  final AsyncValue<PageResult<Series>> async;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (async.hasError && !async.hasValue) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              async.error is ShelfFailure
                  ? (async.error! as ShelfFailure).message
                  : l10n.errorGeneric,
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ),
      );
    }
    final page = async.value;
    if (page == null) return const Center(child: CircularProgressIndicator());
    if (page.items.isEmpty) {
      return Center(child: Text(l10n.collectionsEmpty));
    }
    return ListView.separated(
      key: const Key('collection-series-list'),
      itemCount: page.items.length,
      separatorBuilder: (_, _) => const Divider(height: AppSizes.hairline),
      itemBuilder: (BuildContext context, int index) {
        final series = page.items[index];
        return SeriesShelfRow(
          series: series,
          coverSize: ShelfCoverSize.medium,
          onTap: () => context.push('/series/${series.id}'),
        );
      },
    );
  }
}
