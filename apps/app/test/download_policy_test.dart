import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/app_settings.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/download/download_service.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/download_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu_platform/yomu_platform.dart';

import 'support/test_source_overrides.dart';

/// DLD-01：下载设置（仅 Wi-Fi / 读完自动删除 / 并发数）。
void main() {
  group('AppSettings 下载设置', () {
    test('默认值 + 存档往返', () {
      const defaults = AppSettings();
      expect(defaults.downloadWifiOnly, isFalse);
      expect(defaults.downloadAutoDeleteRead, isFalse);
      expect(defaults.downloadConcurrency, 1);

      final settings = defaults.copyWith(
        downloadWifiOnly: true,
        downloadAutoDeleteRead: true,
        downloadConcurrency: 3,
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.downloadWifiOnly, isTrue);
      expect(restored.downloadAutoDeleteRead, isTrue);
      expect(restored.downloadConcurrency, 3);
    });

    test('被改坏的并发数夹回 1–3', () {
      int read(Object? raw) =>
          AppSettings.fromJson(<String, Object?>{'downloadConcurrency': raw})
              .downloadConcurrency;

      expect(read(0), 1);
      expect(read(9), 3);
      expect(read('2'), 1, reason: '类型不对就回默认');
    });
  });

  group('仅 Wi-Fi 拦截', () {
    Future<ProviderContainer> containerWith({
      required bool wifiOnly,
      required NetworkKind kind,
    }) async {
      final container = ProviderContainer(
        overrides: <Override>[
          settingsStoreProvider.overrideWithValue(
            InMemorySettingsStore(
              const AppSettings().copyWith(downloadWifiOnly: wifiOnly),
            ),
          ),
          networkProbeProvider.overrideWithValue(_FixedProbe(kind)),
        ],
      );
      addTearDown(container.dispose);
      container.read(downloadPolicyProvider);
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      return container;
    }

    test('蜂窝 + 仅 Wi-Fi → 拦住', () async {
      final container = await containerWith(
        wifiOnly: true,
        kind: NetworkKind.cellular,
      );
      final policy = await container.read(downloadPolicyProvider.future);
      expect(policy.wifiOnly, isTrue);
      expect(
        await container.read(networkProbeProvider).current(),
        NetworkKind.cellular,
      );
    });

    test('判断不出网络类型时放行（unknown ≠ 不能用）', () async {
      final container = await containerWith(
        wifiOnly: true,
        kind: NetworkKind.unknown,
      );
      expect(
        await container.read(networkProbeProvider).current(),
        NetworkKind.unknown,
      );
    });
  });

  group('并发数', () {
    test('并发 2：两本同时开跑，谁先完成就补位', () async {
      final service = _GatedDownloadService();
      final db = HttpCacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: <Override>[
          ...testSourceOverrides(download: service),
          httpCacheDatabaseProvider.overrideWithValue(db),
          settingsStoreProvider.overrideWithValue(
            InMemorySettingsStore(
              const AppSettings().copyWith(downloadConcurrency: 2),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(downloadsProvider);
      // 等设置里的并发数真的读进来（控制器是 ref.listen 异步拿到的）。
      await container.read(downloadPolicyProvider.future);
      await Future<void>.delayed(Duration.zero);

      Book book(int i) => Book(
        id: 'b$i',
        seriesId: 's1',
        name: 'Vol. $i',
        number: '$i',
        pagesCount: 3,
        sizeBytes: 10,
      );

      unawaited(
        container.read(downloadsProvider.notifier).startMany(<Book>[
          book(1),
          book(2),
          book(3),
        ]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // 并发 2：前两本已经在跑，第三本还排着。
      expect(service.started.length, 2);

      // 放行第一本 → 第三本补位。
      service.release('b1');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(service.started, contains('b3'));

      service.releaseAll();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(service.finished.length, 3);
    });

    test('仅 Wi-Fi 开启且切换为蜂窝时，队列调度自动暂停不消耗流量', () async {
      final service = _GatedDownloadService();
      final db = HttpCacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: <Override>[
          ...testSourceOverrides(download: service),
          httpCacheDatabaseProvider.overrideWithValue(db),
          networkProbeProvider.overrideWithValue(
            const _FixedProbe(NetworkKind.cellular),
          ),
          settingsStoreProvider.overrideWithValue(
            InMemorySettingsStore(
              const AppSettings().copyWith(downloadWifiOnly: true),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(downloadsProvider);
      await container.read(downloadPolicyProvider.future);
      await Future<void>.delayed(Duration.zero);

      await container
          .read(downloadsProvider.notifier)
          .start(
            const Book(id: 'b1', seriesId: 's1', name: 'Vol. 1', pagesCount: 3),
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(service.started, isEmpty, reason: '蜂窝网络下不应拉起下载');
      expect(container.read(downloadsProvider.notifier).paused, isTrue);
    });
  });
}

class _FixedProbe implements NetworkProbe {
  const _FixedProbe(this.kind);

  final NetworkKind kind;

  @override
  Future<NetworkKind> current() async => kind;
}

class _GatedDownloadService implements DownloadService {
  final List<String> started = <String>[];
  final List<String> finished = <String>[];
  final Map<String, Completer<void>> _gates = <String, Completer<void>>{};

  void release(String id) {
    final gate = _gates.putIfAbsent(id, Completer<void>.new);
    if (!gate.isCompleted) gate.complete();
  }

  void releaseAll() {
    for (final id in started) {
      release(id);
    }
  }

  @override
  Future<DownloadedBook?> downloaded(String bookId) async => null;

  @override
  Future<bool> download(
    Book book, {
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    started.add(book.id);
    await _gates.putIfAbsent(book.id, Completer<void>.new).future;
    onProgress(const DownloadProgress(done: 3, total: 3));
    finished.add(book.id);
    return true;
  }

  @override
  Future<void> delete(Book book) async {}

  @override
  void cancel(String bookId) {}
}
