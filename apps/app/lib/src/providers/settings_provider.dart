import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/data/app_settings.dart';
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
  /// 恢复是异步的：如果用户已经手动改过某一项，不能被旧存档覆盖回去。
  /// 每项单独记，避免"先改了主题"把还没恢复的墨水屏开关一起挡掉。
  bool _themeTouched = false;
  bool _einkTouched = false;
  bool _languageTouched = false;
  bool _hapticsTouched = false;

  @override
  SettingsState build() {
    unawaited(_restore());
    return const SettingsState();
  }

  SettingsStore get _store => ref.read(settingsStoreProvider);

  Future<void> _restore() async {
    final saved = await _store.load();
    final nextHaptics = _hapticsTouched ? state.haptics : saved.haptics;
    AppHaptics.enabled = nextHaptics;
    state = state.copyWith(
      themeMode: _themeTouched ? null : saved.themeMode,
      forceEink: _einkTouched ? null : saved.forceEink,
      language: _languageTouched ? null : appLanguageFromCode(saved.language),
      haptics: nextHaptics,
    );
  }

  /// 整份替换（SET-02 导入备份）。
  ///
  /// 四个"用户手动改过"的标记一并置位：导入之后不该再被异步恢复覆盖。
  Future<void> replaceAll(AppSettings next) async {
    _themeTouched = true;
    _einkTouched = true;
    _languageTouched = true;
    _hapticsTouched = true;
    await _store.update((AppSettings _) => next);
    AppHaptics.enabled = next.haptics;
    state = state.copyWith(
      themeMode: next.themeMode,
      forceEink: next.forceEink,
      language: appLanguageFromCode(next.language),
      haptics: next.haptics,
    );
  }

  void setThemeMode(ThemeMode mode) {
    if (mode == state.themeMode) return;
    _themeTouched = true;
    state = state.copyWith(themeMode: mode);
    unawaited(_store.update((AppSettings s) => s.copyWith(themeMode: mode)));
  }

  void setForceEink(bool value) {
    if (value == state.forceEink) return;
    _einkTouched = true;
    state = state.copyWith(forceEink: value);
    unawaited(_store.update((AppSettings s) => s.copyWith(forceEink: value)));
  }

  void setLanguage(AppLanguage language) {
    if (language == state.language) return;
    _languageTouched = true;
    state = state.copyWith(language: language);
    unawaited(
      _store.update((AppSettings s) => s.copyWith(language: language.code)),
    );
  }

  void setHaptics(bool enabled) {
    if (enabled == state.haptics) return;
    _hapticsTouched = true;
    AppHaptics.enabled = enabled;
    state = state.copyWith(haptics: enabled);
    unawaited(_store.update((AppSettings s) => s.copyWith(haptics: enabled)));
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

/// 本机是否按墨水屏渲染：手动强制 **或** 自动探测。
///
/// 这是"是不是墨水屏"的**唯一**来源：全局主题、阅读器配色、翻页动画、
/// 动态背景、开场 Hero 都读它。
///
/// 之前各页面分别读 `settings.forceEink`，自动探测出来的机型只换了主题，
/// 阅读器仍是黑底/卷页/动态背景（FIX-01）。把判断收成一个 provider 后，
/// 新增墨水屏相关行为只需要 watch 一次，不会再漏。
///
/// 探测是异步的：首帧拿不到结果时按彩色处理，绝不能为了等探测卡住启动。
final Provider<bool> effectiveEinkProvider = Provider<bool>((Ref ref) {
  final forced = ref.watch(settingsProvider.select((s) => s.forceEink));
  final detected = ref.watch(einkDetectedProvider).value ?? false;
  return forced || detected;
});
