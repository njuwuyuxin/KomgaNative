import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/app_settings.dart';
import 'package:yomu/src/data/prefs_backup.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/providers/download_providers.dart';
import 'package:yomu/src/providers/pinned_series_provider.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu/src/providers/settings_provider.dart';

/// 设置备份与原子还原控制器（SET-02 / P1-5）。
///
/// 将多控制器串联读写从 `SettingsBackupSection` 移至 Provider 层，
/// 导入前先完整快照旧状态，任何一步持久化失败时回滚已提交部分，绝不留下半新半旧的设置。
final Provider<SettingsBackupController> settingsBackupControllerProvider =
    Provider<SettingsBackupController>(SettingsBackupController.new);

class SettingsBackupController {
  SettingsBackupController(this._ref);

  final Ref _ref;

  /// 导出当前阅读偏好、应用设置与置顶系列的 JSON 字符串。
  Future<String> exportJson() async {
    final backup = PrefsBackup.of(
      reader: _ref.read(readerPrefsProvider),
      settings: await _ref.read(settingsProvider.notifier).loadSnapshot(),
      pinnedSeries: await _ref
          .read(pinnedSeriesControllerProvider)
          .currentIds(),
    );
    return backup.encode();
  }

  /// 解析并原子还原备份 JSON；失败时回滚已写入的控制器并重新抛出异常。
  Future<void> importJson(String text) async {
    final backup = PrefsBackup.decode(text);
    final nextPrefs = backup.toReaderPrefs();
    final nextSettings = backup.toAppSettings();
    final nextPinned = backup.pinnedSeries;

    final prevPrefs = _ref.read(readerPrefsProvider);
    final prevSettings = await _ref
        .read(settingsProvider.notifier)
        .loadSnapshot();
    final prevPinned = nextPinned != null
        ? await _ref.read(pinnedSeriesControllerProvider).currentIds()
        : null;

    var appliedPrefs = false;
    var appliedSettings = false;
    try {
      await _ref.read(readerPrefsProvider.notifier).replaceAll(nextPrefs);
      appliedPrefs = true;

      await _ref.read(settingsProvider.notifier).replaceAll(nextSettings);
      appliedSettings = true;

      if (nextPinned != null) {
        await _ref.read(pinnedSeriesControllerProvider).replaceAll(nextPinned);
      }
      _ref.invalidate(downloadPolicyProvider);
    } on Object {
      await _rollback(
        appliedPrefs: appliedPrefs,
        appliedSettings: appliedSettings,
        prevPrefs: prevPrefs,
        prevSettings: prevSettings,
        prevPinned: prevPinned,
      );
      rethrow;
    }
  }

  Future<void> _rollback({
    required bool appliedPrefs,
    required bool appliedSettings,
    required ReaderPrefs prevPrefs,
    required AppSettings prevSettings,
    required List<String>? prevPinned,
  }) async {
    if (appliedSettings) {
      try {
        await _ref.read(settingsProvider.notifier).replaceAll(prevSettings);
      } on Object catch (error) {
        debugPrint(
          'SettingsBackupController: rollback settings failed: $error',
        );
      }
    }
    if (appliedPrefs) {
      try {
        await _ref.read(readerPrefsProvider.notifier).replaceAll(prevPrefs);
      } on Object catch (error) {
        debugPrint(
          'SettingsBackupController: rollback readerPrefs failed: $error',
        );
      }
    }
    if (prevPinned != null && appliedSettings) {
      try {
        await _ref.read(pinnedSeriesControllerProvider).replaceAll(prevPinned);
      } on Object catch (error) {
        debugPrint(
          'SettingsBackupController: rollback pinnedSeries failed: $error',
        );
      }
    }
    _ref.invalidate(downloadPolicyProvider);
  }
}
