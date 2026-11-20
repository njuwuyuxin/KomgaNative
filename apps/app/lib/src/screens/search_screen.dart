import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_native/src/screens/search_results_sliver.dart';
import 'package:komga_native/src/widgets/search_empty_state.dart';
import 'package:material_ui/material_ui.dart';

/// 全局搜索（UI-P3-9 / ARC-12 拆出 [SearchResultsSliver]）。
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  SeriesReadStatus? _readStatus;
  String? _tag;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(AppMotion.of(context).emphasized, () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  void _onSubmitted(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    ref.read(settingsProvider.notifier).rememberSearchTerm(query);
    setState(() => _query = query);
  }

  void _pick(String term) {
    _debounce?.cancel();
    _controller.text = term;
    ref.read(settingsProvider.notifier).rememberSearchTerm(term);
    setState(() => _query = term);
  }

  void _removeHistory(String term) {
    ref.read(settingsProvider.notifier).removeSearchTerm(term);
  }

  void _clearHistory() {
    ref.read(settingsProvider.notifier).clearSearchHistory();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(searchHistoryProvider);
    return Scaffold(
      body: GlassPageBackground(
        child: CustomScrollView(
          slivers: <Widget>[
            GlassHeaderSliver(
              header: GlassHeader(
                bar: GlassSearchField(
                  key: const Key('search-field'),
                  controller: _controller,
                  hintText: l10n.searchHint,
                  clearLabel: l10n.closeSearch,
                  autofocus: true,
                  onChanged: _onChanged,
                  onSubmitted: _onSubmitted,
                ),
              ),
            ),
            if (_query.isEmpty)
              SliverToBoxAdapter(
                child: SearchEmptyState(
                  history: history,
                  onPick: _pick,
                  onRemove: _removeHistory,
                  onClear: _clearHistory,
                ),
              )
            else
              SearchResultsSliver(
                query: _query,
                readStatus: _readStatus,
                tag: _tag,
                onReadStatus: (SeriesReadStatus? value) =>
                    setState(() => _readStatus = value),
                onTag: (String? value) => setState(() => _tag = value),
                onClearFacets: () => setState(() {
                  _readStatus = null;
                  _tag = null;
                }),
              ),
          ],
        ),
      ),
    );
  }
}
