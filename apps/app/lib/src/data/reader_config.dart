import 'package:yomu/src/data/reader_choices.dart';
import 'package:yomu_reader/yomu_reader.dart';

export 'package:yomu/src/data/reader_choices.dart';

/// 不可变纯阅读配置值对象（ARC-04）。
///
/// 承载所有可随「命名预设」与「按系列覆盖」完整快照的参数，本身不含预设列表、
/// 系列覆盖字典或按书分组起点，从类型层面根除原型拷贝字段漂移与递归嵌套。
class ReaderConfig {
  const ReaderConfig({
    this.mode = ReaderModeChoice.auto,
    this.brightness = 1,
    this.keepAwake = false,
    this.fit = ReaderFitChoice.contain,
    this.direction = ReaderDirectionChoice.auto,
    this.background = ReaderBackgroundChoice.black,
    this.lockZoom = false,
    this.trimBorders = false,
    this.splitWidePages = WidePageSplitMode.off,
    this.pageTurn = ReaderPageTurnChoice.curl,
    this.tapZone = TapZonePreset.automatic,
    this.invertTapZones = false,
    this.doubleTapZoom = true,
    this.autoScrollSpeed = 5,
    this.showSessionTime = true,
  });

  /// 亮度下限：再暗也要能看见字，所以不允许 0。
  static const double minBrightness = 0.2;

  final ReaderModeChoice mode;
  final double brightness;
  final bool keepAwake;
  final ReaderFitChoice fit;
  final ReaderDirectionChoice direction;
  final ReaderBackgroundChoice background;
  final bool lockZoom;
  final bool trimBorders;
  final WidePageSplitMode splitWidePages;
  final ReaderPageTurnChoice pageTurn;
  final TapZonePreset tapZone;
  final bool invertTapZones;
  final bool doubleTapZoom;
  final int autoScrollSpeed;
  final bool showSessionTime;

  /// 遮罩的不透明度（亮度越低盖得越黑）。
  double get dimOpacity => (1 - brightness).clamp(0.0, 1 - minBrightness);

  /// 把某一组设置恢复默认（RDR-04），其它组原样保留。
  ReaderConfig resetGroup(ReaderSettingsGroup group) => switch (group) {
    ReaderSettingsGroup.pages => copyWith(mode: ReaderModeChoice.auto),
    ReaderSettingsGroup.layout => copyWith(
      fit: ReaderFitChoice.contain,
      direction: ReaderDirectionChoice.auto,
      trimBorders: false,
      splitWidePages: WidePageSplitMode.off,
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
          !trimBorders &&
          splitWidePages == WidePageSplitMode.off,
    ReaderSettingsGroup.color =>
      background == ReaderBackgroundChoice.black && brightness == 1,
    ReaderSettingsGroup.interaction =>
      !lockZoom && !keepAwake && pageTurn == ReaderPageTurnChoice.curl,
  };

  ReaderConfig copyWith({
    ReaderModeChoice? mode,
    double? brightness,
    bool? keepAwake,
    ReaderFitChoice? fit,
    ReaderDirectionChoice? direction,
    ReaderBackgroundChoice? background,
    bool? lockZoom,
    bool? trimBorders,
    WidePageSplitMode? splitWidePages,
    ReaderPageTurnChoice? pageTurn,
    TapZonePreset? tapZone,
    bool? invertTapZones,
    bool? doubleTapZoom,
    int? autoScrollSpeed,
    bool? showSessionTime,
  }) => ReaderConfig(
    mode: mode ?? this.mode,
    brightness: brightness ?? this.brightness,
    keepAwake: keepAwake ?? this.keepAwake,
    fit: fit ?? this.fit,
    direction: direction ?? this.direction,
    background: background ?? this.background,
    lockZoom: lockZoom ?? this.lockZoom,
    trimBorders: trimBorders ?? this.trimBorders,
    splitWidePages: splitWidePages ?? this.splitWidePages,
    pageTurn: pageTurn ?? this.pageTurn,
    tapZone: tapZone ?? this.tapZone,
    invertTapZones: invertTapZones ?? this.invertTapZones,
    doubleTapZoom: doubleTapZoom ?? this.doubleTapZoom,
    autoScrollSpeed: (autoScrollSpeed ?? this.autoScrollSpeed).clamp(1, 10),
    showSessionTime: showSessionTime ?? this.showSessionTime,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.name,
    'brightness': brightness,
    'keepAwake': keepAwake,
    'fit': fit.name,
    'direction': direction.name,
    'background': background.name,
    'lockZoom': lockZoom,
    'trimBorders': trimBorders,
    'splitWidePages': splitWidePages.name,
    'pageTurn': pageTurn.name,
    'tapZone': tapZone.name,
    'invertTapZones': invertTapZones,
    'doubleTapZoom': doubleTapZoom,
    'autoScrollSpeed': autoScrollSpeed,
    'showSessionTime': showSessionTime,
  };

  static ReaderConfig fromJson(Map<String, Object?> json) {
    final rawBrightness = json['brightness'];
    final brightness = rawBrightness is num
        ? rawBrightness.toDouble().clamp(minBrightness, 1.0)
        : 1.0;
    return ReaderConfig(
      mode: parseReaderEnum(
        json['mode'],
        ReaderModeChoice.values,
        ReaderModeChoice.auto,
      ),
      brightness: brightness,
      keepAwake: json['keepAwake'] == true,
      fit: parseReaderEnum(
        json['fit'],
        ReaderFitChoice.values,
        ReaderFitChoice.contain,
      ),
      direction: parseReaderEnum(
        json['direction'],
        ReaderDirectionChoice.values,
        ReaderDirectionChoice.auto,
      ),
      background: parseReaderEnum(
        json['background'],
        ReaderBackgroundChoice.values,
        ReaderBackgroundChoice.black,
      ),
      lockZoom: json['lockZoom'] == true,
      trimBorders: json['trimBorders'] == true,
      splitWidePages: parseReaderEnum(
        json['splitWidePages'],
        WidePageSplitMode.values,
        WidePageSplitMode.off,
      ),
      pageTurn: parseReaderEnum(
        json['pageTurn'],
        ReaderPageTurnChoice.values,
        ReaderPageTurnChoice.curl,
      ),
      tapZone: parseReaderEnum(
        json['tapZone'],
        TapZonePreset.values,
        TapZonePreset.automatic,
      ),
      invertTapZones: json['invertTapZones'] == true,
      doubleTapZoom: json['doubleTapZoom'] != false,
      autoScrollSpeed:
          (json['autoScrollSpeed'] is int ? json['autoScrollSpeed']! as int : 5)
              .clamp(1, 10),
      showSessionTime: json['showSessionTime'] != false,
    );
  }

  List<Object?> get _props => <Object?>[
    mode,
    brightness,
    keepAwake,
    fit,
    direction,
    background,
    lockZoom,
    trimBorders,
    splitWidePages,
    pageTurn,
    tapZone,
    invertTapZones,
    doubleTapZoom,
    autoScrollSpeed,
    showSessionTime,
  ];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ReaderConfig) return false;
    final a = _props;
    final b = other._props;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_props);

  @override
  String toString() =>
      'ReaderConfig(${mode.name}, $brightness, $keepAwake, ${fit.name}, '
      '${direction.name}, ${background.name}, lockZoom: $lockZoom)';
}
