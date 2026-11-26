import 'package:yomu/src/data/reader_config.dart';

export 'package:yomu/src/data/reader_config.dart';

/// 一组命名的阅读设置（UI-P3-1）。
///
/// 预设直接持有不可变 [ReaderConfig] 快照，天然不含预设列表与系列覆盖。
class ReaderPreset {
  const ReaderPreset({
    required this.id,
    required this.name,
    required this.config,
  });

  final String id;
  final String name;
  final ReaderConfig config;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    // 保持字段名为 'prefs' 以兼容既有本地存档与备份导出。
    'prefs': config.toJson(),
  };

  /// 坏条目返回 null（旧存档/手工改坏），调用方直接跳过，不让整份偏好失效。
  static ReaderPreset? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final rawConfig = raw['prefs'] ?? raw['config'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) {
      return null;
    }
    if (rawConfig is! Map) return null;
    final config = ReaderConfig.fromJson(Map<String, Object?>.from(rawConfig));
    return ReaderPreset(id: id, name: name.trim(), config: config);
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderPreset &&
      other.id == id &&
      other.name == name &&
      other.config == config;

  @override
  int get hashCode => Object.hash(id, name, config);

  @override
  String toString() => 'ReaderPreset($id, $name)';
}

/// 阅读器偏好顶层聚合容器（ARC-04）。
///
/// 由全局 [ReaderConfig]、平板默认排版 [tabletLayout]、按书双页分组 [spreadFrom]、
/// 命名预设列表 [presets] 与按系列覆盖 [seriesOverrides] 组成。
class ReaderPrefs {
  const ReaderPrefs({
    this.global = const ReaderConfig(),
    this.tabletLayout = TabletLayoutChoice.auto,
    this.spreadFrom = const <String, int>{},
    this.presets = const <ReaderPreset>[],
    this.seriesOverrides = const <String, ReaderConfig>{},
  });

  static const double minBrightness = ReaderConfig.minBrightness;

  /// 全局默认阅读配置。
  final ReaderConfig global;

  /// 平板上的默认排版（PLT-02）：全局设备级设置，不进系列覆盖。
  final TabletLayoutChoice tabletLayout;

  /// 双页模式的手动分组起点（RDR-06）：bookId → 0 基页码。
  final Map<String, int> spreadFrom;

  /// 用户保存的阅读预设（UI-P3-1）；按保存顺序排列。
  final List<ReaderPreset> presets;

  /// 按系列覆盖的阅读配置（UI-P3-2）：seriesId → [ReaderConfig]。
  final Map<String, ReaderConfig> seriesOverrides;

  /// 组合带服务器分区的键（`$serverKey|$id`）；未提供服务器标识时退化为裸 `id`。
  static String scopedKey(String? serverKey, String id) =>
      (serverKey == null || serverKey.isEmpty) ? id : '$serverKey|$id';

  /// 当前服务器下该系列是否已启用系列覆盖（兼容无前缀旧存档键）。
  bool hasSeriesOverride(String? seriesId, {String? serverKey}) {
    if (seriesId == null) return false;
    if (serverKey != null && serverKey.isNotEmpty) {
      if (seriesOverrides.containsKey('$serverKey|$seriesId')) return true;
    }
    return seriesOverrides.containsKey(seriesId);
  }

  /// 某个系列实际生效的配置：优先命中 `$serverKey|$seriesId`，其次回退旧版裸 `seriesId`，最后返回 [global]。
  ReaderConfig forSeries(String? seriesId, {String? serverKey}) {
    if (seriesId == null) return global;
    if (serverKey != null && serverKey.isNotEmpty) {
      final scoped = seriesOverrides['$serverKey|$seriesId'];
      if (scoped != null) return scoped;
    }
    return seriesOverrides[seriesId] ?? global;
  }

  /// 读取某本书的双页分组起点：优先命中 `$serverKey|$bookId`，兼容回退裸 `bookId`。
  int? spreadFromFor(String bookId, {String? serverKey}) {
    if (serverKey != null && serverKey.isNotEmpty) {
      final scoped = spreadFrom['$serverKey|$bookId'];
      if (scoped != null) return scoped;
    }
    return spreadFrom[bookId];
  }

  /// 记住/清除某本书的双页分组起点（RDR-06 / ARC-07）。[index] 为 null 表示恢复自动。
  ReaderPrefs withSpreadFrom(String bookId, int? index, {String? serverKey}) {
    final next = Map<String, int>.of(spreadFrom);
    final key = scopedKey(serverKey, bookId);
    if (index == null || index < 0) {
      next.remove(key);
      if (key != bookId) next.remove(bookId);
    } else {
      next[key] = index;
    }
    return copyWith(spreadFrom: next);
  }

