import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/progress/progress_store.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/data/reader_prefs_store.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu/src/providers/reader_toc_providers.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu/src/widgets/reader_settings_sheet.dart';
import 'package:yomu/src/widgets/scoped_source_scope.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';

class _FixedActiveSource extends ActiveSourceController {
  _FixedActiveSource(this._source);

  final ContentSource _source;

  @override
  ContentSource build() => _source;
}

void main() {
  test('服务器 B 激活时为服务器 A 的书写入进度：必须经服务器 A 会话立即上传而不滞留队列', () async {
    final receivedA = <String>[];
    final receivedB = <String>[];

    final serverA = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(serverA.close);
    serverA.listen((HttpRequest req) async {
      await req.drain<void>();
      receivedA.add(req.uri.path);
      req.response.statusCode = 204;
      await req.response.close();
    });

    final serverB = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(serverB.close);
    serverB.listen((HttpRequest req) async {
      await req.drain<void>();
      receivedB.add(req.uri.path);
      req.response.statusCode = 204;
      await req.response.close();
    });

    final urlA = 'http://127.0.0.1:${serverA.port}';
    final urlB = 'http://127.0.0.1:${serverB.port}';
    final storedA = StoredServer(
      address: ServerAddress.parse(urlA),
      apiKey: 'KEY-A',
      accountEmail: 'a@example.com',
    );
    final storedB = StoredServer(
      address: ServerAddress.parse(urlB),
      apiKey: 'KEY-B',
      accountEmail: 'b@example.com',
    );
    final serverStore = InMemoryServerStore();
    await serverStore.save(storedA);
    await serverStore.save(storedB); // B 为当前活动服务器

    final progressStore = InMemoryProgressStore();
    final container = ProviderContainer(
      overrides: <Override>[
        serverStoreProvider.overrideWithValue(serverStore),
        progressStoreProvider.overrideWithValue(progressStore),
      ],
    );
    addTearDown(container.dispose);

    // 预热会话与已保存服务器列表（活动会话是 B）。
    container.read(sessionProvider);
    await container.read(serverListProvider.future);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final session = container.read(sessionProvider);
    expect(session, isA<SessionConnected>());
    expect((session as SessionConnected).server.id, urlB);

    // 跨源保存服务器 A 的书籍进度（还原真实 HttpClient 以命中本地回环 HttpServer）。
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);

    final sync = container.read(progressSyncProvider);
    await sync.save('book-on-a', page: 7, completed: false, scope: urlA);
    await sync.flush(scope: urlA);

    expect(receivedA, <String>['/api/v1/books/book-on-a/read-progress']);
    expect(receivedB, isEmpty);
    expect(await progressStore.pending(scope: urlA), isEmpty);
  });

  test('服务器 B 激活时操作服务器 A 的书签：必须落在服务器 A 分区而非 B 分区', () async {
    const scopeA = 'https://komga-a.example';
    const scopeB = 'https://komga-b.example';
    final db = ProgressDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(
      overrides: <Override>[
        progressDatabaseProvider.overrideWithValue(db),
        activeSourceProvider.overrideWith(
          () => _FixedActiveSource(
            const RemoteContentSource(
              sourceKey: scopeB,
              displayName: 'Server B',
              subtitle: scopeB,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final added = await container
        .read(bookmarkControllerProvider)
        .toggle(bookId: 'b1', page: 12, sourceKey: scopeA);
    expect(added, isTrue);

    final subA = container.listen(
      bookBookmarksProvider((sourceKey: scopeA, bookId: 'b1')),
      (_, _) {},
    );
    final subB = container.listen(
      bookBookmarksProvider((sourceKey: scopeB, bookId: 'b1')),
      (_, _) {},
    );
    addTearDown(subA.close);
    addTearDown(subB.close);

    final bookmarksA = await container.read(
      bookBookmarksProvider((sourceKey: scopeA, bookId: 'b1')).future,
    );
    final bookmarksB = await container.read(
      bookBookmarksProvider((sourceKey: scopeB, bookId: 'b1')).future,
    );
    expect(bookmarksA.map((b) => b.page), <int>[12]);
    expect(bookmarksB, isEmpty);
  });

  testWidgets('服务器 B 激活时修改服务器 A 的系列覆盖设置：必须写入 A 分区且不污染 B', (
    WidgetTester tester,
  ) async {
    const scopeA = 'https://komga-a.example';
    const scopeB = 'https://komga-b.example';
    final prefsStore = InMemoryReaderPrefsStore();

    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          readerPrefsStoreProvider.overrideWithValue(prefsStore),
          activeSourceProvider.overrideWith(
            () => _FixedActiveSource(
              const RemoteContentSource(
                sourceKey: scopeB,
                displayName: 'Server B',
                subtitle: scopeB,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Consumer(
              builder: (BuildContext context, WidgetRef ref, Widget? _) {
                capturedRef = ref;
                return ScopedSourceScope(
                  sourceKey: scopeA,
                  child: ReaderSettingsSheet(
                    palette: ReaderPalette.of(isEink: false),
                    page: 1,
                    total: 10,
                    seriesId: 'shared-series-id',
                    onJump: (int _) {},
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 开启「按系列记住」并切换到纵向滚动模式。
    await tester.tap(find.byKey(const Key('reader-series-remember')));
    await tester.pumpAndSettle();
    final verticalFinder = find.byKey(const Key('reader-mode-vertical'));
    await tester.ensureVisible(verticalFinder);
    await tester.pumpAndSettle();
    await tester.tap(verticalFinder);
    await tester.pumpAndSettle();

    final prefs = capturedRef.read(readerPrefsProvider);
    expect(
      prefs.hasSeriesOverride('shared-series-id', serverKey: scopeA),
      isTrue,
    );
    expect(
      prefs.hasSeriesOverride('shared-series-id', serverKey: scopeB),
      isFalse,
    );
    expect(
      prefs.forSeries('shared-series-id', serverKey: scopeA).mode,
      ReaderModeChoice.vertical,
    );
    expect(
      prefs.forSeries('shared-series-id', serverKey: scopeB).mode,
      ReaderModeChoice.auto,
    );
  });
}
