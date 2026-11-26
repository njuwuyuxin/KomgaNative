import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;
import 'package:yomu/src/data/local/external_byte_source.dart';
import 'package:yomu/src/data/local/external_roots_dao.dart';
import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/local_reader_repository.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';
import 'package:yomu_platform/yomu_platform.dart';

Uint8List _fakePng(int width, int height) {
  final b = ByteData(32)
    ..setUint32(16, width)
    ..setUint32(20, height);
  final bytes = b.buffer.asUint8List();
  bytes.setRange(0, 8, const <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ]);
  bytes.setRange(12, 16, const <int>[0x49, 0x48, 0x44, 0x52]);
  return bytes;
}

Uint8List _buildCbz(Map<String, List<int>> entries) {
  final out = BytesBuilder();
  final cd = BytesBuilder();
  for (final e in entries.entries) {
    final offset = out.length;
    final nameBytes = utf8.encode(e.key);
    final data = Uint8List.fromList(e.value);
    final lfh = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 0x0800, Endian.little)
      ..setUint16(8, 0, Endian.little)
      ..setUint32(18, data.length, Endian.little)
      ..setUint32(22, data.length, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little);
    out
      ..add(lfh.buffer.asUint8List())
      ..add(nameBytes)
      ..add(data);

    final cdfh = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0x0800, Endian.little)
      ..setUint16(10, 0, Endian.little)
      ..setUint32(20, data.length, Endian.little)
      ..setUint32(24, data.length, Endian.little)
      ..setUint16(28, nameBytes.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    cd
      ..add(cdfh.buffer.asUint8List())
      ..add(nameBytes);
  }
  final cdOffset = out.length;
  final cdBytes = cd.takeBytes();
  out.add(cdBytes);
  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, entries.length, Endian.little)
    ..setUint16(10, entries.length, Endian.little)
    ..setUint32(12, cdBytes.length, Endian.little)
    ..setUint32(16, cdOffset, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.takeBytes();
}

final class _FakeCloudBridge extends ChannelExternalRootsBridge {
  final List<String> cloudDownloadRequests = <String>[];

  @override
  Future<bool> triggerCloudDownload(
    String uri, {
    MountedExternalRoot? root,
  }) async {
    cloudDownloadRequests.add(uri);
    return true;
  }
}

