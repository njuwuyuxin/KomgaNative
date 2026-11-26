import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/data/local/local_comic_importer.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/local_reader_repository.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_platform/yomu_platform.dart';

Uint8List _fakePng(int width, int height, {int extraPadding = 0}) {
  final total = 33 + extraPadding;
  final b = ByteData(total)
    ..setUint32(8, 13)
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
  const gpFlag = 0x0800;

  for (final entry in entries.entries) {
    final offset = out.length;
    final nameBytes = utf8.encode(entry.key);
    final data = Uint8List.fromList(entry.value);

    final lfh = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, gpFlag, Endian.little)
      ..setUint32(18, data.length, Endian.little)
      ..setUint32(22, data.length, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little);
    out
      ..add(lfh.buffer.asUint8List())
      ..add(nameBytes)
      ..add(data);

    final cfh = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, gpFlag, Endian.little)
      ..setUint32(20, data.length, Endian.little)
      ..setUint32(24, data.length, Endian.little)
      ..setUint16(28, nameBytes.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    cd
      ..add(cfh.buffer.asUint8List())
      ..add(nameBytes);
  }

  final cdOffset = out.length;
  final cdBytes = cd.toBytes();
  out.add(cdBytes);
  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, entries.length, Endian.little)
    ..setUint16(10, entries.length, Endian.little)
    ..setUint32(12, cdBytes.length, Endian.little)
    ..setUint32(16, cdOffset, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.toBytes();
}

final class _FakeExternalRootsBridge implements ExternalRootsBridge {
  _FakeExternalRootsBridge(this.files);

  final Map<String, Uint8List> files;
  final List<String> releasedUris = <String>[];

  @override
  Future<MountedExternalRoot?> pickDirectory() async => null;

  @override
  Future<List<ExternalTreeEntry>> listTree(MountedExternalRoot root) async {
    return files.entries
        .map(
          (e) => ExternalTreeEntry(
            uri: e.key,
            relativePath: e.key,
            name: e.key.split('/').last,
            isDirectory: false,
            sizeBytes: e.value.length,
            lastModifiedMs: 1700000000000,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<bool> checkPermission(MountedExternalRoot root) async => true;

  @override
  Future<bool> ensureNomedia(MountedExternalRoot root) async => true;

  @override
  Future<int?> fileLength(String uri, {MountedExternalRoot? root}) async =>
      files[uri]?.length;

  @override
  Future<Uint8List?> readFileRange(
    String uri,
    int offset,
    int length, {
    MountedExternalRoot? root,
  }) async {
    final data = files[uri];
    if (data == null || offset >= data.length) return Uint8List(0);
    final end = (offset + length) > data.length ? data.length : offset + length;
    return Uint8List.sublistView(data, offset, end);
  }

  @override
  Future<bool> triggerCloudDownload(
    String uri, {
    MountedExternalRoot? root,
  }) async => false;

  @override
  Future<void> releasePermission(MountedExternalRoot root) async {
    releasedUris.add(root.uriOrBookmark);
  }
}

void main() {
  group('importExternalDirectory (SAF / Bookmark 目录导入受管沙盒)', () {
    late Directory sandboxTemp;
    late ProgressDatabase db;
    late LocalComicsStorage storage;
    late LocalComicImporter importer;

    setUp(() {
      sandboxTemp = Directory.systemTemp.createTempSync('yomu_ext_dir_box_');
      db = ProgressDatabase(NativeDatabase.memory());
      storage = LocalComicsStorage(rootResolver: () async => sandboxTemp);
      importer = LocalComicImporter(
        db: db,
        storage: storage,
        coverEncoder: (bytes, {required direction}) async => bytes,
      );
    });

    tearDown(() async {
      await db.close();
      if (sandboxTemp.existsSync()) sandboxTemp.deleteSync(recursive: true);
    });

    test('流式导入含子目录图片与 ComicInfo.xml 的 SAF 图片文件夹（含超过 256KB 分块拷贝）', () async {
      final largePage = _fakePng(1000, 1500, extraPadding: 300 * 1024);
      final bridge = _FakeExternalRootsBridge(<String, Uint8List>{
        '00_cover.png': _fakePng(800, 1200),
        'Ch01/E03P00.png': largePage,
        'Ch01/E03P01.png': _fakePng(900, 1300),
        'ComicInfo.xml': Uint8List.fromList(
          utf8.encode(
            '<ComicInfo><Series>Pepper &amp; Carrot</Series><Title>Episode 3</Title></ComicInfo>',
          ),
        ),
        'notes.txt': Uint8List.fromList(utf8.encode('ignored')),
      });
      const root = MountedExternalRoot(
        id: 'root_test_1',
        kind: ExternalRootKind.androidSaf,
        uriOrBookmark: 'content://com.android.externalstorage.documents/tree/primary%3ADownload%2FPepper',
        displayName: 'Pepper_and_Carrot_Ep03_Images',
      );

      final result = await importer.importExternalDirectory(root, bridge);
      expect(result.importedCount, 1);
      expect(result.failures, isEmpty);

      final series = (await db.queryLocalSeries()).items.single;
      expect(series.title, 'Pepper & Carrot');
      final bookRow = await db.localBookRowById(result.importedBookIds.single);
      expect(bookRow?.storageKind, 'folder');
      expect(bookRow?.pagesCount, 3);

      final readerRepo = LocalReaderRepository(db, storage);
      final page2 = await readerRepo.pageImage(bookRow!.id, 2);
      expect(page2.length, largePage.length);
    });

    test('SAF 目录内含归档与同级 cover.png 时按分卷导入并绑定系列封面', () async {
      final cbz = _buildCbz(<String, List<int>>{
        '001.png': _fakePng(800, 1200),
      });
      final sidecar = _fakePng(640, 960);
      final bridge = _FakeExternalRootsBridge(<String, Uint8List>{
        'Vol. 1.cbz': cbz,
        'cover.png': sidecar,
      });
      const root = MountedExternalRoot(
        id: 'root_test_2',
        kind: ExternalRootKind.androidSaf,
        uriOrBookmark: 'content://tree/demo_series',
        displayName: 'DemoSeries',
      );

      final result = await importer.importExternalDirectory(root, bridge);
      expect(result.importedCount, 1);
      expect(result.failures, isEmpty);

      final seriesRow = await db.localSeriesRowById(
        result.importedSeriesIds.single,
      );
      expect(seriesRow?.title, 'DemoSeries');
      expect(seriesRow?.customCoverPath, isNotNull);
      expect(
        File('${sandboxTemp.path}/${seriesRow!.customCoverPath}')
            .readAsBytesSync(),
        sidecar,
      );
    });

    test('无图片且无归档的空 SAF 目录返回 noImages 失败项', () async {
      final bridge = _FakeExternalRootsBridge(<String, Uint8List>{
        'readme.txt': Uint8List.fromList(utf8.encode('empty')),
      });
      const root = MountedExternalRoot(
        id: 'root_test_3',
        kind: ExternalRootKind.androidSaf,
        uriOrBookmark: 'content://tree/empty',
        displayName: 'EmptyFolder',
      );

      final result = await importer.importExternalDirectory(root, bridge);
      expect(result.importedCount, 0);
      expect(result.failures.single.reason, ImportFailureReason.noImages);
      expect(result.failures.single.fileName, 'EmptyFolder');
    });
  });
}
