import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/src/data/app_settings.dart';
import 'package:yomu/src/data/prefs_backup.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/data/reader_prefs_store.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/providers/pinned_series_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu/src/providers/settings_backup_controller.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';

/// P1-5：设置备份还原原子性测试——任一步骤失败必须把已写入的控制器回滚至旧状态。
void main() {
  test('importJson 在设置写入失败时回滚已修改的 readerPrefs（P1-5）', () async {
    final db = ProgressDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final prefsStore = InMemoryReaderPrefsStore(
      const ReaderPrefs(global: ReaderConfig(mode: ReaderModeChoice.single)),
    );
    final settingsStore = _FailOnSaveSettingsStore(
      const AppSettings(themeMode: ThemeMode.light),
    );

    final container = ProviderContainer(
      overrides: [
        progressDatabaseProvider.overrideWithValue(db),
        readerPrefsStoreProvider.overrideWithValue(prefsStore),
        settingsStoreProvider.overrideWithValue(settingsStore),
        serverStoreProvider.overrideWithValue(InMemoryServerStore()),
      ],
    );
    addTearDown(container.dispose);

    // 预热初始状态。
    container.read(readerPrefsProvider);
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);

    final incoming = PrefsBackup.of(
      reader: const ReaderPrefs(
        global: ReaderConfig(mode: ReaderModeChoice.vertical),
      ),
      settings: const AppSettings(themeMode: ThemeMode.dark),
      pinnedSeries: const <String>['s-new'],
    ).encode();

    // 触发 settingsStore.update 抛错。
    settingsStore.failNextUpdate = true;
    await expectLater(
      container.read(settingsBackupControllerProvider).importJson(incoming),
      throwsA(isA<StateError>()),
    );

    // readerPrefs 必须已回滚回旧值，绝不留下半新半旧状态。
    expect(
      container.read(readerPrefsProvider).global.mode,
      ReaderModeChoice.single,
    );
    expect(container.read(settingsProvider).themeMode, ThemeMode.light);
    expect(
      await container.read(pinnedSeriesControllerProvider).currentIds(),
      isEmpty,
    );
  });

  test(
    'importJson 成功时完整应用 readerPrefs、settings 与 pinnedSeries（P1-5）',
    () async {
      final db = ProgressDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final prefsStore = InMemoryReaderPrefsStore(
        const ReaderPrefs(global: ReaderConfig(mode: ReaderModeChoice.single)),
      );
      final settingsStore = InMemorySettingsStore(
        const AppSettings(themeMode: ThemeMode.light),
      );

      final container = ProviderContainer(
        overrides: [
          progressDatabaseProvider.overrideWithValue(db),
          readerPrefsStoreProvider.overrideWithValue(prefsStore),
          settingsStoreProvider.overrideWithValue(settingsStore),
          serverStoreProvider.overrideWithValue(InMemoryServerStore()),
        ],
      );
      addTearDown(container.dispose);

      container.read(readerPrefsProvider);
      container.read(settingsProvider);
      await Future<void>.delayed(Duration.zero);

      final incoming = PrefsBackup.of(
        reader: const ReaderPrefs(
          global: ReaderConfig(mode: ReaderModeChoice.double),
        ),
        settings: const AppSettings(themeMode: ThemeMode.dark, forceEink: true),
        pinnedSeries: const <String>['s-1', 's-2'],
      ).encode();

      await container
          .read(settingsBackupControllerProvider)
          .importJson(incoming);

      expect(
        container.read(readerPrefsProvider).global.mode,
        ReaderModeChoice.double,
      );
      expect(container.read(settingsProvider).themeMode, ThemeMode.dark);
      expect(container.read(settingsProvider).forceEink, isTrue);
      expect(
        await container.read(pinnedSeriesControllerProvider).currentIds(),
        <String>['s-1', 's-2'],
      );
    },
  );
}

final class _FailOnSaveSettingsStore extends InMemorySettingsStore {
  _FailOnSaveSettingsStore(super.initial);

  bool failNextUpdate = false;

  @override
  Future<void> update(AppSettings Function(AppSettings current) mutate) async {
    if (failNextUpdate) {
      failNextUpdate = false;
      throw StateError('simulated disk full');
    }
    return super.update(mutate);
  }
}
