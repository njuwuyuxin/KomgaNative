import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/data/app_settings.dart';
import 'package:komga_native/src/data/settings_store.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:material_ui/material_ui.dart';

/// 设置持久化（FIX-02）：主题、墨水屏、语言、触感都从同一个 blob 恢复/落盘，
/// 且各自写入不会冲掉别人。
void main() {
  Future<void> drain() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  ProviderContainer containerWith(SettingsStore store) {
    final container = ProviderContainer(
      overrides: <Override>[settingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('没有存档时用默认值', () {
    final container = containerWith(InMemorySettingsStore());
    final state = container.read(settingsProvider);
    expect(state.themeMode, ThemeMode.system);
    expect(state.forceEink, isFalse);
    expect(state.haptics, isTrue);
    expect(state.language, AppLanguage.system);
  });

  test('冷启动恢复主题 / 墨水屏 / 语言 / 触感', () async {
    final container = containerWith(
      InMemorySettingsStore(
        const AppSettings(
          themeMode: ThemeMode.dark,
          forceEink: true,
          language: 'zh',
          haptics: false,
        ),
      ),
    );
    container.read(settingsProvider);
    await drain();

    final state = container.read(settingsProvider);
    expect(state.themeMode, ThemeMode.dark);
    expect(state.forceEink, isTrue);
    expect(state.haptics, isFalse);
    expect(state.language, AppLanguage.zh);
  });

  test('未知语言存档回 system（跟随系统）', () async {
    final container = containerWith(
      InMemorySettingsStore(const AppSettings(language: 'klingon')),
    );
    container.read(settingsProvider);
    await drain();
    expect(container.read(settingsProvider).language, AppLanguage.system);
  });

  test('切换后落盘；恢复晚到也不会覆盖用户刚做的选择', () async {
    final store = InMemorySettingsStore(const AppSettings(language: 'zh'));
    final container = containerWith(store);
    final controller = container.read(settingsProvider.notifier);

    // 存档还没读回来就先动手：恢复不能把这两项打回默认。
    controller.setThemeMode(ThemeMode.light);
    controller.setForceEink(true);
    controller.setHaptics(false);
    await drain();

    final state = container.read(settingsProvider);
    expect(state.themeMode, ThemeMode.light);
    expect(state.forceEink, isTrue);
    expect(state.haptics, isFalse);
    // 没动过的语言照常恢复。
    expect(state.language, AppLanguage.zh);

    expect(store.settings.themeMode, ThemeMode.light);
    expect(store.settings.forceEink, isTrue);
    expect(store.settings.haptics, isFalse);
  });

  test('改一个字段不会把别的字段冲回旧值', () async {
    final store = InMemorySettingsStore(
      const AppSettings(themeMode: ThemeMode.dark, language: 'zh'),
    );
    final container = containerWith(store);
    await drain();

    container.read(settingsProvider.notifier).setHaptics(false);
    await drain();

    expect(store.settings.haptics, isFalse);
    expect(store.settings.themeMode, ThemeMode.dark);
    expect(store.settings.language, 'zh');
  });

  group('SecureSettingsStore', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

    test('写在一个 blob 里，读改写互不覆盖', () async {
      final store = SecureSettingsStore();
      await store.update(
        (AppSettings s) =>
            s.copyWith(language: 'zh', themeMode: ThemeMode.dark),
      );
      await store.update((AppSettings s) => s.copyWith(haptics: false));

      final loaded = await store.load();
      expect(loaded.language, 'zh');
      expect(loaded.themeMode, ThemeMode.dark);
      expect(loaded.haptics, isFalse);
    });

    test('旧存档（只有语言）其余字段回默认', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'komganative.settings.v1': '{"language":"zh"}',
      });
      final loaded = await SecureSettingsStore().load();
      expect(loaded.language, 'zh');
      expect(loaded.themeMode, ThemeMode.system);
      expect(loaded.haptics, isTrue);
      expect(loaded.view.name, 'grid');
    });

    test('坏存档 / 字段类型不对：都不抛错，逐字段回默认', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'komganative.settings.v1': '{"haptics":"yes","theme":42}',
      });
      final loaded = await SecureSettingsStore().load();
      expect(loaded.haptics, isTrue);
      expect(loaded.themeMode, ThemeMode.system);

      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'komganative.settings.v1': 'not json',
      });
      expect((await SecureSettingsStore().load()).themeMode, ThemeMode.system);

      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'komganative.settings.v1': '[1,2,3]',
      });
      expect((await SecureSettingsStore().load()).haptics, isTrue);
    });
  });
}
