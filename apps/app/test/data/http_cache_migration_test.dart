import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:yomu/src/data/cache/http_cache_database.dart';

/// P2-6：HttpCacheDatabase 旧 schema 版本（v1 / v2 / v3 / v7）→ v8 迁移测试。
void main() {
  group('P2-6 HttpCacheDatabase schema migrations to v8', () {
    test(
      'v1 -> v8：补建 downloaded_books / download_queue_entries 并保留旧缓存',
      () async {
        final raw = sqlite.sqlite3.openInMemory();
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
      ''');
        raw.execute(
          'INSERT INTO cached_responses (scope, url, kind, byte_size, body, last_used_seq) '
          "VALUES ('https://srv-a', 'https://srv-a/api/v1/series', 'json', 4, X'7B7D0A20', 10)",
        );
        raw.execute('PRAGMA user_version = 1');

        final db = HttpCacheDatabase(NativeDatabase.opened(raw));
        addTearDown(db.close);

        final cached = await db.read(
          'https://srv-a',
          'https://srv-a/api/v1/series',
        );
        expect(cached, isNotNull);
        expect(cached!.pinned, isFalse);

        // 升级后新表可正常读写。
        await db.markDownloaded(
          scope: 'https://srv-a',
          bookId: 'b1',
          seriesId: 's1',
          bookName: 'Vol 1',
          pageCount: 10,
          bytes: 1024,
        );
        final dl = await db.download('b1', scope: 'https://srv-a');
        expect(dl?.bookName, 'Vol 1');
        expect(await db.downloadQueue(scope: 'https://srv-a'), isEmpty);
      },
    );

    test('v2 -> v8：downloaded_books 按 legacyScope 回填并自动 pin 页图与元数据', () async {
      final raw = sqlite.sqlite3.openInMemory();
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
      ''');
      raw.execute('''
        CREATE TABLE downloaded_books (
          book_id TEXT NOT NULL PRIMARY KEY,
          series_id TEXT NOT NULL,
          page_count INTEGER NOT NULL,
          bytes INTEGER NOT NULL,
          saved_at INTEGER NOT NULL
        );
      ''');
      const scope = 'https://legacy.komga';
      raw.execute(
        'INSERT INTO downloaded_books (book_id, series_id, page_count, bytes, saved_at) '
        "VALUES ('book-1', 'series-1', 20, 4096, 1700000000)",
      );
      raw.execute(
        'INSERT INTO cached_responses (scope, url, kind, byte_size, body, last_used_seq) VALUES '
        "('$scope', '$scope/api/v1/books/book-1/pages/1', 'image', 3, X'010203', 1),"
        "('$scope', '$scope/api/v1/books/book-1/pages', 'json', 2, X'5B5D', 2),"
        "('$scope', '$scope/api/v1/books/book-1', 'json', 2, X'7B7D', 3),"
        "('$scope', '$scope/api/v1/books/other/pages/1', 'image', 3, X'040506', 4)",
      );
      raw.execute('PRAGMA user_version = 2');

      final db = HttpCacheDatabase(
        NativeDatabase.opened(raw),
        defaultLegacyScope: () => scope,
      );
      addTearDown(db.close);

      final dl = await db.download('book-1', scope: scope);
      expect(dl, isNotNull);
      expect(dl!.seriesId, 'series-1');
      expect(dl.bookName, '');

      // 下载书的页图 + /pages + /books/{id} 元数据全部被自动 pin。
      expect(
        await db.readPinned(scope, '$scope/api/v1/books/book-1/pages/1'),
        isNotNull,
      );
      expect(
        await db.readPinned(scope, '$scope/api/v1/books/book-1/pages'),
        isNotNull,
      );
      expect(
        await db.readPinned(scope, '$scope/api/v1/books/book-1'),
        isNotNull,
      );
      // 未下载书的缓存保持非 pinned，允许被 LRU / clear 清理。
      expect(
        await db.readPinned(scope, '$scope/api/v1/books/other/pages/1'),
        isNull,
      );
      expect(
        await db.read(scope, '$scope/api/v1/books/other/pages/1'),
        isNotNull,
      );
    });

    test(
      'v3 -> v8：download_queue_entries 同步迁移到 legacyScope 且含单引号域名安全转义',
      () async {
        final raw = sqlite.sqlite3.openInMemory();
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
      ''');
        raw.execute('''
        CREATE TABLE downloaded_books (
          book_id TEXT NOT NULL PRIMARY KEY,
          series_id TEXT NOT NULL,
          page_count INTEGER NOT NULL,
          bytes INTEGER NOT NULL,
          saved_at INTEGER NOT NULL
        );
      ''');
        raw.execute('''
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
      ''');
        raw.execute(
          'INSERT INTO download_queue_entries '
          '(book_id, series_id, name, number, pages_count, state, done, total, created_at) '
          "VALUES ('q1', 's1', 'Vol 1', '1', 12, 'queued', 0, 12, 1700000000)",
        );
        raw.execute('PRAGMA user_version = 3');

        const scopeWithQuote = "https://bob's-komga.example";
        final db = HttpCacheDatabase(
          NativeDatabase.opened(raw),
          defaultLegacyScope: () => scopeWithQuote,
        );
        addTearDown(db.close);

        final queue = await db.downloadQueue(scope: scopeWithQuote);
        expect(queue, hasLength(1));
        expect(queue.single.bookId, 'q1');
        expect(queue.single.scope, scopeWithQuote);
      },
    );

    test('v7 -> v8：新增 book_name 列并对已下载书补标 /books/{id} 与 /pages 元数据 pinned', () async {
      final raw = sqlite.sqlite3.openInMemory();
      raw.execute('''
        CREATE TABLE cached_responses (
          scope TEXT NOT NULL,
          url TEXT NOT NULL,
          kind TEXT NOT NULL,
          byte_size INTEGER NOT NULL,
          body BLOB NOT NULL,
          last_used_seq INTEGER NOT NULL,
          pinned INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (scope, url)
        );
      ''');
      raw.execute('''
        CREATE TABLE downloaded_books (
          scope TEXT NOT NULL DEFAULT '',
          book_id TEXT NOT NULL,
          series_id TEXT NOT NULL,
          page_count INTEGER NOT NULL,
          bytes INTEGER NOT NULL,
          saved_at INTEGER NOT NULL,
          PRIMARY KEY (scope, book_id)
        );
      ''');
      raw.execute('''
        CREATE TABLE download_queue_entries (
          scope TEXT NOT NULL DEFAULT '',
          book_id TEXT NOT NULL,
          series_id TEXT NOT NULL,
          name TEXT NOT NULL,
          number TEXT NOT NULL DEFAULT '',
          pages_count INTEGER NOT NULL,
          state TEXT NOT NULL,
          done INTEGER NOT NULL DEFAULT 0,
          total INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          PRIMARY KEY (scope, book_id)
        );
      ''');
      const scope = 'https://srv-v7';
      raw.execute(
        'INSERT INTO downloaded_books (scope, book_id, series_id, page_count, bytes, saved_at) '
        "VALUES ('$scope', 'b7', 's7', 5, 500, 1700000000)",
      );
      raw.execute(
        'INSERT INTO cached_responses (scope, url, kind, byte_size, body, last_used_seq, pinned) VALUES '
        "('$scope', '$scope/api/v1/books/b7', 'json', 2, X'7B7D', 1, 0),"
        "('$scope', '$scope/api/v1/books/b7/pages', 'json', 2, X'5B5D', 2, 0),"
        "('$scope', '$scope/api/v1/series/s7', 'json', 2, X'7B7D', 3, 0)",
      );
      raw.execute('PRAGMA user_version = 7');

      final db = HttpCacheDatabase(NativeDatabase.opened(raw));
      addTearDown(db.close);

      // 升级后 clear() 不应清掉被补 pin 的离线元数据，但应清掉普通系列列表缓存。
      await db.clear(scope: scope);

      expect(await db.readPinned(scope, '$scope/api/v1/books/b7'), isNotNull);
      expect(
        await db.readPinned(scope, '$scope/api/v1/books/b7/pages'),
        isNotNull,
      );
      expect(await db.read(scope, '$scope/api/v1/series/s7'), isNull);

      // 新写入带 bookName 的记录可正常持久化。
      await db.write(scope, '$scope/api/v1/books/b8', 'json', Uint8List(2));
      await db.markDownloaded(
        scope: scope,
        bookId: 'b8',
        seriesId: 's7',
        bookName: 'Volume 8',
        pageCount: 8,
        bytes: 800,
      );
      expect((await db.download('b8', scope: scope))?.bookName, 'Volume 8');
    });
  });
}
