import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/app_settings.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/data/shelf_filter_preset.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';

import 'support/fake_library.dart';

/// LIB-04：保存的筛选组合（排序 + 阅读状态 + 库），按服务器分区。
void main() {
  group('ShelfFilterPreset', () {
    test('JSON 往返', () {
      const preset = ShelfFilterPreset(
        id: 'p1',
        name: '未读漫画',
        sort: SeriesSort.booksCountDesc,
        readStatus: SeriesReadStatus.unread,
        libraryId: 'l2',
      );
      expect(ShelfFilterPreset.fromJson(preset.toJson()), preset);
    });

    test('坏条目返回 null，好条目照常解析', () {
      expect(ShelfFilterPreset.fromJson('nope'), isNull);
      expect(ShelfFilterPreset.fromJson(<String, Object?>{'id': 'x'}), isNull);
      expect(
        ShelfFilterPreset.fromJson(<String, Object?>{
          'id': 'p1',
          'name': 'A',
          'sort': 'removedSort',
        })?.sort,
        isNull,
        reason: '认不出的枚举回 null，不影响这条本身',
      );
      expect(
        const ShelfFilterPreset(id: 'p', name: 'n').isEmpty,
        isTrue,
        reason: '三项都空 = 没有筛选',
      );
    });
  });

  group('AppSettings.filterPresets', () {
    test('按服务器分区，切服务器不串', () {
      final settings = const AppSettings()
          .withPreset(
            'a',
            const ShelfFilterPreset(
              id: 'p1',
              name: 'A',
              sort: SeriesSort.titleAsc,
            ),
          )
          .withPreset(
            'b',
            const ShelfFilterPreset(
              id: 'p2',
              name: 'B',
              sort: SeriesSort.titleDesc,
            ),
          );

      expect(settings.presetsFor('a').single.name, 'A');
      expect(settings.presetsFor('b').single.name, 'B');
      expect(settings.presetsFor('c'), isEmpty);
      expect(settings.presetsFor(null), isEmpty);
    });

    test('同 id 覆盖、最多 8 条', () {
      var settings = const AppSettings();
      for (var i = 0; i < 10; i++) {
        settings = settings.withPreset(
          'a',
          ShelfFilterPreset(id: 'p$i', name: 'P$i'),
        );
      }
      expect(settings.presetsFor('a').length, 8);
      expect(settings.presetsFor('a').first.name, 'P9');

      settings = settings.withPreset(
        'a',
        const ShelfFilterPreset(id: 'p9', name: 'P9 renamed'),
      );
      expect(settings.presetsFor('a').length, 8, reason: '同 id 覆盖不新增');
      expect(settings.presetsFor('a').first.name, 'P9 renamed');
    });

    test('删除只删一条，最后一条删完就不留空列表', () {
      var settings = const AppSettings()
          .withPreset('a', const ShelfFilterPreset(id: 'p1', name: 'A'))
          .withPreset('a', const ShelfFilterPreset(id: 'p2', name: 'B'));

      settings = settings.withoutPreset('a', 'p1');
      expect(settings.presetsFor('a').single.id, 'p2');

      settings = settings.withoutPreset('a', 'p2');
      expect(settings.presetsFor('a'), isEmpty);
      expect(settings.toJson().containsKey('filterPresets'), isFalse);
    });

    test('存档往返：坏条目被丢弃，其它保留', () {
      final settings = const AppSettings().withPreset(
        'a',
        const ShelfFilterPreset(
          id: 'p1',
          name: 'A',
          readStatus: SeriesReadStatus.read,
        ),
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.presetsFor('a').single.readStatus, SeriesReadStatus.read);

      final broken = AppSettings.fromJson(const <String, Object?>{
        'filterPresets': <String, Object?>{
          'a': <Object?>[
            <String, Object?>{'id': 'ok', 'name': 'OK'},
            <String, Object?>{'id': 42},
            'garbage',
          ],
          'b': 'not a list',
        },
      });
      expect(broken.presetsFor('a').single.id, 'ok');
      expect(broken.presetsFor('b'), isEmpty);
    });
  });

  group('书架控制器', () {
    late FakeLibraryRepository repository;
    late InMemorySettingsStore store;

    Future<ProviderContainer> container() async {
      repository = FakeLibraryRepository(series: demoShelf());
      store = InMemorySettingsStore();
      final c = ProviderContainer(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(repository),
          settingsStoreProvider.overrideWithValue(store),
          // 筛选组合按服务器分区：给一个连接好的会话，key 才不是 null。
          sessionProvider.overrideWith(
            () => _ConnectedSession(
              StoredServer(
                address: ServerAddress.parse('http://test.local'),
                apiKey: 'k',
                accountEmail: 'a@b.c',
                accountId: 'u1',
              ),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.read(shelfProvider);
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      return c;
    }

    test('保存 → 应用 → 删除', () async {
      final c = await container();
      final controller = c.read(shelfProvider.notifier);

      controller.setSort(SeriesSort.booksCountDesc);
      controller.setReadStatus(SeriesReadStatus.unread);
      await Future<void>.delayed(Duration.zero);

      controller.savePreset('未读');
      await Future<void>.delayed(Duration.zero);

      final saved = c.read(shelfProvider).presets;
      expect(saved.single.name, '未读');
      expect(saved.single.sort, SeriesSort.booksCountDesc);
      expect(saved.single.readStatus, SeriesReadStatus.unread);
      expect(
        store.settings.presetsFor(null),
        isEmpty,
        reason: '没会话时按 null key 不写',
      );

      // 清空筛选后应用这条组合：三项一起回来。
      controller.setSort(null);
      controller.setReadStatus(null);
      await Future<void>.delayed(Duration.zero);
      controller.applyPreset(saved.single);
      await Future<void>.delayed(Duration.zero);

      expect(c.read(shelfProvider).sort, SeriesSort.booksCountDesc);
      expect(c.read(shelfProvider).readStatus, SeriesReadStatus.unread);

      controller.deletePreset(saved.single.id);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(shelfProvider).presets, isEmpty);
    });

    test('空名字 / 无筛选条件时什么都不存', () async {
      final c = await container();
      final controller = c.read(shelfProvider.notifier);

      controller.savePreset('   ');
      controller.savePreset('名字');
      await Future<void>.delayed(Duration.zero);

      expect(c.read(shelfProvider).presets, isEmpty);
    });
  });
}

/// 一个"已连接"的会话替身：只为了让按服务器分区的 key 不为 null。
class _ConnectedSession extends SessionController {
  _ConnectedSession(this._server);

  final StoredServer _server;

  @override
  SessionState build() => SessionConnected(_server);
}
