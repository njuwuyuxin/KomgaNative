import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;
import 'package:yomu/src/data/local/local_catalog_delete_dao.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/progress/bookmarks_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

void main() {
  group('LMB-05 ProgressDatabase v5 迁移、章节目录与页级书签', () {
    test(
      '从 schema v4 升级至 v5 自动创建 local_book_chapters_rows 与 page_bookmarks_rows',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('yomu_v4_to_v5_');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final dbFile = File('${tempDir.path}/komga_native.sqlite');

        // 先手工构造一个 v4 版本的 SQLite 文件并设置 user_version = 4。
        final raw = raw_sqlite.sqlite3.open(dbFile.path);
        try {
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
            id INTEGER PRIMARY KEY AUTOINCREMENT,
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
          PRAGMA user_version = 4;
        ''');
        } finally {
          raw.close();
        }

        final db = ProgressDatabase(NativeDatabase(dbFile));
        addTearDown(db.close);

        final added = await db.togglePageBookmark(
          scope: 'https://komga.example',
          bookId: 'b1',
          page: 12,
          nowOverride: DateTime.utc(2026, 11, 26),
        );
        expect(added, isTrue);
        final bms = await db.pageBookmarks(
          scope: 'https://komga.example',
          bookId: 'b1',
        );
        expect(bms, hasLength(1));
        expect(bms.single.page, 12);
      },
    );

    test('本地书籍入库持久化章节目录，书签按 scope 物理隔离，删书时同步级联清理', () async {
      final db = ProgressDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final inserted = await db.insertImportedLocalBook(
        const LocalBookImportDraft(
          bookId: 'local:b1',
          seriesTitle: 'Test Series',
          bookName: 'Vol 1',
          storageKind: 'epub',
          relativePath: 'books/b1/archive.epub',
          sizeBytes: 1024,
          pages: <ArchivePageEntry>[
            ArchivePageEntry(
              number: 1,
              entryName: '01.png',
              uncompressedSize: 10,
            ),
            ArchivePageEntry(
              number: 2,
              entryName: '02.png',
              uncompressedSize: 10,
            ),
            ArchivePageEntry(
              number: 3,
              entryName: '03.png',
              uncompressedSize: 10,
            ),
          ],
          chapters: <ArchiveChapter>[
            ArchiveChapter(title: '序章', startPage: 1),
            ArchiveChapter(title: '第 1 话', startPage: 2),
          ],
        ),
        generateSeriesId: () => 'local:s1',
      );

      final chapters = await db.bookChapters(inserted.bookId);
      expect(chapters, const <BookChapter>[
        BookChapter(title: '序章', startPage: 1),
        BookChapter(title: '第 1 话', startPage: 2),
      ]);

      // 同 bookId 不同 scope 的书签严格隔离
      await db.togglePageBookmark(
        scope: kLocalSourceKey,
        bookId: inserted.bookId,
        page: 3,
      );
      await db.togglePageBookmark(
        scope: 'https://server-a.example',
        bookId: inserted.bookId,
        page: 1,
      );
      expect(
        (await db.pageBookmarks(
          scope: kLocalSourceKey,
          bookId: inserted.bookId,
        )).map((b) => b.page),
        <int>[3],
      );
      expect(
        (await db.pageBookmarks(
          scope: 'https://server-a.example',
          bookId: inserted.bookId,
        )).map((b) => b.page),
        <int>[1],
      );

      // 再次 toggle 移除已有书签
      final stillBookmarked = await db.togglePageBookmark(
        scope: 'https://server-a.example',
        bookId: inserted.bookId,
        page: 1,
      );
      expect(stillBookmarked, isFalse);

      // 删除本地书同步清理章节与本地书签
      await db.deleteLocalBookFromDb(inserted.bookId);
      expect(await db.bookChapters(inserted.bookId), isEmpty);
      expect(
        await db.pageBookmarks(scope: kLocalSourceKey, bookId: inserted.bookId),
        isEmpty,
      );
    });
  });
}
