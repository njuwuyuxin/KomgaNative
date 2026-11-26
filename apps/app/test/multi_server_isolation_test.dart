import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/data/reader_prefs_store.dart';
import 'package:yomu/src/data/reading_session_tracker.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/download_providers.dart';
import 'package:yomu/src/providers/pinned_series_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu/src/providers/reading_history_provider.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// ARC-07：多服务器数据隔离闭环验收测试。
void main() {
  test('多服务器切换：待提交进度不串发、下载/历史/阅读设置互不污染、切回完整恢复', () async {
    var serverAOnline = false;
    final serverARequests = <String>[];
    final serverBRequests = <String>[];

    final httpA = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final httpB = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(httpA.close);
    addTearDown(httpB.close);

    httpA.listen((HttpRequest req) async {
      await req.drain<void>();
      serverARequests.add('${req.method} ${req.uri.path}');
      req.response.statusCode = serverAOnline ? 204 : 503;
      await req.response.close();
    });
    httpB.listen((HttpRequest req) async {
      await req.drain<void>();
      serverBRequests.add('${req.method} ${req.uri.path}');
      req.response.statusCode = 204;
      await req.response.close();
    });

    final serverA = StoredServer(
      address: ServerAddress.parse('http://127.0.0.1:${httpA.port}'),
      apiKey: 'KEY-A',
      accountEmail: 'a@example.com',
    );
    final serverB = StoredServer(
      address: ServerAddress.parse('http://127.0.0.1:${httpB.port}'),
      apiKey: 'KEY-B',
      accountEmail: 'b@example.com',
    );

    final userDb = ProgressDatabase(NativeDatabase.memory());
    final cacheDb = HttpCacheDatabase(NativeDatabase.memory());
    addTearDown(userDb.close);
    addTearDown(cacheDb.close);

    final container = ProviderContainer(
      overrides: <Override>[
        serverStoreProvider.overrideWithValue(
          InMemoryServerStore.withAll(<StoredServer>[
            serverA,
            serverB,
          ], active: serverA),
        ),
        progressDatabaseProvider.overrideWithValue(userDb),
        httpCacheDatabaseProvider.overrideWithValue(cacheDb),
        readerPrefsStoreProvider.overrideWithValue(InMemoryReaderPrefsStore()),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionProvider);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(container.read(activeServerKeyProvider), serverA.address.baseUrl);

    // 1. 在服务器 A 产生未提交进度（A 当前 503）、下载记录、阅读历史、系列覆盖与分屏起点。
    final scopeA = serverA.address.baseUrl;
    final scopeB = serverB.address.baseUrl;
    final sync = container.read(progressSyncProvider);
    await sync.save('b1', page: 12, completed: false, scope: scopeA);
    await sync.flush(scope: scopeA);
    expect(
      await userDb.pending(scope: scopeA),
      hasLength(1),
      reason: '服务器 A 返回 503，进度留在服务器 A 的专属队列中',
    );

    await cacheDb.markDownloaded(
      scope: scopeA,
      bookId: 'b1',
      seriesId: 's1',
      pageCount: 20,
      bytes: 4096,
    );
    await container
        .read(readingSessionRecorderProvider)
        .record(
          ReadingSessionDraft(
            bookId: 'b1',
            seriesId: 's1',
            bookName: 'Vol. 1',
            startedAt: DateTime.utc(2026, 11, 20, 10),
            endedAt: DateTime.utc(2026, 11, 20, 10, 15),
            startPage: 1,
            endPage: 12,
            completed: false,
          ),
          scope: scopeA,
        );
    container.read(readerPrefsProvider.notifier)
      ..setSeriesOverride('s1', true, serverKey: scopeA)
      ..setMode(ReaderModeChoice.double, seriesId: 's1', serverKey: scopeA)
      ..setSpreadFrom('b1', 3, serverKey: scopeA);

    // 2. 切换到服务器 B：验证进度/下载/阅读偏好隔离，同时阅读历史按 ADR 0008 全局汇聚但携带显式 scope 分区。
    await container.read(sessionProvider.notifier).switchTo(serverB);
    await sync.flush(scope: scopeB);

    expect(
      serverBRequests,
      isEmpty,
      reason: '服务器 A 的 pending 进度绝不允许 PATCH 到服务器 B',
    );
    expect(await container.read(downloadedBooksProvider.future), isEmpty);
    expect((await container.read(downloadsUsageProvider.future)).entries, 0);
    final globalSessions = await container.read(readingSessionsProvider.future);
    expect(globalSessions, hasLength(1));
    expect(globalSessions.single.scope, scopeA);

    final prefsOnB = container.read(readerPrefsProvider);
    final keyB = container.read(activeServerKeyProvider);
    expect(
      prefsOnB.forSeries('s1', serverKey: keyB).mode,
      ReaderModeChoice.auto,
    );
    expect(prefsOnB.spreadFromFor('b1', serverKey: keyB), isNull);

    // 3. 切回服务器 A（且服务器 A 恢复在线）：验证全部数据恢复且 pending 正常上传到 A。
    serverAOnline = true;
    serverARequests.clear();
    await container.read(sessionProvider.notifier).switchTo(serverA);
    await sync.flush(scope: scopeA);

    expect(serverARequests, <String>['PATCH /api/v1/books/b1/read-progress']);
    expect(await userDb.pending(scope: scopeA), isEmpty);

    final downloadsOnA = await container.read(downloadedBooksProvider.future);
    expect(downloadsOnA.map((DownloadedBookRecord d) => d.bookId), <String>[
      'b1',
    ]);
    final sessionsOnA = await container.read(readingSessionsProvider.future);
    expect(sessionsOnA.map((ReadingSession s) => s.bookId), <String>['b1']);

    final keyA = container.read(activeServerKeyProvider);
    expect(
      prefsOnB.forSeries('s1', serverKey: keyA).mode,
      ReaderModeChoice.double,
    );
    expect(prefsOnB.spreadFromFor('b1', serverKey: keyA), 3);
  });

  test('ReaderPrefs 旧版无前缀键兼容回退，新写入使用 serverKey|id', () {
    final legacy = ReaderPrefs.fromJson(const <String, Object?>{
      'spreadFrom': <String, Object?>{'b-old': 2},
      'seriesOverrides': <String, Object?>{
        's-old': <String, Object?>{'mode': 'vertical'},
      },
    });

    expect(
      legacy.forSeries('s-old', serverKey: 'https://srv-a').mode,
      ReaderModeChoice.vertical,
    );
    expect(legacy.spreadFromFor('b-old', serverKey: 'https://srv-a'), 2);

    final updated = legacy
        .withSeriesOverride(
          's-new',
          const ReaderConfig(mode: ReaderModeChoice.double),
          serverKey: 'https://srv-a',
        )
        .withSpreadFrom('b-new', 4, serverKey: 'https://srv-a');

    expect(updated.seriesOverrides.containsKey('https://srv-a|s-new'), isTrue);
    expect(updated.spreadFrom['https://srv-a|b-new'], 4);
    expect(
      updated.forSeries('s-new', serverKey: 'https://srv-b').mode,
      ReaderModeChoice.auto,
    );
  });

  test('v5 缓存库下载表升级至 v6 复合主键并回填活动服务器 scope', () async {
    final dir = Directory.systemTemp.createTempSync('komga_arc07_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final cacheFile = File('${dir.path}/komga_cache.sqlite');
    final raw = sqlite.sqlite3.open(cacheFile.path);
    raw.execute('''
      CREATE TABLE cached_responses (
        scope TEXT NOT NULL,
        url TEXT NOT NULL,
        kind TEXT NOT NULL,
        byte_size INTEGER NOT NULL,
        body BLOB NOT NULL,
        last_used_seq INTEGER NOT NULL,
        PRIMARY KEY (scope, url)
      );
      CREATE TABLE downloaded_books (
        book_id TEXT NOT NULL PRIMARY KEY,
        series_id TEXT NOT NULL,
        page_count INTEGER NOT NULL,
        bytes INTEGER NOT NULL,
        saved_at INTEGER NOT NULL
      );
      CREATE TABLE download_queue_entries (
        book_id TEXT NOT NULL PRIMARY KEY,
        series_id TEXT NOT NULL,
        name TEXT NOT NULL,
        number TEXT NOT NULL DEFAULT '',
        pages_count INTEGER NOT NULL,
        state TEXT NOT NULL,
        done INTEGER NOT NULL DEFAULT 0,
        total INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
      INSERT INTO downloaded_books VALUES ('b1', 's1', 10, 2048, 1700000000);
      INSERT INTO download_queue_entries VALUES ('b2', 's1', 'Vol 2', '2', 12, 'queued', 0, 12, 1700000001);
      PRAGMA user_version = 5;
    ''');
    raw.close();

    final db = HttpCacheDatabase(
      NativeDatabase(cacheFile),
      defaultLegacyScope: () => 'https://srv-a',
    );
    addTearDown(db.close);

    expect(await db.downloads(scope: 'https://srv-a'), hasLength(1));
    expect(await db.downloads(scope: 'https://srv-b'), isEmpty);
    expect(await db.downloadQueue(scope: 'https://srv-a'), hasLength(1));
    expect(await db.downloadQueue(scope: 'https://srv-b'), isEmpty);
  });
}
