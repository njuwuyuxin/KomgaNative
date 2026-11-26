import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/local/external_roots_dao.dart';
import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/data/progress/bookmarks_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_platform/yomu_platform.dart';

typedef _ColumnSpec = ({String name, String type, bool notNull, int pk});

/// 读取 SQLite 文件内全部用户表及每列结构，用于比对升级库与全新建库的一致性。
Map<String, Map<String, _ColumnSpec>> _inspectSchema(File dbFile) {
  final raw = sqlite.sqlite3.open(dbFile.path);
  try {
    final tableRows = raw.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    final schema = <String, Map<String, _ColumnSpec>>{};
    for (final row in tableRows) {
      final table = row['name'] as String;
      final cols = raw.select('PRAGMA table_info("$table")');
      schema[table] = <String, _ColumnSpec>{
        for (final c in cols)
          c['name'] as String: (
            name: c['name'] as String,
            type: (c['type'] as String).toUpperCase(),
            notNull: (c['notnull'] as int) != 0,
            pk: c['pk'] as int,
          ),
      };
    }
    return schema;
  } finally {
    raw.close();
  }
}

void _assertSchemaMatchesFresh(
  Map<String, Map<String, _ColumnSpec>> migrated,
  Map<String, Map<String, _ColumnSpec>> fresh, {
  required String label,
}) {
  expect(
    migrated.keys.toSet(),
    fresh.keys.toSet(),
    reason: '$label 升级后表集合必须与全新建库完全一致',
  );
  for (final table in fresh.keys) {
    final expectedCols = fresh[table]!;
    final actualCols = migrated[table]!;
    expect(
      actualCols.keys.toSet(),
      expectedCols.keys.toSet(),
      reason: '$label 表 $table 列集合必须与全新建库一致',
    );
    for (final col in expectedCols.keys) {
      expect(
        actualCols[col],
        expectedCols[col],
        reason: '$label 表 $table.$col 约束/类型/主键必须与全新建库一致',
      );
    }
  }
}

void _seedV1(File dbFile) {
  final raw = sqlite.sqlite3.open(dbFile.path);
  raw.execute('''
    CREATE TABLE local_progress (
      book_id TEXT NOT NULL PRIMARY KEY,
      page INTEGER NOT NULL,
      completed INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      server_last_modified INTEGER NULL,
      pending_seq INTEGER NULL
    );
    INSERT INTO local_progress (book_id, page, completed, updated_at, pending_seq)
    VALUES ('b-v1', 9, 0, 1700000100, 7);
    PRAGMA user_version = 1;
  ''');
  raw.close();
}

void _seedV2(File dbFile) {
  _seedV1(dbFile);
  final raw = sqlite.sqlite3.open(dbFile.path);
  raw.execute('''
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
    INSERT INTO pinned_series_rows (server_id, series_id, created_at)
    VALUES ('https://legacy.komga', 's-v2', 1700000200);
    INSERT INTO reading_sessions
      (book_id, series_id, book_name, started_at, ended_at, duration_ms)
    VALUES ('b-v2', 's-v2', 'V2 Vol.1', 1700000200, 1700000500, 300000);
    PRAGMA user_version = 2;
  ''');
  raw.close();
}

void _seedV3(File dbFile) {
  final raw = sqlite.sqlite3.open(dbFile.path);
  raw.execute('''
    CREATE TABLE local_progress (
      scope TEXT NOT NULL DEFAULT '',
      book_id TEXT NOT NULL,
      page INTEGER NOT NULL,
      completed INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      server_last_modified INTEGER NULL,
      pending_seq INTEGER NULL,
      PRIMARY KEY (scope, book_id)
    );
    CREATE TABLE pinned_series_rows (
      server_id TEXT NOT NULL,
      series_id TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      PRIMARY KEY (server_id, series_id)
    );
    CREATE TABLE reading_sessions (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      scope TEXT NOT NULL DEFAULT '',
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
    INSERT INTO local_progress (scope, book_id, page, completed, updated_at)
    VALUES ('https://v3.komga', 'b-v3', 12, 0, 1700000300);
    PRAGMA user_version = 3;
  ''');
  raw.close();
}

