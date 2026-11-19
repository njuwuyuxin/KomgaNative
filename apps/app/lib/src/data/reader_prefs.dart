import 'package:komga_domain/komga_domain.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';

/// 用户在阅读设置里选的模式。
///
/// 多一个 `auto` 是必要的：系列元数据能表达"条漫/竖向"，但表达不了"双页"。
/// `auto` 让"没选过"的用户跟随服务端元数据，选过的用户才有稳定的个人偏好。
enum ReaderModeChoice { auto, single, double, vertical }

extension ReaderModeChoiceX on ReaderModeChoice {
  /// 解析成引擎的阅读模式。
  ///
  /// `auto` 在竖屏跟随系列方向（条漫/竖向 → 纵向，其余单页）；
  /// **横屏时普通漫画自动双页**（Panels 的 Standard 预设行为，UI-P3-3）。
  /// 用户显式选过单页/双页/纵向则不受横竖屏影响。
  ReadingMode resolve(ReadingDirection direction, {bool landscape = false}) =>
      switch (this) {
        ReaderModeChoice.auto =>
          direction.isScroll
              ? ReadingMode.verticalScroll
              : (landscape ? ReadingMode.doublePage : ReadingMode.paged),
        ReaderModeChoice.single => ReadingMode.paged,
        ReaderModeChoice.double => ReadingMode.doublePage,
        ReaderModeChoice.vertical => ReadingMode.verticalScroll,
      };
}

/// 适配方式（UI-P1-3）。
///
/// 直接对应引擎的 `FitMode`：`cover`（填满屏幕）会在溢出的方向允许平移，
/// 双页模式一律按 `contain`（一跨页两页并排，任何"铺满"都会把另一页裁掉）。
enum ReaderFitChoice { contain, cover, fitWidth, fitHeight }

extension ReaderFitChoiceX on ReaderFitChoice {
  FitMode get fit => switch (this) {
    ReaderFitChoice.contain => FitMode.contain,
    ReaderFitChoice.cover => FitMode.cover,
    ReaderFitChoice.fitWidth => FitMode.fitWidth,
    ReaderFitChoice.fitHeight => FitMode.fitHeight,
  };
}

/// 阅读方向（UI-P1-4）。
///
/// `auto` 跟随系列元数据；另两项给"元数据没填 / 填错"的书兜底。
enum ReaderDirectionChoice { auto, leftToRight, rightToLeft }

extension ReaderDirectionChoiceX on ReaderDirectionChoice {
  /// 解析成"是否右到左"。系列方向未知（`unknown`）时按从左到右。
  bool resolveRightToLeft(ReadingDirection series) => switch (this) {
    ReaderDirectionChoice.auto => series.isRightToLeft,
    ReaderDirectionChoice.leftToRight => false,
    ReaderDirectionChoice.rightToLeft => true,
  };
}

/// 阅读区背景（UI-P1-5）。
///
/// `dynamic` 从当前页边缘提色，双页取两页的平均；墨水屏不提供这一项（固定白底）。
enum ReaderBackgroundChoice { black, white, dynamic, immersive }

/// 翻页动画（RDR-05）。
///
/// 四个档位对应"最真 → 最省"：卷页（着色器）→ 平移 → 淡入 → 瞬切。
/// 墨水屏与系统"减少动态效果"一律按瞬切处理，不看这个设置。
enum ReaderPageTurnChoice { curl, slide, fade, none }

/// 阅读设置的分组（RDR-04）。
///
/// 完整面板按这四组排，并且**每组可以单独重置**：用户调坏了"颜色"，
/// 不该把"布局"一起打回默认。
enum ReaderSettingsGroup { pages, layout, color, interaction }

/// 一组命名的阅读设置（UI-P3-1）。
///
/// 预设是一个**快照**：保存时的模式/适配/方向/背景/亮度/常亮，之后应用就整体覆盖。
/// `prefs` 本身不再带预设（避免递归），见 [ReaderPreset.fromJson]。
class ReaderPreset {
  const ReaderPreset({
    required this.id,
    required this.name,
    required this.prefs,
  });

