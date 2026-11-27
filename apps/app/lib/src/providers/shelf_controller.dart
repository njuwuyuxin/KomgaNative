import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/app_settings.dart';
import 'package:yomu/src/data/library_repository.dart';
import 'package:yomu/src/data/missing_source_repository.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/data/shelf_filter_preset.dart';
import 'package:yomu/src/data/shelf_view_options.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/session/session_controller.dart';

export 'package:yomu/src/providers/shelf_state.dart';

/// 书架控制器：分页、搜索、按库筛选，并处理请求竞态。
class ShelfController extends Notifier<ShelfState> {
  static const Duration searchDebounce = Duration(milliseconds: 350);

  int _generation = 0;
  Timer? _debounce;
  final Set<String> _touched = <String>{};

  @override
  ShelfState build() {
    final repo = ref.watch(libraryRepositoryProvider);
    ref.onDispose(() => _debounce?.cancel());
    // 服务器列表仍在冷启动加载且目标远程源尚未注册时，保持初始 loading 态，
    // 绝不把远程筛选预设套到本机库，也不在过渡帧闪错误态（P1-3）。
    if (repo is MissingSourceRepository &&
        ref.watch(serverListProvider).isLoading) {
      return const ShelfState();
    }
    ref.listen<int>(readStatusEpochProvider, (_, _) {
      unawaited(refreshInPlace());
    });
    unawaited(Future<void>.microtask(() => _load(reset: true)));
    unawaited(_restore());
    return const ShelfState();
  }

  LibraryRepository get _repository => ref.read(libraryRepositoryProvider);

  SettingsStore get _store => ref.read(settingsStoreProvider);

  String? get _serverKey => ref.read(activeSourceProvider).sourceKey;

  Future<void> _restore() async {
    final saved = await _store.load();
    if (!ref.mounted) return;
    final libraryId = _touched.contains('library')
        ? state.libraryId
        : await _storedLibraryId(saved);
    if (!ref.mounted) return;

    final next = state.copyWith(
      view: _touched.contains('view') ? state.view : saved.view,
      coverSize: _touched.contains('coverSize')
          ? state.coverSize
          : saved.coverSize,
      sort: _touched.contains('sort') ? state.sort : saved.sort,
      readStatus: _touched.contains('readStatus')
          ? state.readStatus
          : saved.readStatus,
      libraryId: libraryId,
      presets: saved.presetsFor(_serverKey),
    );
    final needsReload =
        next.sort != state.sort ||
        next.readStatus != state.readStatus ||
        next.libraryId != state.libraryId;
    state = next;

    final serverKey = _serverKey;
    if (libraryId == null &&
        serverKey != null &&
        saved.libraryFilterFor(serverKey) != null) {
      _persist((AppSettings s) => s.withLibraryFilter(serverKey, null));
    }
    if (needsReload) await _load(reset: true);
  }

  Future<String?> _storedLibraryId(AppSettings saved) async {
    final stored = saved.libraryFilterFor(_serverKey);
    if (stored == null) return null;
    try {
      final libraries = await ref.read(librariesProvider.future);
      if (libraries.any((Library library) => library.id == stored)) {
        return stored;
      }
    } on ShelfFailure {
      return stored;
    }
    return null;
  }

  void _persist(AppSettings Function(AppSettings current) mutate) {
    unawaited(_store.update(mutate));
  }

  Future<void> refresh() {
    _debounce?.cancel();
    return _load(reset: true);
  }

  Future<void> refreshInPlace() {
    _debounce?.cancel();
    return _load(reset: true, keepItems: true);
  }

  /// 仅当书架当前正在展示目标 [sourceKey] 时原地刷新（避免业务层直接窥探激活源）。
  Future<void> refreshForSource(String sourceKey) {
    if (_serverKey != sourceKey) return Future<void>.value();
    return refreshInPlace();
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    await _load(reset: false);
  }

  void selectLibrary(String? libraryId) {
    if (state.libraryId == libraryId) return;
    _debounce?.cancel();
    _touched.add('library');
    final serverKey = _serverKey;
    state = state.copyWith(
      libraryId: libraryId,
      series: const <Series>[],
      page: 0,
      totalElements: 0,
      hasMore: false,
      loading: true,
      clearFailure: true,
      clearLoadMoreFailure: true,
    );
    if (serverKey != null) {
      _persist((AppSettings s) => s.withLibraryFilter(serverKey, libraryId));
    }
    unawaited(_load(reset: true));
  }

