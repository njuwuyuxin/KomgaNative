import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/local/external_directory_scanner.dart';
import 'package:yomu/src/data/local/external_roots_dao.dart';
import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_platform/yomu_platform.dart';
import 'package:yomu_sync/yomu_sync.dart';

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

void main() {
  group('LMB-09 ExternalDirectoryScanner 后台增量目录扫描与 iOS Files 自发现', () {
    late Directory extDir;
    late Directory sandboxDir;
    late ProgressDatabase db;
    late ExternalDirectoryScanner scanner;

    setUp(() {
      extDir = Directory.systemTemp.createTempSync('yomu_scan_ext_');
      sandboxDir = Directory.systemTemp.createTempSync('yomu_scan_sb_');
      db = ProgressDatabase(NativeDatabase.memory());
      scanner = ExternalDirectoryScanner(
        db: db,
        storage: LocalComicsStorage(rootResolver: () async => sandboxDir),
        bridge: ChannelExternalRootsBridge(),
        coverEncoder: (
          Uint8List raw, {
          required ReadingDirection direction,
        }) async => raw,
      );
    });

    tearDown(() async {
      await db.close();
      if (extDir.existsSync()) extDir.deleteSync(recursive: true);
      if (sandboxDir.existsSync()) sandboxDir.deleteSync(recursive: true);
    });

    test('增量扫描支持首次全量、二次零开销跳过、文件修改保留 bookId/进度、删除清理索引与 iCloud 占位', () async {
      final sub = Directory('${extDir.path}/Frieren')..createSync();
      final vol1 = File('${sub.path}/Vol.1.cbz')
        ..writeAsBytesSync(
          _buildCbz(<String, List<int>>{'01.png': _fakePng(800, 1200)}),
        );
      final vol2 = File('${sub.path}/Vol.2.cbz')
        ..writeAsBytesSync(
          _buildCbz(<String, List<int>>{'01.png': _fakePng(800, 1200)}),
        );
      File('${sub.path}/.Vol.3.cbz.icloud').writeAsBytesSync(<int>[1, 2, 3]);

      final root = MountedExternalRoot(
        id: 'root_test',
        displayName: 'Comics',
        uriOrBookmark: extDir.path,
        kind: ExternalRootKind.localDirectory,
      );
      await db.upsertMountedRoot(root);

      // 1) 首次扫描：新增 3 本（含 1 个 iCloud 占位）
      final first = await scanner.scanRoot(root);
      expect(first.added, 3);
      expect(first.skipped, 0);
      expect(first.cloudPlaceholders, 1);

      final booksAfterFirst = await db.booksForMountedRoot(root.id);
      final vol1Row = booksAfterFirst.firstWhere(
        (b) => b.sourceRelativePath == 'Frieren/Vol.1.cbz',
      );
      // 写入阅读进度，验证后续增量更新保留原 bookId 不丢进度
      await db.enqueue(
        ProgressTarget(bookId: vol1Row.id, page: 1, completed: true),
        scope: kLocalSourceKey,
      );

      // 2) 未变更二次扫描：全部跳过
      final second = await scanner.scanRoot(root);
      expect(second.added, 0);
      expect(second.updated, 0);
      expect(second.skipped, 3);
      expect(second.removed, 0);

      // 3) 修改 Vol.1（增加一页）、删除 Vol.2、新增 Vol.4
      vol1.writeAsBytesSync(
        _buildCbz(<String, List<int>>{
          '01.png': _fakePng(800, 1200),
          '02.png': _fakePng(800, 1200),
        }),
      );
      vol2.deleteSync();
      File('${sub.path}/Vol.4.cbz').writeAsBytesSync(
        _buildCbz(<String, List<int>>{'01.png': _fakePng(800, 1200)}),
      );

      final third = await scanner.scanRoot(root);
      expect(third.added, 1);
      expect(third.updated, 1);
      expect(third.removed, 1);
      expect(third.skipped, 1); // .Vol.3.cbz.icloud 未变

      final booksAfterThird = await db.booksForMountedRoot(root.id);
      final updatedVol1 = booksAfterThird.firstWhere(
        (b) => b.sourceRelativePath == 'Frieren/Vol.1.cbz',
      );
      expect(updatedVol1.id, vol1Row.id);
      expect(updatedVol1.pagesCount, 2);
      final progress = await db.record(updatedVol1.id, scope: kLocalSourceKey);
      expect(progress?.completed, isTrue);
    });

    test(
      'discoverAndScanDocumentsDirectory 自动注册 iOS Files.app 挂载根并入库',
      () async {
        File('${extDir.path}/Bocchi Vol.1.cbz').writeAsBytesSync(
          _buildCbz(<String, List<int>>{'01.png': _fakePng(800, 1200)}),
        );

        final summary = await scanner.discoverAndScanDocumentsDirectory(extDir);
        expect(summary.added, 1);

        final rootRow = await db.mountedRootById(kIosFilesRootId);
        expect(rootRow, isNotNull);
        expect(rootRow!.booksCount, 1);
        expect((await db.queryLocalSeries()).items.single.title, 'Bocchi');
      },
    );

    test('scanRoot 自动识别同级 cover.png 侧车封面绑定到系列且不产生假书', () async {
      final sub = Directory('${extDir.path}/Kimetsu')..createSync();
      final coverBytes = _fakePng(620, 930);
      File('${sub.path}/Vol.1.cbz').writeAsBytesSync(
        _buildCbz(<String, List<int>>{'01.png': _fakePng(800, 1200)}),
      );
      File('${sub.path}/cover.png').writeAsBytesSync(coverBytes);

      final root = MountedExternalRoot(
        id: 'root_cover_test',
        displayName: 'Manga',
        uriOrBookmark: extDir.path,
        kind: ExternalRootKind.localDirectory,
      );
      await db.upsertMountedRoot(root);

      final summary = await scanner.scanRoot(root);
      expect(summary.added, 1);

      final series = (await db.queryLocalSeries()).items.single;
      expect(series.booksCount, 1);
      final seriesRow = await db.localSeriesRowById(series.id);
      expect(seriesRow?.customCoverPath, isNotNull);
      expect(
        File('${sandboxDir.path}/${seriesRow!.customCoverPath}')
            .readAsBytesSync(),
        coverBytes,
      );
    });

    test('损坏压缩包计入 failed 且不阻断同目录其他健康压缩包入库（P2-6）', () async {
      final sub = Directory('${extDir.path}/Mixed')..createSync();
      File('${sub.path}/bad.cbz')
          .writeAsBytesSync(<int>[0x50, 0x4B, 0x03, 0x04]);
      File('${sub.path}/good.cbz').writeAsBytesSync(
        _buildCbz(<String, List<int>>{'01.png': _fakePng(800, 1200)}),
      );

      final root = MountedExternalRoot(
        id: 'root_mixed',
        displayName: 'Mixed',
        uriOrBookmark: extDir.path,
        kind: ExternalRootKind.localDirectory,
      );
      await db.upsertMountedRoot(root);

      final summary = await scanner.scanRoot(root);
      expect(summary.added, 1);
      expect(summary.failed, 1);
      expect((await db.booksForMountedRoot(root.id)), hasLength(1));
    });

    test(
      'SAF/Bridge 外部目录挂载按 ExternalRangeByteSource 入库 saf_zip 并回调进度（P2-6）',
      () async {
        final cbzBytes = _buildCbz(<String, List<int>>{
          '01.png': _fakePng(640, 960),
        });
        final fakeBridge = _FakeSafBridge(
          entries: <ExternalTreeEntry>[
            ExternalTreeEntry(
              uri: 'content://tree/manga/Vol.1.cbz',
              relativePath: 'Naruto/Vol.1.cbz',
              name: 'Vol.1.cbz',
              sizeBytes: cbzBytes.length,
              lastModifiedMs: 1700000000000,
              isDirectory: false,
            ),
          ],
          files: <String, Uint8List>{
            'content://tree/manga/Vol.1.cbz': cbzBytes,
          },
        );
        final safScanner = ExternalDirectoryScanner(
          db: db,
          storage: LocalComicsStorage(rootResolver: () async => sandboxDir),
          bridge: fakeBridge,
          coverEncoder: (
            Uint8List raw, {
            required ReadingDirection direction,
          }) async => raw,
        );
        const root = MountedExternalRoot(
          id: 'root_saf_1',
          displayName: 'SD Card',
          uriOrBookmark: 'content://tree/manga',
          kind: ExternalRootKind.androidSaf,
        );
        await db.upsertMountedRoot(root);

        final progressEvents = <ExternalScanProgress>[];
        final summary = await safScanner.scanRoot(
          root,
          onProgress: progressEvents.add,
        );

        expect(summary.added, 1);
        expect(summary.failed, 0);
        expect(progressEvents.length, greaterThanOrEqualTo(2));
        expect(progressEvents.last.scanned, 1);
        expect(progressEvents.last.total, 1);

        final books = await db.booksForMountedRoot(root.id);
        expect(books, hasLength(1));
        expect(books.single.storageKind, 'saf_zip');
        expect((await db.mountedRootById(root.id))?.booksCount, 1);
      },
    );

    test('多级子目录隔离不同系列与各自侧车封面，且清空目录后 booksCount 归零（P2-6）', () async {
      final dirA = Directory('${extDir.path}/Author/SeriesA')
        ..createSync(recursive: true);
      final dirB = Directory('${extDir.path}/Author/SeriesB')
        ..createSync(recursive: true);
      final coverA = _fakePng(500, 750);
      final coverB = _fakePng(600, 900);
      File('${dirA.path}/Vol.1.cbz').writeAsBytesSync(
        _buildCbz(<String, List<int>>{'01.png': _fakePng(800, 1200)}),
      );
      File('${dirA.path}/cover.png').writeAsBytesSync(coverA);
      File('${dirB.path}/Vol.1.cbz').writeAsBytesSync(
        _buildCbz(<String, List<int>>{'01.png': _fakePng(800, 1200)}),
      );
      File('${dirB.path}/cover.png').writeAsBytesSync(coverB);

      final root = MountedExternalRoot(
        id: 'root_nested',
        displayName: 'Nested',
        uriOrBookmark: extDir.path,
        kind: ExternalRootKind.localDirectory,
      );
      await db.upsertMountedRoot(root);

      final first = await scanner.scanRoot(root);
      expect(first.added, 2);

      final allSeries = (await db.queryLocalSeries()).items;
      expect(allSeries, hasLength(2));

      // 删除外部目录内全部书后复扫：清理全部索引，booksCount 归零。
      File('${dirA.path}/Vol.1.cbz').deleteSync();
      File('${dirB.path}/Vol.1.cbz').deleteSync();
      final second = await scanner.scanRoot(root);
      expect(second.removed, 2);
      expect(await db.booksForMountedRoot(root.id), isEmpty);
      expect((await db.mountedRootById(root.id))?.booksCount, 0);
    });

    test('discoverAndScanDocumentsDirectory 目录不存在时温和返回空统计且不建根（P2-6）', () async {
      final missing = Directory('${extDir.path}/does_not_exist');
      final summary = await scanner.discoverAndScanDocumentsDirectory(missing);
      expect(summary.added, 0);
      expect(summary.failed, 0);
      expect(await db.mountedRootById(kIosFilesRootId), isNull);
    });
  });
}

final class _FakeSafBridge extends ChannelExternalRootsBridge {
  _FakeSafBridge({required this.entries, required this.files});

  final List<ExternalTreeEntry> entries;
  final Map<String, Uint8List> files;

  @override
  Future<List<ExternalTreeEntry>> listTree(MountedExternalRoot root) async =>
      entries;

  @override
  Future<Uint8List?> readFileRange(
    String uri,
    int offset,
    int length, {
    MountedExternalRoot? root,
  }) async {
    final data = files[uri]!;
    final end = (offset + length).clamp(0, data.length);
    return Uint8List.sublistView(data, offset, end);
  }
}
