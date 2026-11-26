import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// ARC-06：置顶系列与阅读会话统计从 v5 `komga_cache.sqlite` 平滑迁入用户库 `komga_native.sqlite`。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('komga_arc06_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// 构造一份真实的 v5 `komga_cache.sqlite`（含置顶与阅读会话）及 v1 `komga_native.sqlite`。
  void seedLegacyDatabases({required File cacheFile, required File userFile}) {
    final cacheRaw = sqlite.sqlite3.open(cacheFile.path);
    cacheRaw.execute('''
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
      CREATE TABLE pinned_series_rows (
        server_id TEXT NOT NULL,
        series_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (server_id, series_id)
      );
      CREATE TABLE reading_sessions (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL,
        series_id TEXT NOT NULL,
        book_name TEXT NOT NULL DEFAULT '',
        started_at INTEGER NOT NULL,
        ended_at INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL,
        start_page INTEGER NOT NULL DEFAULT 1,
        end_page INTEGER NOT NULL DEFAULT 1,
        completed INTEGER NOT NULL DEFAULT 0
      );
      PRAGMA user_version = 5;
    ''');
    cacheRaw.execute('''
      INSERT INTO pinned_series_rows (server_id, series_id, created_at)
      VALUES ('https://srv-a', 's1', 1700000001), ('https://srv-a', 's2', 1700000010);
    ''');
    cacheRaw.execute('''
      INSERT INTO reading_sessions
      (id, book_id, series_id, book_name, started_at, ended_at, duration_ms, start_page, end_page, completed)
      VALUES
      (1, 'b1', 's1', 'Vol. 1', 1700000100, 1700000700, 600000, 1, 15, 0),
      (2, 'b2', 's1', 'Vol. 2', 1700001000, 1700001900, 900000, 1, 20, 1);
    ''');
    cacheRaw.close();

    final userRaw = sqlite.sqlite3.open(userFile.path);
    userRaw.execute('''
      CREATE TABLE local_progress (
        book_id TEXT NOT NULL PRIMARY KEY,
        page INTEGER NOT NULL,
        completed INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        server_last_modified INTEGER NULL,
        pending_seq INTEGER NULL
      );
      INSERT INTO local_progress (book_id, page, completed, updated_at, pending_seq)
      VALUES ('b1', 15, 0, 1700000700, 42);
      PRAGMA user_version = 1;
    ''');
    userRaw.close();
  }

  test('从 v5 缓存库平滑迁入置顶与阅读历史；清空或删除缓存库完全不影响用户资产', () async {
    final cacheFile = File('${tempDir.path}/komga_cache.sqlite');
    final userFile = File('${tempDir.path}/komga_native.sqlite');
    seedLegacyDatabases(cacheFile: cacheFile, userFile: userFile);

    final userDb = ProgressDatabase(
      NativeDatabase(userFile),
      legacyCacheDbPath: () => cacheFile.path,
    );

    // 既有 v1 本地进度完好。
    final progress = await userDb.record('b1');
    expect(progress?.page, 15);
    expect(progress?.pendingSeq, 42);

    // 置顶与阅读会话已完整迁入用户库。
    expect(await userDb.pinnedSeries('https://srv-a'), <String>['s2', 's1']);
    final sessions = await userDb.readingSessionList();
    expect(sessions.map((ReadingSession s) => s.bookId), <String>['b2', 'b1']);
    expect(sessions.first.completed, isTrue);

    // 打开缓存库执行 clear()，再彻底删除缓存库文件。
    final cacheDb = HttpCacheDatabase(NativeDatabase(cacheFile));
    await cacheDb.write(
      'https://srv-a',
      'https://srv-a/api/v1/series',
      'json',
      Uint8List.fromList(<int>[1, 2, 3]),
    );
    await cacheDb.clear();
    await cacheDb.close();
    cacheFile.deleteSync();
    expect(cacheFile.existsSync(), isFalse);

    // 删除缓存库后重新打开用户库：置顶、阅读历史与本地进度 100% 完好。
    await userDb.close();
    final reopened = ProgressDatabase(
      NativeDatabase(userFile),
      legacyCacheDbPath: () => cacheFile.path,
    );
    addTearDown(reopened.close);

    expect(await reopened.pinnedSeries('https://srv-a'), <String>['s2', 's1']);
    expect(
      (await reopened.readingSessionList()).map((ReadingSession s) => s.bookId),
      <String>['b2', 'b1'],
    );
    expect((await reopened.record('b1'))?.page, 15);
  });
}