  void search(String raw) {
    final query = raw.trim();
    if (query == state.query) return;
    state = state.copyWith(query: query);
    _debounce?.cancel();
    _debounce = Timer(searchDebounce, () => unawaited(_load(reset: true)));
  }

  void setSort(SeriesSort? sort) {
    if (state.sort == sort) return;
    _touched.add('sort');
    _persist((AppSettings s) => s.copyWith(sort: sort));
    _reloadWith(state.copyWith(sort: sort));
  }

  void setReadStatus(SeriesReadStatus? status) {
    if (state.readStatus == status) return;
    _touched.add('readStatus');
    _persist((AppSettings s) => s.copyWith(readStatus: status));
    _reloadWith(state.copyWith(readStatus: status));
  }

  void savePreset(String name) {
    final serverKey = _serverKey ?? '';
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final preset = ShelfFilterPreset(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: trimmed,
      sort: state.sort,
      readStatus: state.readStatus,
      libraryId: state.libraryId,
    );
    if (preset.isEmpty) return;
    _persist((AppSettings s) => s.withPreset(serverKey, preset));
    state = state.copyWith(
      presets: <ShelfFilterPreset>[preset, ...state.presets],
    );
  }

  void applyPreset(ShelfFilterPreset preset) {
    final serverKey = _serverKey ?? '';
    _touched.addAll(<String>['sort', 'readStatus', 'libraryId']);
    _persist(
      (AppSettings s) =>
          s.copyWith(sort: preset.sort, readStatus: preset.readStatus),
    );
    if (preset.libraryId != null) {
      _persist(
        (AppSettings s) => s.withLibraryFilter(serverKey, preset.libraryId),
      );
    }
    _reloadWith(
      state.copyWith(
        sort: preset.sort,
        readStatus: preset.readStatus,
        libraryId: preset.libraryId,
      ),
    );
  }

  void deletePreset(String id) {
    final serverKey = _serverKey ?? '';
    _persist((AppSettings s) => s.withoutPreset(serverKey, id));
    state = state.copyWith(
      presets: <ShelfFilterPreset>[
        for (final preset in state.presets)
          if (preset.id != id) preset,
      ],
    );
  }

  void setView(ShelfView view) {
    if (state.view == view) return;
    _touched.add('view');
    state = state.copyWith(view: view);
    _persist((AppSettings s) => s.copyWith(view: view));
  }

  void setCoverSize(ShelfCoverSize size) {
    if (state.coverSize == size) return;
    _touched.add('coverSize');
    state = state.copyWith(coverSize: size);
    _persist((AppSettings s) => s.copyWith(coverSize: size));
  }

  void _reloadWith(ShelfState next) {
    _debounce?.cancel();
    state = next.copyWith(
      series: const <Series>[],
      page: 0,
      totalElements: 0,
      hasMore: false,
      loading: true,
      clearFailure: true,
      clearLoadMoreFailure: true,
    );
    unawaited(_load(reset: true));
  }

  Future<void> _load({required bool reset, bool keepItems = false}) async {
    final generation = ++_generation;
    final targetPage = reset ? 0 : state.page + 1;
    final keepVisible = keepItems && state.series.isNotEmpty;

    state = reset
        ? state.copyWith(
            loading: !keepVisible,
            clearFailure: true,
            clearLoadMoreFailure: true,
          )
        : state.copyWith(loadingMore: true, clearLoadMoreFailure: true);

    try {
      final result = await _repository.series(
        libraryId: state.libraryId,
        query: state.query,
        page: targetPage,
        sort: state.sort,
        readStatus: state.readStatus,
      );
      if (generation != _generation) return;

      state = state.copyWith(
        series: reset
            ? result.items
            : <Series>[...state.series, ...result.items],
        page: result.page,
        totalElements: result.totalElements,
        hasMore: result.hasMore,
        loading: false,
        loadingMore: false,
        clearFailure: true,
      );
    } on ShelfFailure catch (failure) {
      if (generation != _generation) return;
      state = reset && state.series.isEmpty
          ? state.copyWith(loading: false, failure: failure)
          : state.copyWith(
              loading: false,
              loadingMore: false,
              loadMoreFailure: failure,
            );
    }
  }
}

final NotifierProvider<ShelfController, ShelfState> shelfProvider =
    NotifierProvider<ShelfController, ShelfState>(ShelfController.new);
