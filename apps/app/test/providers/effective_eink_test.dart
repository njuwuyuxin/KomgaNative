import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/data/settings_store.dart';
import 'package:komga_native/src/providers/settings_provider.dart';

/// 固定初始状态的设置控制器：不读存储、不落盘，只供 provider 单测使用。
class _FixedSettings extends SettingsController {
  _FixedSettings(this._initial);

  final SettingsState _initial;

  @override
  SettingsState build() => _initial;
}

void main() {
  /// [detected] 为 null 表示"探测还没回来"（等价于首帧）。
  Future<ProviderContainer> makeContainer({
    bool forced = false,
    bool? detected,
  }) async {
    final container = ProviderContainer(
      overrides: <Override>[
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        settingsProvider.overrideWith(
          () => _FixedSettings(SettingsState(forceEink: forced)),
        ),
        if (detected != null)
          einkDetectedProvider.overrideWith((ref) async => detected),
      ],
    );
    addTearDown(container.dispose);
    if (detected != null) await container.read(einkDetectedProvider.future);
    return container;
  }

  group('effectiveEinkProvider', () {
    test('手动强制为真 → 墨水屏', () async {
      final container = await makeContainer(forced: true, detected: false);
      expect(container.read(effectiveEinkProvider), isTrue);
    });

    test('自动探测为真（没开强制）→ 墨水屏', () async {
      final container = await makeContainer(forced: false, detected: true);
      expect(container.read(effectiveEinkProvider), isTrue);
    });

    test('两者都为假 → 普通设备', () async {
      final container = await makeContainer(forced: false, detected: false);
      expect(container.read(effectiveEinkProvider), isFalse);
    });

    test('探测没回来时按普通设备处理，不阻塞首帧', () async {
      final container = await makeContainer(forced: false);
      expect(container.read(effectiveEinkProvider), isFalse);
    });

    test('强制开关变化会立刻反映到结果', () async {
      final container = ProviderContainer(
        overrides: <Override>[
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          settingsProvider.overrideWith(
            () => _FixedSettings(const SettingsState()),
          ),
          einkDetectedProvider.overrideWith((ref) async => false),
        ],
      );
      addTearDown(container.dispose);
      await container.read(einkDetectedProvider.future);
      expect(container.read(effectiveEinkProvider), isFalse);

      // provider 是派生的：强制开关一改就必须跟着变，否则主题和阅读器会不同步。
      container.read(settingsProvider.notifier).setForceEink(true);
      expect(container.read(effectiveEinkProvider), isTrue);
    });
  });
}