  final String id;
  final String name;
  final ReaderPrefs prefs;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'prefs': prefs.toJson(includePresets: false),
  };

  /// 坏条目返回 null（旧存档/手工改坏），调用方直接跳过，不让整份偏好失效。
  static ReaderPreset? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final config = raw['prefs'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) {
      return null;
    }
    if (config is! Map) return null;
    final prefs = ReaderPrefs.fromJson(Map<String, Object?>.from(config))
        .configOnly();
    return ReaderPreset(id: id, name: name.trim(), prefs: prefs);
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderPreset &&
      other.id == id &&
      other.name == name &&
      other.prefs == prefs;

  @override
  int get hashCode => Object.hash(id, name, prefs);

  @override
  String toString() => 'ReaderPreset($id, $name)';
}

/// 阅读器偏好（全局，不分书）。
///
/// 为什么不分书：漫画是"一次读很多卷"的场景，每本都要重设模式反而烦；
/// 而"条漫 vs 单行本"的差异已经由系列元数据 + [ReaderModeChoice.auto] 兜住了。
class ReaderPrefs {
  const ReaderPrefs({
    this.mode = ReaderModeChoice.auto,
    this.brightness = 1,
    this.keepAwake = false,
    this.fit = ReaderFitChoice.contain,
    this.direction = ReaderDirectionChoice.auto,
    this.background = ReaderBackgroundChoice.black,
    this.lockZoom = false,
    this.trimBorders = false,
    this.pageTurn = ReaderPageTurnChoice.curl,
    this.spreadFrom = const <String, int>{},
    this.presets = const <ReaderPreset>[],
    this.seriesOverrides = const <String, ReaderPrefs>{},
  });

  /// 亮度下限：再暗也要能看见字，所以不允许 0。
  static const double minBrightness = 0.2;

  final ReaderModeChoice mode;

  /// 1 = 不遮罩；小于 1 时在阅读区上盖一层半透明黑。
  final double brightness;

  final bool keepAwake;

  final ReaderFitChoice fit;
  final ReaderDirectionChoice direction;
  final ReaderBackgroundChoice background;

  /// 翻页后保持缩放比例（UI-P3-4）。
  final bool lockZoom;

  /// 自动裁掉页图四周的纯色白边/黑边（UI-P3-10）。
  final bool trimBorders;

  /// 翻页动画（RDR-05）。
  final ReaderPageTurnChoice pageTurn;

  /// 双页模式的手动分组起点（RDR-06）：bookId → 0 基页码。
  ///
  /// 按**书**记：同一系列的不同卷可能排版不同；换书不会串。
  /// 不进预设/系列覆盖（[configOnly] 会丢掉它）——它是"这本书的排版修正"，
  /// 不是一套可复用的阅读风格。
  final Map<String, int> spreadFrom;

  /// 用户保存的阅读预设（UI-P3-1）；按保存顺序排列。
  final List<ReaderPreset> presets;

  /// 按系列覆盖的阅读设置（UI-P3-2）：seriesId → 纯配置。
  ///
  /// 值里不能带预设/覆盖（用 [configOnly] 生成），否则 JSON 会递归。
  final Map<String, ReaderPrefs> seriesOverrides;

  /// 把某一组设置恢复默认（RDR-04），其它组原样保留。
  ReaderPrefs resetGroup(ReaderSettingsGroup group) => switch (group) {
    ReaderSettingsGroup.pages => copyWith(mode: ReaderModeChoice.auto),
    ReaderSettingsGroup.layout => copyWith(
      fit: ReaderFitChoice.contain,
      direction: ReaderDirectionChoice.auto,
      trimBorders: false,
    ),
    ReaderSettingsGroup.color => copyWith(
      background: ReaderBackgroundChoice.black,
      brightness: 1,
    ),
    ReaderSettingsGroup.interaction => copyWith(
      lockZoom: false,
      keepAwake: false,
      pageTurn: ReaderPageTurnChoice.curl,
    ),
  };

  /// 这一组是不是已经是默认值（决定"重置"按钮要不要亮）。
  bool isGroupDefault(ReaderSettingsGroup group) => switch (group) {
    ReaderSettingsGroup.pages => mode == ReaderModeChoice.auto,
    ReaderSettingsGroup.layout =>
      fit == ReaderFitChoice.contain &&
          direction == ReaderDirectionChoice.auto &&
          !trimBorders,
    ReaderSettingsGroup.color =>
      background == ReaderBackgroundChoice.black && brightness == 1,
    ReaderSettingsGroup.interaction =>
      !lockZoom && !keepAwake && pageTurn == ReaderPageTurnChoice.curl,
  };