void _seedV4(File dbFile) {
  _seedV3(dbFile);
  final raw = sqlite.sqlite3.open(dbFile.path);
  raw.execute('''
    CREATE TABLE local_series_rows (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL,
      title_sort TEXT NOT NULL,
      summary TEXT NOT NULL DEFAULT '',
      publisher TEXT NOT NULL DEFAULT '',
      authors_json TEXT NOT NULL DEFAULT '[]',
      tags_json TEXT NOT NULL DEFAULT '[]',
      reading_direction TEXT NOT NULL DEFAULT 'unknown',
      cover_book_id TEXT NULL,
      custom_cover_path TEXT NULL,
      metadata_locked INTEGER NOT NULL DEFAULT 0,
      release_date INTEGER NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    CREATE TABLE local_books_rows (
      id TEXT NOT NULL PRIMARY KEY,
      series_id TEXT NOT NULL,
      name TEXT NOT NULL,
      number TEXT NOT NULL DEFAULT '',
      number_sort REAL NOT NULL DEFAULT 0.0,
      pages_count INTEGER NOT NULL,
      size_bytes INTEGER NOT NULL,
      storage_kind TEXT NOT NULL,
      relative_path TEXT NOT NULL,
      cover_thumb_path TEXT NULL,
      release_date INTEGER NULL,
      created_at INTEGER NOT NULL
    );
    CREATE TABLE local_pages_rows (
      book_id TEXT NOT NULL,
      page_number INTEGER NOT NULL,
      entry_name TEXT NOT NULL,
      local_header_offset INTEGER NOT NULL DEFAULT 0,
      compressed_size INTEGER NOT NULL DEFAULT 0,
      uncompressed_size INTEGER NOT NULL DEFAULT 0,
      compression_method INTEGER NOT NULL DEFAULT 0,
      width INTEGER NULL,
      height INTEGER NULL,
      media_type TEXT NULL,
      PRIMARY KEY (book_id, page_number)
    );
    CREATE TABLE local_collections_rows (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      ordered INTEGER NOT NULL DEFAULT 0,
      series_ids_json TEXT NOT NULL DEFAULT '[]',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    CREATE TABLE local_read_lists_rows (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      summary TEXT NOT NULL DEFAULT '',
      ordered INTEGER NOT NULL DEFAULT 0,
      book_ids_json TEXT NOT NULL DEFAULT '[]',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    INSERT INTO local_series_rows (id, title, title_sort, created_at, updated_at)
    VALUES ('local:s-v4', 'V4 Manga', 'v4 manga', 1700000400, 1700000400);
    INSERT INTO local_books_rows
      (id, series_id, name, pages_count, size_bytes, storage_kind, relative_path, created_at)
    VALUES
      ('local:b-v4', 'local:s-v4', 'Vol. 1', 24, 4096, 'zip', 'books/v4/vol1.cbz', 1700000400);
    PRAGMA user_version = 4;
  ''');
  raw.close();
}

void _seedV5(File dbFile) {
  _seedV4(dbFile);
  final raw = sqlite.sqlite3.open(dbFile.path);
  raw.execute('''
    CREATE TABLE local_book_chapters_rows (
      book_id TEXT NOT NULL,
      chapter_index INTEGER NOT NULL,
      title TEXT NOT NULL,
      start_page INTEGER NOT NULL,
      PRIMARY KEY (book_id, chapter_index)
    );
    CREATE TABLE page_bookmarks_rows (
      scope TEXT NOT NULL DEFAULT '',
      book_id TEXT NOT NULL,
      page INTEGER NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      PRIMARY KEY (scope, book_id, page)
    );
    INSERT INTO page_bookmarks_rows (scope, book_id, page, note, created_at)
    VALUES ('local://device', 'local:b-v4', 5, 'Favorite spread', 1700000500);
    PRAGMA user_version = 5;
  ''');
  raw.close();
}

