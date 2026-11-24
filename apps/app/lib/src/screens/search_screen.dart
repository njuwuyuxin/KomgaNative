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
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  String _query = '';
  SeriesReadStatus? _readStatus;
  String? _tag;

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    if (_focusNode.hasFocus) {
      _focusNode.unfocus();
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
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
    _dismissKeyboard();
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
    return GestureDetector(
      // 点击空白处收起键盘；输入框/按钮会赢得点击竞技场，不会被这里抢走。
      behavior: HitTestBehavior.translucent,
      onTap: _dismissKeyboard,
      child: Scaffold(
        body: GlassPageBackground(
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: <Widget>[
              GlassHeaderSliver(
                header: GlassHeader(
                  bar: GlassSearchField(
                    key: const Key('search-field'),
                    controller: _controller,
                    focusNode: _focusNode,
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
                  onReadStatus: (SeriesReadStatus? value) {
                    _dismissKeyboard();
                    setState(() => _readStatus = value);
                  },
                  onTag: (String? value) {
                    _dismissKeyboard();
                    setState(() => _tag = value);
                  },
                  onClearFacets: () {
                    _dismissKeyboard();
                    setState(() {
                      _readStatus = null;
                      _tag = null;
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