void main() {
  group('LMB-08 外部目录原位挂载与零拷贝读取', () {
    test(
      'schema v5 升级至 v6 创建 local_mounted_roots_rows 并扩展 local_books_rows',
      () async {
        final temp = Directory.systemTemp.createTempSync('yomu_v5_to_v6_');
        addTearDown(() => temp.deleteSync(recursive: true));
        final dbFile = File('${temp.path}/komga_native.sqlite');

        final raw = raw_sqlite.sqlite3.open(dbFile.path);
        try {
          raw.execute('''
          CREATE TABLE local_progress (scope TEXT NOT NULL DEFAULT '', book_id TEXT NOT NULL, page INTEGER NOT NULL, completed INTEGER NOT NULL, updated_at INTEGER NOT NULL, server_last_modified INTEGER NULL, pending_seq INTEGER NULL, PRIMARY KEY (scope, book_id));
          CREATE TABLE pinned_series_rows (server_id TEXT NOT NULL, series_id TEXT NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY (server_id, series_id));
          CREATE TABLE reading_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, scope TEXT NOT NULL DEFAULT '', book_id TEXT NOT NULL, series_id TEXT NOT NULL, book_name TEXT NOT NULL DEFAULT '', started_at INTEGER NOT NULL, ended_at INTEGER NOT NULL, duration_ms INTEGER NOT NULL, start_page INTEGER NOT NULL DEFAULT 1, end_page INTEGER NOT NULL DEFAULT 1, completed INTEGER NOT NULL DEFAULT 0);
          CREATE TABLE local_series_rows (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, title_sort TEXT NOT NULL, summary TEXT NOT NULL DEFAULT '', publisher TEXT NOT NULL DEFAULT '', authors_json TEXT NOT NULL DEFAULT '[]', tags_json TEXT NOT NULL DEFAULT '[]', reading_direction TEXT NOT NULL DEFAULT 'unknown', cover_book_id TEXT NULL, custom_cover_path TEXT NULL, metadata_locked INTEGER NOT NULL DEFAULT 0, release_date INTEGER NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
          CREATE TABLE local_books_rows (id TEXT NOT NULL PRIMARY KEY, series_id TEXT NOT NULL, name TEXT NOT NULL, number TEXT NOT NULL DEFAULT '', number_sort REAL NOT NULL DEFAULT 0.0, pages_count INTEGER NOT NULL, size_bytes INTEGER NOT NULL, storage_kind TEXT NOT NULL, relative_path TEXT NOT NULL, cover_thumb_path TEXT NULL, release_date INTEGER NULL, created_at INTEGER NOT NULL);
          CREATE TABLE local_pages_rows (book_id TEXT NOT NULL, page_number INTEGER NOT NULL, entry_name TEXT NOT NULL, local_header_offset INTEGER NOT NULL DEFAULT 0, compressed_size INTEGER NOT NULL DEFAULT 0, uncompressed_size INTEGER NOT NULL DEFAULT 0, compression_method INTEGER NOT NULL DEFAULT 0, width INTEGER NULL, height INTEGER NULL, media_type TEXT NULL, PRIMARY KEY (book_id, page_number));
          CREATE TABLE local_book_chapters_rows (book_id TEXT NOT NULL, chapter_index INTEGER NOT NULL, title TEXT NOT NULL, start_page INTEGER NOT NULL, PRIMARY KEY (book_id, chapter_index));
          CREATE TABLE local_collections_rows (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, ordered INTEGER NOT NULL DEFAULT 0, series_ids_json TEXT NOT NULL DEFAULT '[]', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
          CREATE TABLE local_read_lists_rows (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, summary TEXT NOT NULL DEFAULT '', ordered INTEGER NOT NULL DEFAULT 0, book_ids_json TEXT NOT NULL DEFAULT '[]', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
          CREATE TABLE page_bookmarks_rows (scope TEXT NOT NULL DEFAULT '', book_id TEXT NOT NULL, page INTEGER NOT NULL, note TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL, PRIMARY KEY (scope, book_id, page));
          PRAGMA user_version = 5;
        ''');
        } finally {
          raw.close();
        }

        final db = ProgressDatabase(NativeDatabase(dbFile));
        addTearDown(db.close);

        await db.upsertMountedRoot(
          const MountedExternalRoot(
            id: 'root_1',
            displayName: 'SD Comics',
            uriOrBookmark: 'content://tree/1',
            kind: ExternalRootKind.androidSaf,
            hasNomedia: true,
          ),
        );
        final roots = await db.allMountedRoots();
        expect(roots, hasLength(1));
        expect(roots.single.displayName, 'SD Comics');
        expect(roots.single.hasNomedia, isTrue);
      },
    );

    test('原位挂载 CBZ 支持零拷贝区间读、卸载时不删原始外部文件，iCloud 占位打开时触发云端下载', () async {
      final externalDir = Directory.systemTemp.createTempSync('yomu_ext_dir_');
      final sandboxDir = Directory.systemTemp.createTempSync('yomu_ext_sb_');
      addTearDown(() {
        if (externalDir.existsSync()) externalDir.deleteSync(recursive: true);
        if (sandboxDir.existsSync()) sandboxDir.deleteSync(recursive: true);
      });

      final p1 = _fakePng(800, 1200);
      final p2 = _fakePng(800, 1200);
      final cbzFile = File('${externalDir.path}/Vol.1.cbz')
        ..writeAsBytesSync(
          _buildCbz(<String, List<int>>{'01.png': p1, '02.png': p2}),
        );

      final db = ProgressDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final bridge = _FakeCloudBridge();
      final root = MountedExternalRoot(
        id: 'root_ext',
        displayName: 'External',
        uriOrBookmark: externalDir.path,
        kind: ExternalRootKind.localDirectory,
      );
      await db.upsertMountedRoot(root);

      // 使用 ExternalRangeByteSource 原位打开外部 CBZ（不拷贝进沙盒）
      final rangeSource = ExternalRangeByteSource(
        bridge: bridge,
        uri: cbzFile.path,
        root: root,
      );
      final archiveReader = await openComicArchive(rangeSource);
      await db.insertImportedLocalBook(
        LocalBookImportDraft(
          bookId: 'local:ext_b1',
          seriesTitle: 'External Manga',
          bookName: 'Vol.1',
          storageKind: 'saf_zip',
          relativePath: cbzFile.path,
          sizeBytes: cbzFile.lengthSync(),
          pages: archiveReader.pages,
          mountRootId: root.id,
          sourceRelativePath: 'Vol.1.cbz',
          sourceModifiedMs: cbzFile.lastModifiedSync().millisecondsSinceEpoch,
        ),
        generateSeriesId: () => 'local:ext_s1',
      );
      await archiveReader.close();

      // LocalReaderRepository 零拷贝直读原位文件
      final readerRepo = LocalReaderRepository(
        db,
        LocalComicsStorage(rootResolver: () async => sandboxDir),
        externalRoots: bridge,
      );
      addTearDown(readerRepo.dispose);
      expect(await readerRepo.pageImage('local:ext_b1', 2), p2);
      expect(Directory('${sandboxDir.path}/books').existsSync(), isFalse);

      // iCloud 占位文件打开时主动触发 triggerCloudDownload
      await db.insertImportedLocalBook(
        const LocalBookImportDraft(
          bookId: 'local:cloud_b2',
          seriesTitle: 'External Manga',
          bookName: 'Vol.2',
          storageKind: 'saf_zip',
          relativePath: '/icloud/.Vol.2.cbz.icloud',
          sizeBytes: 0,
          pages: <ArchivePageEntry>[],
          mountRootId: 'root_ext',
          sourceRelativePath: 'Vol.2.cbz',
          isCloudPlaceholder: true,
        ),
        generateSeriesId: () => 'local:ext_s1',
      );
      await expectLater(
        () => readerRepo.pages('local:cloud_b2'),
        throwsA(anything),
      );
      expect(bridge.cloudDownloadRequests, <String>[
        '/icloud/.Vol.2.cbz.icloud',
      ]);

      // 卸载外部挂载目录仅清库索引，绝不删用户原始 CBZ 文件
      await readerRepo.closeBookHandle('local:ext_b1');
      await db.unmountExternalRootFromDb(root.id);
      expect(await db.allMountedRoots(), isEmpty);
      expect((await db.queryLocalSeries()).items, isEmpty);
      expect(cbzFile.existsSync(), isTrue);
    });
  });
}
