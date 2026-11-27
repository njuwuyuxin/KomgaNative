import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/l10n/failure_text.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/widgets/cover_image.dart';
import 'package:yomu/src/widgets/load_more_footer.dart';
import 'package:yomu/src/widgets/picker_sheet_shell.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 在收藏集详情页内选择系列加入该收藏集的底部抽屉。
///
/// 返回用户新勾选的系列 id 列表（不包含已在 [existingIds] 里的）；取消返回 `null`。
Future<List<String>?> showSeriesPickerSheet(
  BuildContext context, {
  required Set<String> existingIds,
}) => showModalBottomSheet<List<String>>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (BuildContext context) =>
      _SeriesPickerSheet(existingIds: existingIds),
);

class _SeriesPickerSheet extends ConsumerStatefulWidget {
  const _SeriesPickerSheet({required this.existingIds});

  final Set<String> existingIds;

  @override
  ConsumerState<_SeriesPickerSheet> createState() => _SeriesPickerSheetState();
}

class _SeriesPickerSheetState extends ConsumerState<_SeriesPickerSheet> {
  final Set<String> _picked = <String>{};
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _toggle(String seriesId) {
    unawaited(AppHaptics.selection());
    setState(() {
      if (!_picked.remove(seriesId)) _picked.add(seriesId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final search = (query: _query, readStatus: null, tag: null);
    final provider = searchSeriesProvider(search);
    final async = ref.watch(provider);

    return PickerSheetShell(
      sheetKey: const Key('series-picker-sheet'),
      maxHeightFactor: 0.78,
      title: l10n.addSeriesToCollection,
      showSearch: true,
      searchKey: const Key('series-picker-search'),
      searchHint: l10n.searchSeriesHint,
      onSearchChanged: _onSearchChanged,
      body: _buildList(
        l10n,
        async,
        onRetry: () => ref.invalidate(provider),
        onLoadMore: () => unawaited(ref.read(provider.notifier).loadMore()),
      ),
      footer: FilledButton(
        key: const Key('series-picker-confirm'),
        onPressed: _picked.isEmpty
            ? null
            : () => Navigator.of(context).pop(_picked.toList()),
        child: Text(
          _picked.isEmpty
              ? l10n.addSeriesToCollection
              : l10n.collectionAddButton(_picked.length),
        ),
      ),
    );
  }

  Widget _buildList(
    AppLocalizations l10n,
    AsyncValue<PageResult<Series>> async, {
    required VoidCallback onRetry,
    required VoidCallback onLoadMore,
  }) {
    if (async.hasError && !async.hasValue) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
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
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (page.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: StatusView(icon: Icons.search_off, title: l10n.noMatches),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: page.items.length + 1,
      itemBuilder: (BuildContext context, int index) {
        if (index == page.items.length) {
          return LoadMoreFooter(
            loaded: page.items.length,
            total: page.totalElements,
            unit: LoadMoreUnit.series,
            onLoadMore: onLoadMore,
          );
        }
        final series = page.items[index];
        final alreadyIn = widget.existingIds.contains(series.id);
        final checked = alreadyIn || _picked.contains(series.id);
        return CheckboxListTile(
          key: Key('series-pick-${series.id}'),
          value: checked,
          onChanged: alreadyIn ? null : (_) => _toggle(series.id),
          secondary: _SeriesMiniCover(seriesId: series.id),
          title: Text(
            series.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            alreadyIn
                ? l10n.collectionAlreadyIn
                : l10n.booksCount(series.booksCount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

class _SeriesMiniCover extends ConsumerWidget {
  const _SeriesMiniCover({required this.seriesId});

  final String seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cover = ref.watch(
      seriesCoverProvider((sourceKey: null, id: seriesId)),
    );
    final Uint8List? bytes = switch (cover) {
      AsyncData<Uint8List?>(:final value) => value,
      _ => null,
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: SizedBox(
        width: AppSpacing.xl,
        height: AppSpacing.xxl,
        child: bytes == null || bytes.isEmpty
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
              )
            : CoverImage(bytes: bytes),
      ),
    );
  }
}
