import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/shelf_filter_preset.dart';
import 'package:komga_native/src/data/shelf_view_options.dart';
import 'package:material_ui/material_ui.dart';

/// 搜索历史最多留几条：10 条足够覆盖最近找过的，再多会把空态撑成一整屏。
const int kSearchHistoryLimit = 10;

/// 全部可持久化的本地偏好。
///
/// 为什么集中成一个快照：这些字段分别被设置页（主题/墨水屏/语言/触感）和书架
/// （视图/封面档位/排序/筛选）修改，但它们共用**同一个**钥匙串 blob。读改写
/// 走同一份快照，谁也不会把别人刚写的字段冲回旧值（FIX-02）。
///
/// 反序列化一律容错：单个字段类型不对/枚举不认识，只让**该字段**回默认，
/// 不整份丢掉、更不能让启动崩掉——存档可能是旧版本写的，也可能被手工改过。
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.forceEink = false,
    this.language = 'system',
    this.haptics = true,
    this.view = ShelfView.grid,
    this.coverSize = ShelfCoverSize.medium,
    this.sort,
    this.readStatus,
    this.libraryFilters = const <String, String>{},
    this.filterPresets = const <String, List<ShelfFilterPreset>>{},
    this.searchHistory = const <String>[],
    this.downloadWifiOnly = false,
    this.downloadAutoDeleteRead = false,
    this.downloadConcurrency = 1,
  });

  /// 全默认值（没有存档、存档写坏、字段缺失时都用它）。
  static const AppSettings defaults = AppSettings();

  final ThemeMode themeMode;
  final bool forceEink;

  /// 语言编码（`system` / `en` / `zh`）。data 层不认识语言枚举，
  /// 由 `settings_provider.appLanguageFromCode` 解释，未知值回"跟随系统"。
  final String language;
  final bool haptics;

  final ShelfView view;
  final ShelfCoverSize coverSize;

  /// 书架排序；null = 服务端默认顺序。
  final SeriesSort? sort;

  /// 书架阅读状态筛选；null = 不筛选。
  final SeriesReadStatus? readStatus;

  /// 每台服务器上次选中的库（key = 服务器 base URL）。
  ///
  /// 不能只存一个 id：切到另一台服务器时那个 id 在库列表里不存在，
  /// 书架会变成"空书架"（FIX-02 的验收点之一）。
  final Map<String, String> libraryFilters;

  /// 每台服务器上保存的筛选组合（LIB-04）；key = 服务器 base URL。
  ///
  /// 按服务器分区：切服务器时另一台的库 id 在本机根本不成立。
  final Map<String, List<ShelfFilterPreset>> filterPresets;

  /// 最近搜索（最新的在前，最多 kSearchHistoryLimit 条）。空态展示与回填用。
  final List<String> searchHistory;

  /// 只在 Wi-Fi 下下载（DLD-01）。
  final bool downloadWifiOnly;

  /// 读完一本就删掉它的下载（DLD-01）。
  final bool downloadAutoDeleteRead;

  /// 同时下载几本（1–3）。默认 1：并发下载会把单本的页图请求挤慢，
  /// 而阅读体验的瓶颈通常在服务端而不是本地带宽。
  final int downloadConcurrency;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? forceEink,
    String? language,
    bool? haptics,
    ShelfView? view,
    ShelfCoverSize? coverSize,
    Object? sort = _unset,
    Object? readStatus = _unset,
    Map<String, String>? libraryFilters,
    Map<String, List<ShelfFilterPreset>>? filterPresets,
    List<String>? searchHistory,
    bool? downloadWifiOnly,
    bool? downloadAutoDeleteRead,
    int? downloadConcurrency,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    forceEink: forceEink ?? this.forceEink,
    language: language ?? this.language,
    haptics: haptics ?? this.haptics,
    view: view ?? this.view,
    coverSize: coverSize ?? this.coverSize,
    sort: identical(sort, _unset) ? this.sort : sort as SeriesSort?,
    readStatus: identical(readStatus, _unset)
        ? this.readStatus
        : readStatus as SeriesReadStatus?,
    libraryFilters: libraryFilters ?? this.libraryFilters,
    filterPresets: filterPresets ?? this.filterPresets,
    searchHistory: searchHistory ?? this.searchHistory,
    downloadWifiOnly: downloadWifiOnly ?? this.downloadWifiOnly,
    downloadAutoDeleteRead:
        downloadAutoDeleteRead ?? this.downloadAutoDeleteRead,
    downloadConcurrency: downloadConcurrency ?? this.downloadConcurrency,
  );

  /// 记下某台服务器选的库；[libraryId] 为 null 表示"全部库"。
  AppSettings withLibraryFilter(String serverKey, String? libraryId) {
    final next = Map<String, String>.of(libraryFilters);
    if (libraryId == null) {
      next.remove(serverKey);
    } else {
      next[serverKey] = libraryId;
    }
    return copyWith(libraryFilters: next);
  }

  /// 这台服务器上次选的库；没存过返回 null。
  String? libraryFilterFor(String? serverKey) =>
      serverKey == null ? null : libraryFilters[serverKey];

  /// 这台服务器保存的筛选组合（没有就是空列表）。
  List<ShelfFilterPreset> presetsFor(String? serverKey) => serverKey == null
      ? const <ShelfFilterPreset>[]
      : (filterPresets[serverKey] ?? const <ShelfFilterPreset>[]);

  /// 保存/覆盖一条筛选组合（按 id 覆盖，最多留 8 条防无限增长）。
  AppSettings withPreset(String serverKey, ShelfFilterPreset preset) {
    final next = <String, List<ShelfFilterPreset>>{
      for (final entry in filterPresets.entries)
        entry.key: List<ShelfFilterPreset>.of(entry.value),
    };
    final list = next.putIfAbsent(serverKey, () => <ShelfFilterPreset>[]);
    list.removeWhere((ShelfFilterPreset p) => p.id == preset.id);
    list.insert(0, preset);
    if (list.length > 8) list.removeRange(8, list.length);
    return copyWith(filterPresets: next);
  }

  /// 删掉一条筛选组合。
  AppSettings withoutPreset(String serverKey, String id) {
    final next = <String, List<ShelfFilterPreset>>{
      for (final entry in filterPresets.entries)
        entry.key: List<ShelfFilterPreset>.of(entry.value),
    };
    final list = next[serverKey];
    if (list == null) return this;
    list.removeWhere((ShelfFilterPreset p) => p.id == id);
    if (list.isEmpty) next.remove(serverKey);
    return copyWith(filterPresets: next);
  }

  /// 记一条搜索：去重（再次搜同一个词要移到最前）、截断到上限。
  AppSettings withSearchTerm(String term) {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return this;
    final next = <String>[
      trimmed,
      for (final item in searchHistory)
        if (item != trimmed) item,
    ];
    return copyWith(searchHistory: next.take(kSearchHistoryLimit).toList());
  }

  /// 删掉一条历史（长按 / 滑动删除）。
  AppSettings withoutSearchTerm(String term) => copyWith(
    searchHistory: <String>[
      for (final item in searchHistory)
        if (item != term) item,
    ],
  );

  AppSettings clearSearchHistory() => copyWith(searchHistory: const <String>[]);

  Map<String, Object?> toJson() => <String, Object?>{
    'theme': themeMode.name,
    'forceEink': forceEink,
    'language': language,
    'haptics': haptics,
    'shelfView': view.name,
    'coverSize': coverSize.name,
    if (sort != null) 'sort': sort!.name,
    if (readStatus != null) 'readStatus': readStatus!.name,
    if (libraryFilters.isNotEmpty) 'libraryFilters': libraryFilters,
    if (searchHistory.isNotEmpty) 'searchHistory': searchHistory,
    if (downloadWifiOnly) 'downloadWifiOnly': true,
    if (downloadAutoDeleteRead) 'downloadAutoDeleteRead': true,
    if (downloadConcurrency != 1) 'downloadConcurrency': downloadConcurrency,
    if (filterPresets.isNotEmpty)
      'filterPresets': <String, Object?>{
        for (final entry in filterPresets.entries)
          entry.key: <Object?>[
            for (final preset in entry.value) preset.toJson(),
          ],
      },
  };

  /// 从存档解析；任何字段坏了都只影响它自己。
  factory AppSettings.fromJson(Map<String, Object?> json) {
    final rawFilters = json['libraryFilters'];
    return AppSettings(
      themeMode: _enumByName(json['theme'], ThemeMode.values, ThemeMode.system),
      forceEink: _bool(json['forceEink'], false),
      language: _string(json['language'], 'system'),
      haptics: _bool(json['haptics'], true),
      view: _enumByName(json['shelfView'], ShelfView.values, ShelfView.grid),
      coverSize: _enumByName(
        json['coverSize'],
        ShelfCoverSize.values,
        ShelfCoverSize.medium,
      ),
      sort: _enumByNameOrNull(json['sort'], SeriesSort.values),
      readStatus: _enumByNameOrNull(
        json['readStatus'],
        SeriesReadStatus.values,
      ),
      libraryFilters: rawFilters is Map
          ? <String, String>{
              for (final entry in rawFilters.entries)
                if (entry.key is String &&
                    entry.value is String &&
                    (entry.value as String).isNotEmpty)
                  entry.key as String: entry.value as String,
            }
          : const <String, String>{},
      filterPresets: _parsePresets(json['filterPresets']),
      searchHistory: _parseHistory(json['searchHistory']),
      downloadWifiOnly: _bool(json['downloadWifiOnly'], false),
      downloadAutoDeleteRead: _bool(json['downloadAutoDeleteRead'], false),
      // 越界的并发数（被改坏的存档）夹回 1–3。
      downloadConcurrency:
          (json['downloadConcurrency'] is int
                  ? json['downloadConcurrency']! as int
                  : 1)
              .clamp(1, 3),
    );
  }

  /// 解析"每台服务器的筛选组合"：坏条目逐条丢弃，不影响其它条。
  /// 解析搜索历史：只收非空字符串，去重并截断（存档可能被改坏）。
  static List<String> _parseHistory(Object? raw) {
    if (raw is! List) return const <String>[];
    final result = <String>[];
    for (final item in raw) {
      if (item is! String) continue;
      final trimmed = item.trim();
      if (trimmed.isEmpty || result.contains(trimmed)) continue;
      result.add(trimmed);
      if (result.length >= kSearchHistoryLimit) break;
    }
    return result;
  }

  static Map<String, List<ShelfFilterPreset>> _parsePresets(Object? raw) {
    if (raw is! Map) return const <String, List<ShelfFilterPreset>>{};
    final result = <String, List<ShelfFilterPreset>>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || key.isEmpty || value is! List) continue;
      final presets = <ShelfFilterPreset>[
        for (final item in value)
          if (ShelfFilterPreset.fromJson(item) case final ShelfFilterPreset p)
            p,
      ];
      if (presets.isNotEmpty) result[key] = presets;
    }
    return result;
  }

  static const Object _unset = Object();
}

String _string(Object? raw, String fallback) =>
    raw is String && raw.isNotEmpty ? raw : fallback;

bool _bool(Object? raw, bool fallback) => raw is bool ? raw : fallback;

T _enumByName<T extends Enum>(Object? raw, List<T> values, T fallback) =>
    _enumByNameOrNull(raw, values) ?? fallback;

T? _enumByNameOrNull<T extends Enum>(Object? raw, List<T> values) {
  if (raw is! String) return null;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return null;
}
