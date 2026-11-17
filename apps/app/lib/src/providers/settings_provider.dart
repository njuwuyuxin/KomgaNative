import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 外观设置。
class SettingsState {
  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.forceEink = false,
  });

  final ThemeMode themeMode;

  /// 手动强制墨水屏档位（真机探测在 M5 接入）。
  final bool forceEink;

  SettingsState copyWith({ThemeMode? themeMode, bool? forceEink}) =>
      SettingsState(
        themeMode: themeMode ?? this.themeMode,
        forceEink: forceEink ?? this.forceEink,
      );
}

class SettingsController extends Notifier<SettingsState> {
  @override
  SettingsState build() => const SettingsState();

  void setThemeMode(ThemeMode mode) => state = state.copyWith(themeMode: mode);

  void setForceEink(bool value) => state = state.copyWith(forceEink: value);
}

final NotifierProvider<SettingsController, SettingsState> settingsProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);
