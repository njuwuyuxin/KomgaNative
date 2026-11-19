import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_native/src/data/settings_store.dart';
import 'package:komga_platform/komga_platform.dart';
import 'package:material_ui/material_ui.dart';

/// 界面语言。
///
/// `system` 表示跟随系统（交给 MaterialApp 的 locale 解析），
/// 不是"英文"：系统是中文时就应该显示中文。
enum AppLanguage { system, en, zh }

extension AppLanguageX on AppLanguage {
  /// 传给 `MaterialApp.locale` 的值；null = 跟随系统。
  Locale? get locale => switch (this) {
    AppLanguage.system => null,
    AppLanguage.en => const Locale('en'),
    AppLanguage.zh => const Locale('zh'),
  };

  /// 存档里的编码（也是 ARB 的 locale 名）。
  String get code => switch (this) {
    AppLanguage.system => 'system',
    AppLanguage.en => 'en',
    AppLanguage.zh => 'zh',
  };
}

/// 从存档解析语言：不认识的值（旧版本/手工改过/乱码）一律回 system。
AppLanguage appLanguageFromCode(String? code) => switch (code) {
  'en' => AppLanguage.en,
  'zh' => AppLanguage.zh,
  _ => AppLanguage.system,
};

/// 外观设置。
class SettingsState {
  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.forceEink = false,
    this.language = AppLanguage.system,
    this.haptics = true,
  });

  final ThemeMode themeMode;

  /// 手动强制墨水屏档位（真机探测在 M5 接入）。
  final bool forceEink;

  final AppLanguage language;

  /// 触感反馈（默认开启）。墨水屏也保留：它不影响屏幕刷新。
  final bool haptics;

  SettingsState copyWith({
    ThemeMode? themeMode,
    bool? forceEink,
    AppLanguage? language,
    bool? haptics,
  }) => SettingsState(
    themeMode: themeMode ?? this.themeMode,
    forceEink: forceEink ?? this.forceEink,
    language: language ?? this.language,
    haptics: haptics ?? this.haptics,
  );
}

class SettingsController extends Notifier<SettingsState> {
  /// 恢复是异步的：如果用户已经手动选过语言，不能被旧存档覆盖回去。
  bool _languageTouched = false;
  bool _hapticsTouched = false;

  @override
  SettingsState build() {
    unawaited(_restore());
    return const SettingsState();
  }

  SettingsStore get _store => ref.read(settingsStoreProvider);

  Future<void> _restore() async {
    try {
      final saved = await _store.loadLanguage();
      final haptics = await _store.loadHaptics();
      state = state.copyWith(
        language: _languageTouched ? null : appLanguageFromCode(saved),
        haptics: _hapticsTouched ? null : haptics,
      );
    } on Object {
      // 设置存储读失败就用默认值：不能让钥匙串问题挡住启动。
    }
  }

  void setThemeMode(ThemeMode mode) => state = state.copyWith(themeMode: mode);

  void setForceEink(bool value) => state = state.copyWith(forceEink: value);

  void setLanguage(AppLanguage language) {
    if (language == state.language) return;
    _languageTouched = true;
    state = state.copyWith(language: language);
    unawaited(_store.saveLanguage(language.code));
  }

  void setHaptics(bool enabled) {
    if (enabled == state.haptics) return;
    _hapticsTouched = true;
    state = state.copyWith(haptics: enabled);
    unawaited(_store.saveHaptics(enabled));
  }
}

final Provider<SettingsStore> settingsStoreProvider = Provider<SettingsStore>(
  (Ref ref) => SecureSettingsStore(),
);

final NotifierProvider<SettingsController, SettingsState> settingsProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);

/// 设备是不是墨水屏（UI-P3-14）。
///
/// Android 原生侧按厂商/型号做保守探测；没有实现（iOS/测试）时 [EinkProbe]
/// 返回 unknown → false。探测失败只会让主题保持彩色，不阻塞启动。
final FutureProvider<bool> einkDetectedProvider = FutureProvider<bool>((
  Ref ref,
) async {
  final info = await EinkProbe().detect();
  return info.isEink;
});
