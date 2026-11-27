import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/data/cache/drift_http_cache.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/progress/progress_store.dart';
import 'package:yomu/src/data/progress/progress_sync_service.dart';
import 'package:yomu/src/data/reader_prefs_store.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/cross_source_reading_provider.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/screens/reader_screen.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_sync/yomu_sync.dart';

import 'support/fake_library.dart';
import 'support/fake_reader.dart';
import 'support/fakes.dart';

class _FixedSession extends SessionController {
  _FixedSession(this._initial);
  final SessionState _initial;

  @override
  SessionState build() => _initial;
}

void main() {
  group('P3 懒加载、selectSource、删除服务器清理与领域解耦', () {
    test(
      'ActiveSourceController 与 crossSourceOndeckProvider 保持真懒加载：不给休眠服务器建会话',
      () async {
        const keyA = 'https://a.p3.test';
        const keyB = 'https://b.p3.test';
        final resolvedKeys = <String>[];
        final localLib = FakeLibraryRepository();
        final libA = FakeLibraryRepository();
        final libB = FakeLibraryRepository();

        final registry = SourceRegistry.lazy(
          localBundle: SourceBundle(
            source: const LocalContentSource(),
            library: localLib,
            reader: FakeReaderRepository(),
            collections: localLib,
            readStatus: localLib,
          ),
          remoteSources: const <RemoteContentSource>[
            RemoteContentSource(sourceKey: keyA, displayName: 'Server A'),
            RemoteContentSource(sourceKey: keyB, displayName: 'Server B'),
          ],
          resolveRemote: (String key) {
            resolvedKeys.add(key);
            final lib = key == keyA ? libA : libB;
            return SourceBundle(
              source: RemoteContentSource(sourceKey: key, displayName: key),
              library: lib,
              reader: FakeReaderRepository(),
              collections: lib,
              readStatus: lib,
            );
          },
        );

        final container = ProviderContainer(
          overrides: <Override>[
            sourceRegistryProvider.overrideWithValue(registry),
            settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
            serverStoreProvider.overrideWithValue(InMemoryServerStore()),
            sessionProvider.overrideWith(
              () => _FixedSession(const SessionDisconnected()),
            ),
          ],
        );
        addTearDown(container.dispose);

        // 1) 在本机分组下打开首页「正在读」：绝不能触发任何休眠服务器的 resolveRemote。
        await container.read(crossSourceOndeckProvider.future);
        expect(resolvedKeys, isEmpty);

        // 2) ActiveSourceController.selectSource 只拿描述符，也不应触发 resolveRemote。
        await container.read(activeSourceProvider.notifier).selectSource(keyA);
        expect(container.read(activeSourceProvider).sourceKey, keyA);
        expect(resolvedKeys, isEmpty);

        // 3) 切到 A 源后刷新首页「正在读」：仅解析激活的 A，休眠的 B 仍不被创建。
        container.invalidate(crossSourceOndeckProvider);
        await container.read(crossSourceOndeckProvider.future);
        expect(resolvedKeys, <String>[keyA]);
      },
    );

    test('selectSource 在服务器列表尚未加载完时记住选择，注册表就绪后立即生效无需冷启动', () async {
      final serverA = StoredServer(
        address: ServerAddress.parse('https://late.p3.test'),
        apiKey: 'k',
        accountEmail: 'a@test.com',
      );
      final listCompleter = Completer<List<StoredServer>>();
      final settingsStore = InMemorySettingsStore();

      final container = ProviderContainer(
        overrides: <Override>[
          settingsStoreProvider.overrideWithValue(settingsStore),
          serverStoreProvider.overrideWithValue(InMemoryServerStore()),
          sessionProvider.overrideWith(
            () => _FixedSession(const SessionDisconnected()),
          ),
          serverListProvider.overrideWith((Ref ref) => listCompleter.future),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen<ContentSource>(
        activeSourceProvider,
        (ContentSource? _, ContentSource _) {},
      );
      addTearDown(sub.close);

      // 服务器列表加载前主动切到 serverA：写入持久化，当前源暂为本机。
      await container
          .read(activeSourceProvider.notifier)
          .selectSource(serverA.id);
      expect((await settingsStore.load()).activeSourceKey, serverA.id);

      // 注册表就绪后自动对齐到 serverA，无需冷启动。
      listCompleter.complete(<StoredServer>[serverA]);
      await container.read(serverListProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(activeSourceProvider).sourceKey, serverA.id);
    });

    test('removeServer 删除服务器时彻底清理该分区的 outbox 与本地进度，不影响其他源', () async {
      final serverA = StoredServer(
        address: ServerAddress.parse('https://del-a.p3.test'),
        apiKey: 'ka',
        accountEmail: 'a@test.com',
      );
      final serverB = StoredServer(
        address: ServerAddress.parse('https://keep-b.p3.test'),
        apiKey: 'kb',
        accountEmail: 'b@test.com',
      );
      final serverStore = InMemoryServerStore.withAll(<StoredServer>[
        serverA,
        serverB,
      ]);
      final progressStore = InMemoryProgressStore();
      await progressStore.enqueue(
        const ProgressTarget(bookId: 'b1', page: 7, completed: false),
        scope: serverA.id,
      );
      await progressStore.enqueue(
        const ProgressTarget(bookId: 'b2', page: 3, completed: false),
        scope: serverB.id,
      );
      await progressStore.forceAdopt(
        'local-b1',
        ReadProgress(
          page: 4,
          completed: false,
          lastModified: DateTime.utc(2026, 11, 27),
        ),
        scope: kLocalSourceKey,
      );

      final container = ProviderContainer(
        overrides: <Override>[
          serverStoreProvider.overrideWithValue(serverStore),
          progressStoreProvider.overrideWithValue(progressStore),
        ],
      );
      addTearDown(container.dispose);

      // 同时拉起真实 progressSyncProvider，验证 removeServer 不构成循环依赖。
      container.read(progressSyncProvider);
      await container.read(sessionProvider.notifier).removeServer(serverA);

      expect(await progressStore.pending(scope: serverA.id), isEmpty);
      expect(await progressStore.record('b1', scope: serverA.id), isNull);
      // 服务器 B 与本机进度必须完好无损。
      expect(await progressStore.pending(scope: serverB.id), hasLength(1));
      expect(
        (await progressStore.record('local-b1', scope: kLocalSourceKey))?.page,
        4,
      );
    });

    test(
      'ServerAddress.parse 抛出结构化 ServerAddressFormatException 且不带 Komga 硬编码文案',
      () {
        expect(
          () => ServerAddress.parse(''),
          throwsA(
            isA<ServerAddressFormatException>()
                .having((e) => e.reason, 'reason', ServerAddressError.empty)
                .having(
                  (e) => e.message.toLowerCase(),
                  'message',
                  isNot(contains('komga')),
                ),
          ),
        );
        expect(
          () => ServerAddress.parse('bad url'),
          throwsA(
            isA<ServerAddressFormatException>().having(
              (e) => e.reason,
              'reason',
              ServerAddressError.containsWhitespace,
            ),
          ),
        );
        expect(
          () => ServerAddress.parse('ftp://host'),
          throwsA(
            isA<ServerAddressFormatException>().having(
              (e) => e.reason,
              'reason',
              ServerAddressError.unsupportedScheme,
            ),
          ),
        );
      },
    );

    testWidgets('ReaderScreen 被路由替换直接销毁时不触碰 ref.read 且不抛错', (
      WidgetTester tester,
    ) async {
      const localBook = Book(
        id: 'b-replace',
        seriesId: 's-replace',
        name: 'Replaceable',
        number: '1',
        pagesCount: 2,
        sourceKey: kLocalSourceKey,
      );
      final localLib = FakeLibraryRepository();
      final localReader = FakeReaderRepository(
        stubBook: localBook,
        pageCount: 2,
      );
      final registry = SourceRegistry(
        localBundle: SourceBundle(
          source: const LocalContentSource(),
          library: localLib,
          reader: localReader,
          collections: localLib,
          readStatus: localLib,
        ),
        remoteBundles: const <String, SourceBundle>{},
      );
      final db = ProgressDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final cache = DriftHttpCache(
        HttpCacheDatabase(NativeDatabase.memory()),
        now: () => DateTime.utc(2026, 11, 27, 12),
      );
      addTearDown(cache.dispose);
      final sync = ProgressSyncService(
        store: InMemoryProgressStore(),
        upload: (_) async {},
      );
      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            sourceRegistryProvider.overrideWithValue(registry),
            progressDatabaseProvider.overrideWithValue(db),
            progressSyncProvider.overrideWithValue(sync),
            httpCacheProvider.overrideWithValue(cache),
            readerPrefsStoreProvider.overrideWithValue(
              InMemoryReaderPrefsStore(),
            ),
            wakeLockProvider.overrideWithValue(FakeWakeLock()),
            imageSaverProvider.overrideWithValue(FakeImageSaver()),
            hardwareKeysProvider.overrideWithValue(FakeHardwareKeys()),
          ],
          child: MaterialApp(
            navigatorKey: navKey,
            locale: const Locale('en'),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.dark(),
            home: const ReaderScreen(
              bookId: 'b-replace',
              sourceKey: kLocalSourceKey,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 直接 pushReplacement 替换当前 ReaderScreen（不走 PopScope）：dispose 不得抛异常。
      unawaited(
        navKey.currentState!.pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Replaced')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Replaced'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('N1: 系列详情已在缓存里且入口未传 direction 时，右到左漫画用键盘左键应翻到下一页', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      const rtlSeries = Series(
        id: 's-rtl-cached',
        libraryId: 'lib-1',
        title: 'Cached RTL Manga',
        booksCount: 1,
        readingDirection: ReadingDirection.rightToLeft,
        sourceKey: kLocalSourceKey,
      );
      const rtlBook = Book(
        id: 'b-rtl-cached',
        seriesId: 's-rtl-cached',
        name: 'Vol. 1',
        number: '1',
        pagesCount: 4,
        sourceKey: kLocalSourceKey,
      );
      final localLib = FakeLibraryRepository(series: <Series>[rtlSeries]);
      final localReader = FakeReaderRepository(stubBook: rtlBook, pageCount: 4);
      final registry = SourceRegistry(
        localBundle: SourceBundle(
          source: const LocalContentSource(),
          library: localLib,
          reader: localReader,
          collections: localLib,
          readStatus: localLib,
        ),
        remoteBundles: const <String, SourceBundle>{},
      );
      final db = ProgressDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final cache = DriftHttpCache(
        HttpCacheDatabase(NativeDatabase.memory()),
        now: () => DateTime.utc(2026, 11, 27, 12),
      );
      addTearDown(cache.dispose);
      final sync = ProgressSyncService(
        store: InMemoryProgressStore(),
        upload: (_) async {},
      );
      final container = ProviderContainer(
        overrides: <Override>[
          sourceRegistryProvider.overrideWithValue(registry),
          progressDatabaseProvider.overrideWithValue(db),
          progressSyncProvider.overrideWithValue(sync),
          httpCacheProvider.overrideWithValue(cache),
          readerPrefsStoreProvider.overrideWithValue(
            InMemoryReaderPrefsStore(),
          ),
          wakeLockProvider.overrideWithValue(FakeWakeLock()),
          imageSaverProvider.overrideWithValue(FakeImageSaver()),
          hardwareKeysProvider.overrideWithValue(FakeHardwareKeys()),
        ],
      );
      addTearDown(container.dispose);

      // 先把系列详情预热进缓存（模拟从搜索/书架/收藏进入阅读器时 seriesDetailProvider 已有缓存）。
      final preloaded = await container.read(
        seriesDetailProvider((
          sourceKey: kLocalSourceKey,
          seriesId: rtlSeries.id,
        )).future,
      );
      expect(preloaded?.readingDirection, ReadingDirection.rightToLeft);

      // 入口不传 direction（默认 unknown），与搜索/下载/收藏入口一致。
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.dark(),
            home: const ReaderScreen(
              bookId: 'b-rtl-cached',
              book: rtlBook,
              sourceKey: kLocalSourceKey,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('1 / 4'), findsOneWidget);

      // RTL 漫画按键盘左键 = 翻到下一页（第 2 页）；若 _nav.direction 停留在 unknown 会误判成 LTR 而停在第 1 页。
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.textContaining('2 / 4'), findsOneWidget);
    });
  });
}