  /// 去掉预设与系列覆盖后的"纯配置"（保存预设/系列覆盖时用）。
  ReaderPrefs configOnly() => ReaderPrefs(
    mode: mode,
    brightness: brightness,
    keepAwake: keepAwake,
    fit: fit,
    direction: direction,
    background: background,
    lockZoom: lockZoom,
    trimBorders: trimBorders,
    pageTurn: pageTurn,
  );

  /// 某个系列实际生效的设置：有覆盖就用覆盖，否则用全局。
  ///
  /// 返回的对象仍带全局预设列表，方便设置面板继续读；系列覆盖本身不嵌套。
  ReaderPrefs forSeries(String? seriesId) {
    if (seriesId == null) return this;
    final override = seriesOverrides[seriesId];
    if (override == null) return this;
    return ReaderPrefs(
      mode: override.mode,
      brightness: override.brightness,
      keepAwake: override.keepAwake,
      fit: override.fit,
      direction: override.direction,
      background: override.background,
      lockZoom: override.lockZoom,
      trimBorders: override.trimBorders,
      pageTurn: override.pageTurn,
      spreadFrom: spreadFrom,
      presets: presets,
      seriesOverrides: seriesOverrides,
    );
  }

  /// 用 [config] 的**纯配置**覆盖本对象，预设列表与系列覆盖保持不变。
  ///
  /// "应用预设"和"应用系列覆盖"都走这里：字段清单只写一遍，
  /// 以后新增一个配置项就不可能只改到其中一条路径（FIX-04 曾漏掉锁定缩放/去白边）。
  ReaderPrefs withConfig(ReaderPrefs config) => copyWith(
    mode: config.mode,
    brightness: config.brightness,
    keepAwake: config.keepAwake,
    fit: config.fit,
    direction: config.direction,
    background: config.background,
    lockZoom: config.lockZoom,
    trimBorders: config.trimBorders,
  );

  /// 记住/清除某本书的双页分组起点（RDR-06）。[index] 为 null 表示恢复自动。
  ReaderPrefs withSpreadFrom(String bookId, int? index) {
    final next = Map<String, int>.of(spreadFrom);
    if (index == null || index < 0) {
      next.remove(bookId);
    } else {
      next[bookId] = index;
    }
    return copyWith(spreadFrom: next);
  }

  /// 写入/删除某个系列的覆盖。传入 null 表示删除。
  ReaderPrefs withSeriesOverride(String seriesId, ReaderPrefs? config) {
    final next = Map<String, ReaderPrefs>.from(seriesOverrides);
    if (config == null) {
      next.remove(seriesId);
    } else {
      next[seriesId] = config.configOnly();
    }
    return copyWith(seriesOverrides: next);
  }

  /// 遮罩的不透明度（亮度越低盖得越黑）。
  double get dimOpacity => (1 - brightness).clamp(0.0, 1 - minBrightness);

  ReaderPrefs copyWith({
    ReaderModeChoice? mode,
    double? brightness,
    bool? keepAwake,
    ReaderFitChoice? fit,
    ReaderDirectionChoice? direction,
    ReaderBackgroundChoice? background,
    bool? lockZoom,
    bool? trimBorders,
    ReaderPageTurnChoice? pageTurn,
    Map<String, int>? spreadFrom,
    List<ReaderPreset>? presets,
    Map<String, ReaderPrefs>? seriesOverrides,
  }) => ReaderPrefs(
    mode: mode ?? this.mode,
    brightness: brightness ?? this.brightness,
    keepAwake: keepAwake ?? this.keepAwake,
    fit: fit ?? this.fit,
    direction: direction ?? this.direction,
    background: background ?? this.background,
    lockZoom: lockZoom ?? this.lockZoom,
    trimBorders: trimBorders ?? this.trimBorders,
    pageTurn: pageTurn ?? this.pageTurn,
    spreadFrom: spreadFrom ?? this.spreadFrom,
    presets: presets ?? this.presets,
    seriesOverrides: seriesOverrides ?? this.seriesOverrides,
  );