  /// 写入/删除某个系列的覆盖。传入 null 表示删除。
  ReaderPrefs withSeriesOverride(
    String seriesId,
    ReaderConfig? config, {
    String? serverKey,
  }) {
    final next = Map<String, ReaderConfig>.from(seriesOverrides);
    final key = scopedKey(serverKey, seriesId);
    if (config == null) {
      next.remove(key);
      if (key != seriesId) next.remove(seriesId);
    } else {
      next[key] = config;
    }
    return copyWith(seriesOverrides: next);
  }

  ReaderPrefs copyWith({
    ReaderConfig? global,
    TabletLayoutChoice? tabletLayout,
    Map<String, int>? spreadFrom,
    List<ReaderPreset>? presets,
    Map<String, ReaderConfig>? seriesOverrides,
  }) => ReaderPrefs(
    global: global ?? this.global,
    tabletLayout: tabletLayout ?? this.tabletLayout,
    spreadFrom: spreadFrom ?? this.spreadFrom,
    presets: presets ?? this.presets,
    seriesOverrides: seriesOverrides ?? this.seriesOverrides,
  );

  /// 保持现有扁平顶层 JSON 字段格式兼容旧存档与 [PrefsBackup]。
  Map<String, Object?> toJson() => <String, Object?>{
    ...global.toJson(),
    'tabletLayout': tabletLayout.name,
    if (spreadFrom.isNotEmpty) 'spreadFrom': spreadFrom,
    if (presets.isNotEmpty)
      'presets': <Object?>[for (final preset in presets) preset.toJson()],
    if (seriesOverrides.isNotEmpty)
      'seriesOverrides': <String, Object?>{
        for (final entry in seriesOverrides.entries)
          entry.key: entry.value.toJson(),
      },
  };

  /// 兼容旧版扁平顶层 JSON，坏值一律回默认。
  static ReaderPrefs fromJson(Map<String, Object?> json) {
    final rawPresets = json['presets'];
    final presets = <ReaderPreset>[];
    if (rawPresets is List) {
      for (final raw in rawPresets) {
        final preset = ReaderPreset.fromJson(raw);
        if (preset != null) presets.add(preset);
      }
    }
    final rawOverrides = json['seriesOverrides'];
    final overrides = <String, ReaderConfig>{};
    if (rawOverrides is Map) {
      for (final entry in rawOverrides.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        overrides[entry.key as String] = ReaderConfig.fromJson(
          Map<String, Object?>.from(entry.value as Map),
        );
      }
    }
    return ReaderPrefs(
      global: ReaderConfig.fromJson(json),
      tabletLayout: parseReaderEnum(
        json['tabletLayout'],
        TabletLayoutChoice.values,
        TabletLayoutChoice.auto,
      ),
      spreadFrom: _parseSpreadFrom(json['spreadFrom']),
      presets: presets,
      seriesOverrides: overrides,
    );
  }

  static Map<String, int> _parseSpreadFrom(Object? raw) {
    if (raw is! Map) return const <String, int>{};
    final result = <String, int>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || key.isEmpty) continue;
      if (value is! int || value < 0) continue;
      result[key] = value;
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderPrefs &&
      other.global == global &&
      other.tabletLayout == tabletLayout &&
      _sameSpreadFrom(other.spreadFrom, spreadFrom) &&
      _samePresets(other.presets, presets) &&
      _sameOverrides(other.seriesOverrides, seriesOverrides);

  static bool _sameSpreadFrom(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static bool _sameOverrides(
    Map<String, ReaderConfig> a,
    Map<String, ReaderConfig> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || other != entry.value) return false;
    }
    return true;
  }

  static bool _samePresets(List<ReaderPreset> a, List<ReaderPreset> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    global,
    tabletLayout,
    Object.hashAll(
      spreadFrom.entries.map(
        (MapEntry<String, int> e) => Object.hash(e.key, e.value),
      ),
    ),
    Object.hashAll(presets),
    Object.hashAll(
      seriesOverrides.entries.map(
        (MapEntry<String, ReaderConfig> e) => Object.hash(e.key, e.value),
      ),
    ),
  );

  @override
  String toString() =>
      'ReaderPrefs($global, tablet: ${tabletLayout.name}, '
      'presets: ${presets.length}, series: ${seriesOverrides.length})';
}
