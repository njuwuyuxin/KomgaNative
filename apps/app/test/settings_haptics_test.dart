import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/data/settings_store.dart';
import 'package:komga_native/src/providers/settings_provider.dart';

/// 触感反馈设置：默认开启、恢复存档、切换落盘、与语言字段互不覆盖。
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

  test('默认开启；存档里关掉就恢复为关', () async {
    expect(
      containerWith(InMemorySettingsStore()).read(settingsProvider).haptics,
      isTrue,
    );

    final container = containerWith(InMemorySettingsStore(null, false));
    container.read(settingsProvider);
    await drain();
    expect(container.read(settingsProvider).haptics, isFalse);
  });

  test('切换后落盘；恢复晚到也不会覆盖用户刚做的选择', () async {
    final store = InMemorySettingsStore('zh', true);
    final container = containerWith(store);
    container.read(settingsProvider.notifier).setHaptics(false);
    await drain();
    expect(container.read(settingsProvider).haptics, isFalse);
    expect(store.haptics, isFalse);
    // 语言照常恢复。
    expect(container.read(settingsProvider).language, AppLanguage.zh);
  });

  group('SecureSettingsStore', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

    test('语言与触感反馈写在同一个 blob 里，互不覆盖', () async {
      final store = SecureSettingsStore();
      await store.saveLanguage('zh');
      await store.saveHaptics(false);
      expect(await store.loadLanguage(), 'zh');
      expect(await store.loadHaptics(), isFalse);

      await store.saveLanguage('en');
      expect(await store.loadHaptics(), isFalse);
    });

    test('旧存档（只有语言）与坏存档：触感反馈为 null（按默认开启）', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'komganative.settings.v1': '{"language":"zh"}',
      });
      expect(await SecureSettingsStore().loadHaptics(), isNull);
      expect(await SecureSettingsStore().loadLanguage(), 'zh');

      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'komganative.settings.v1': '{"haptics":"yes"}',
      });
      expect(await SecureSettingsStore().loadHaptics(), isNull);

      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'komganative.settings.v1': 'not json',
      });
      expect(await SecureSettingsStore().loadHaptics(), isNull);
    });
  });
}