  Map<String, Object?> toJson({bool includePresets = true}) =>
      <String, Object?>{
        'mode': mode.name,
        'brightness': brightness,
        'keepAwake': keepAwake,
        'fit': fit.name,
        'direction': direction.name,
        'background': background.name,
        'lockZoom': lockZoom,
        'trimBorders': trimBorders,
        'pageTurn': pageTurn.name,
        if (spreadFrom.isNotEmpty) 'spreadFrom': spreadFrom,
        if (includePresets && presets.isNotEmpty)
          'presets': <Object?>[for (final preset in presets) preset.toJson()],
        if (includePresets && seriesOverrides.isNotEmpty)
          'seriesOverrides': <String, Object?>{
            for (final entry in seriesOverrides.entries)
              entry.key: entry.value.toJson(includePresets: false),
          },
      };

  /// 存档可能被旧版本/手工改过，所有字段先判类型再取值，坏值一律回默认，
  /// 绝不让一条脏数据把阅读器变成黑屏或抛异常。
  static ReaderPrefs fromJson(Map<String, Object?> json) {
    final rawBrightness = json['brightness'];
    final brightness = rawBrightness is num
        ? rawBrightness.toDouble().clamp(minBrightness, 1.0)
        : 1.0;
    final rawPresets = json['presets'];
    final presets = <ReaderPreset>[];
    if (rawPresets is List) {
      for (final raw in rawPresets) {
        final preset = ReaderPreset.fromJson(raw);
        if (preset != null) presets.add(preset);
      }
    }
    final rawOverrides = json['seriesOverrides'];
    final overrides = <String, ReaderPrefs>{};
    if (rawOverrides is Map) {
      for (final entry in rawOverrides.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        overrides[entry.key as String] = ReaderPrefs.fromJson(
          Map<String, Object?>.from(entry.value as Map),
        ).configOnly();
      }
    }
    return ReaderPrefs(
      mode: _parse(
        json['mode'],
        ReaderModeChoice.values,
        ReaderModeChoice.auto,
      ),
      brightness: brightness,
      keepAwake: json['keepAwake'] == true,
      fit: _parse(json['fit'], ReaderFitChoice.values, ReaderFitChoice.contain),
      direction: _parse(
        json['direction'],
        ReaderDirectionChoice.values,
        ReaderDirectionChoice.auto,
      ),
      background: _parse(
        json['background'],
        ReaderBackgroundChoice.values,
        ReaderBackgroundChoice.black,
      ),
      lockZoom: json['lockZoom'] == true,
      trimBorders: json['trimBorders'] == true,
      pageTurn: _parse(
        json['pageTurn'],
        ReaderPageTurnChoice.values,
        ReaderPageTurnChoice.curl,
      ),
      spreadFrom: _parseSpreadFrom(json['spreadFrom']),
      presets: presets,
      seriesOverrides: overrides,
    );
  }

  /// 解析"每本书的分组起点"：只收非负 int，坏条目直接丢（存档可能被改坏）。
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

  /// 按名字解析枚举；不是已知名字（旧版本 / 手工改坏）就回默认值。
  static T _parse<T extends Enum>(Object? raw, List<T> values, T fallback) {
    if (raw is! String) return fallback;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderPrefs &&
      other.mode == mode &&
      other.brightness == brightness &&
      other.keepAwake == keepAwake &&
      other.fit == fit &&
      other.direction == direction &&
      other.background == background &&
      other.lockZoom == lockZoom &&
      other.trimBorders == trimBorders &&
      other.pageTurn == pageTurn &&
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
    Map<String, ReaderPrefs> a,
    Map<String, ReaderPrefs> b,
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
    mode,
    brightness,
    keepAwake,
    fit,
    direction,
    background,
    lockZoom,
    trimBorders,
    pageTurn,
    Object.hashAll(
      spreadFrom.entries.map(
        (MapEntry<String, int> e) => Object.hash(e.key, e.value),
      ),
    ),
    Object.hashAll(presets),
    Object.hashAll(
      seriesOverrides.entries.map(
        (MapEntry<String, ReaderPrefs> e) => Object.hash(e.key, e.value),
      ),
    ),
  );

  @override
  String toString() =>
      'ReaderPrefs(${mode.name}, $brightness, $keepAwake, ${fit.name}, '
      '${direction.name}, ${background.name}, lockZoom: $lockZoom, '
      'presets: ${presets.length}, '
      'series: ${seriesOverrides.length})';
}