void main() {
  group('P2-3 ProgressDatabase 全链路迁移（v1/v2/v3/v4/v5 → v6）与 Schema 快照校验', () {
    late Directory tempDir;
    late Map<String, Map<String, _ColumnSpec>> freshSchema;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('yomu_full_mig_');
      final freshFile = File('${tempDir.path}/fresh_v6.sqlite');
      final freshDb = ProgressDatabase(NativeDatabase(freshFile));
      await freshDb.pinnedSeries('any');
      await freshDb.close();
      freshSchema = _inspectSchema(freshFile);
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('v1 → v6 全链路升级：保留旧进度并回填 scope，表列结构与全新建库 100% 一致', () async {
      final dbFile = File('${tempDir.path}/v1.sqlite');
      _seedV1(dbFile);

      final db = ProgressDatabase(
        NativeDatabase(dbFile),
        defaultLegacyScope: () => 'https://legacy.komga',
      );
      final rec = await db.record('b-v1', scope: 'https://legacy.komga');
      expect(rec?.page, 9);
      expect(rec?.pendingSeq, 7);

      // 验证升级后新表均可正常读写
      await db.togglePageBookmark(
        scope: kLocalSourceKey,
        bookId: 'b-new',
        page: 3,
      );
      expect(
        await db.pageBookmarks(scope: kLocalSourceKey, bookId: 'b-new'),
        hasLength(1),
      );
      await db.upsertMountedRoot(
        const MountedExternalRoot(
          id: 'root-1',
          displayName: 'SD Comics',
          uriOrBookmark: '/comics',
          kind: ExternalRootKind.localDirectory,
        ),
      );
      expect(await db.allMountedRoots(), hasLength(1));
      await db.close();

      _assertSchemaMatchesFresh(
        _inspectSchema(dbFile),
        freshSchema,
        label: 'v1→v6',
      );
    });

    test('v2 → v6 全链路升级：保留置顶与会话并回填 reading_sessions.scope，表列完全一致', () async {
      final dbFile = File('${tempDir.path}/v2.sqlite');
      _seedV2(dbFile);

      final db = ProgressDatabase(
        NativeDatabase(dbFile),
        defaultLegacyScope: () => 'https://legacy.komga',
      );
      expect(await db.pinnedSeries('https://legacy.komga'), <String>['s-v2']);
      final sessions = await db.readingSessionList(
        scope: 'https://legacy.komga',
      );
      expect(sessions, hasLength(1));
      expect(sessions.single.scope, 'https://legacy.komga');
      await db.close();

      _assertSchemaMatchesFresh(
        _inspectSchema(dbFile),
        freshSchema,
        label: 'v2→v6',
      );
    });

    test('v3 → v6 全链路升级：保留分区进度并补齐本地编目/书签/挂载表，表列完全一致', () async {
      final dbFile = File('${tempDir.path}/v3.sqlite');
      _seedV3(dbFile);

      final db = ProgressDatabase(NativeDatabase(dbFile));
      final rec = await db.record('b-v3', scope: 'https://v3.komga');
      expect(rec?.page, 12);
      await db.close();

      _assertSchemaMatchesFresh(
        _inspectSchema(dbFile),
        freshSchema,
        label: 'v3→v6',
      );
    });

    test('v4 → v6 全链路升级：保留本地系列/书籍并扩充 v6 外部挂载 4 列，表列完全一致', () async {
      final dbFile = File('${tempDir.path}/v4.sqlite');
      _seedV4(dbFile);

      final db = ProgressDatabase(NativeDatabase(dbFile));
      final bookRow = await db.localBookRowById('local:b-v4');
      expect(bookRow?.name, 'Vol. 1');
      expect(bookRow?.mountRootId, isNull);
      expect(bookRow?.isCloudPlaceholder, isFalse);
      await db.close();

      _assertSchemaMatchesFresh(
        _inspectSchema(dbFile),
        freshSchema,
        label: 'v4→v6',
      );
    });

    test('v5 → v6 升级：保留书签与本地书籍并创建外部挂载根目录表，表列完全一致', () async {
      final dbFile = File('${tempDir.path}/v5.sqlite');
      _seedV5(dbFile);

      final db = ProgressDatabase(NativeDatabase(dbFile));
      final bookmarks = await db.pageBookmarks(
        scope: kLocalSourceKey,
        bookId: 'local:b-v4',
      );
      expect(bookmarks, hasLength(1));
      expect(bookmarks.single.page, 5);
      await db.close();

      _assertSchemaMatchesFresh(
        _inspectSchema(dbFile),
        freshSchema,
        label: 'v5→v6',
      );
    });

    test('Drift schema dump 快照（ProgressDatabase v6 & HttpCacheDatabase v8）与运行时表列一致', () async {
      void verifySnapshot(
        String path,
        Map<String, Map<String, _ColumnSpec>> actual,
      ) {
        final file = File(path);
        expect(
          file.existsSync(),
          isTrue,
          reason: '缺少 Drift schema 快照：$path，请运行 dart run drift_dev schema dump',
        );
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        final entities = (json['entities'] as List<Object?>)
            .cast<Map<String, Object?>>();
        final snapshotTables = <String, Set<String>>{};
        for (final entity in entities) {
          if (entity['type'] != 'table') continue;
          final data = entity['data']! as Map<String, Object?>;
          final name = data['name']! as String;
          final columns = (data['columns']! as List<Object?>)
              .cast<Map<String, Object?>>();
          snapshotTables[name] = <String>{
            for (final c in columns) c['name']! as String,
          };
        }
        expect(
          actual.keys.toSet(),
          snapshotTables.keys.toSet(),
          reason: '$path 表集合与运行时不一致，修改表结构或升级 schemaVersion 后请重新 dump',
        );
        for (final entry in snapshotTables.entries) {
          expect(
            actual[entry.key]!.keys.toSet(),
            entry.value,
            reason: '$path 表 ${entry.key} 列集合与运行时不一致',
          );
        }
      }

      final progressVersionDb = ProgressDatabase(NativeDatabase.memory());
      final progressVersion = progressVersionDb.schemaVersion;
      await progressVersionDb.close();
      verifySnapshot(
        'drift_schemas/progress_database/drift_schema_v$progressVersion.json',
        freshSchema,
      );

      final cacheFile = File('${tempDir.path}/fresh_cache_v8.sqlite');
      final cacheDb = HttpCacheDatabase(NativeDatabase(cacheFile));
      final cacheVersion = cacheDb.schemaVersion;
      await cacheDb.downloadsUsage();
      await cacheDb.close();
      verifySnapshot(
        'drift_schemas/http_cache_database/drift_schema_v$cacheVersion.json',
        _inspectSchema(cacheFile),
      );
    });
  });
}
