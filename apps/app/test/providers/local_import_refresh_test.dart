import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/local_import_provider.dart';
import 'package:yomu/src/providers/local_library_center_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu_platform/yomu_platform.dart';

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

Uint8List _fakePng() {
  final b = ByteData(33)
    ..setUint32(8, 13)
    ..setUint32(16, 100)
    ..setUint32(20, 140);
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

class _FakeComicFilePicker implements ComicFilePicker {
  List<PickedComicFile> nextArchives = const <PickedComicFile>[];
  int pickImagePagesCallCount = 0;

  @override
  Future<List<PickedComicFile>> pickArchiveFiles() async => nextArchives;

  @override
  Future<String?> pickComicDirectory() async => null;

  @override
  Future<List<PickedComicFile>> pickImagePages() async {
    pickImagePagesCallCount += 1;
    return const <PickedComicFile>[];
  }

  @override
  Future<void> clearTemporaryCache() async {}
}

class _StubExternalRootsBridge implements ExternalRootsBridge {
  _StubExternalRootsBridge(this.files);

  final Map<String, Uint8List> files;
  final List<String> releasedUris = <String>[];

  @override
  Future<MountedExternalRoot?> pickDirectory() async => null;

  @override
  Future<List<ExternalTreeEntry>> listTree(MountedExternalRoot root) async =>
      files.entries
          .map(
            (e) => ExternalTreeEntry(
              uri: e.key,
              relativePath: e.key,
              name: e.key.split('/').last,
              isDirectory: false,
              sizeBytes: e.value.length,
            ),
          )
          .toList(growable: false);

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
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory srcTemp;
  late Directory sandboxTemp;
  late ProgressDatabase db;
  late _FakeComicFilePicker picker;
  late _StubExternalRootsBridge externalBridge;
  late ProviderContainer container;

  setUp(() async {
    srcTemp = await Directory.systemTemp.createTemp('yomu_import_refresh_src_');
    sandboxTemp = await Directory.systemTemp.createTemp(
      'yomu_import_refresh_box_',
    );
    db = ProgressDatabase(NativeDatabase.memory());
    picker = _FakeComicFilePicker();
    externalBridge = _StubExternalRootsBridge(<String, Uint8List>{});
    final storage = LocalComicsStorage(rootResolver: () async => sandboxTemp);
    final importer = LocalComicImporter(
      db: db,
      storage: storage,
      coverEncoder: (bytes, {required direction}) async => bytes,
    );

    container = ProviderContainer(
      overrides: <Override>[
        progressDatabaseProvider.overrideWithValue(db),
        localComicsStorageProvider.overrideWithValue(storage),
        localComicImporterProvider.overrideWithValue(importer),
        comicFilePickerProvider.overrideWithValue(picker),
        externalRootsBridgeProvider.overrideWithValue(externalBridge),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (await srcTemp.exists()) await srcTemp.delete(recursive: true);
    if (await sandboxTemp.exists()) await sandboxTemp.delete(recursive: true);
  });

  test(
    '已有系列导入新卷后，seriesDetailProvider 与 seriesBooksProvider 立即失效并返回新卷',
    () async {
      final vol1 = File('${srcTemp.path}/Frieren Vol 1.cbz')
        ..writeAsBytesSync(
          _buildCbz(<String, List<int>>{'001.png': _fakePng()}),
        );
      picker.nextArchives = <PickedComicFile>[
        PickedComicFile.fromFile(vol1, name: 'Frieren Vol 1.cbz'),
      ];

      final first = await container
          .read(localImportProvider.notifier)
          .pickAndImportArchives();
      expect(first?.importedCount, 1);
      final seriesId = first!.importedSeriesIds.single;
      final seriesQuery = (sourceKey: null, seriesId: seriesId);
      final query = (
        sourceKey: null,
        seriesId: seriesId,
        sort: null,
        readStatus: null,
      );

      // 模拟用户先打开过一次详情页，令 seriesDetailProvider 与 seriesBooksProvider 进入缓存。
      final detailBefore = await container.read(
        seriesDetailProvider(seriesQuery).future,
      );
      final booksBefore = await container.read(
        seriesBooksProvider(query).future,
      );
      expect(detailBefore?.booksCount, 1);
      expect(booksBefore.items, hasLength(1));

      // 向同一已有系列导入第 2 卷。
      final vol2 = File('${srcTemp.path}/Frieren Vol 2.cbz')
        ..writeAsBytesSync(
          _buildCbz(<String, List<int>>{'001.png': _fakePng()}),
        );
      picker.nextArchives = <PickedComicFile>[
        PickedComicFile.fromFile(vol2, name: 'Frieren Vol 2.cbz'),
      ];

      final second = await container
          .read(localImportProvider.notifier)
          .pickAndImportArchives();
      expect(second?.importedCount, 1);
      expect(second?.importedSeriesIds.single, seriesId);

      // 无需手动下拉刷新，再次读取详情与分卷列表即直接包含新导入的第 2 卷。
      final detailAfter = await container.read(
        seriesDetailProvider(seriesQuery).future,
      );
      final booksAfter = await container.read(
        seriesBooksProvider(query).future,
      );
      expect(detailAfter?.booksCount, 2);
      expect(booksAfter.items, hasLength(2));
    },
  );

  test('通过外部文件打开向已有系列导入新卷后，已缓存的系列详情与分卷列表同样立即更新', () async {
    final vol1 = File('${srcTemp.path}/Dandadan Vol 1.cbz')
      ..writeAsBytesSync(_buildCbz(<String, List<int>>{'001.png': _fakePng()}));
    final first = await container
        .read(localImportProvider.notifier)
        .importExternalFile(vol1.path, fileName: 'Dandadan Vol 1.cbz');
    final seriesId = first!.importedSeriesIds.single;
    final seriesQuery = (sourceKey: null, seriesId: seriesId);
    final query = (
      sourceKey: null,
      seriesId: seriesId,
      sort: null,
      readStatus: null,
    );

    final booksBefore = await container.read(seriesBooksProvider(query).future);
    expect(booksBefore.items, hasLength(1));

    final vol2 = File('${srcTemp.path}/Dandadan Vol 2.cbz')
      ..writeAsBytesSync(_buildCbz(<String, List<int>>{'001.png': _fakePng()}));
    final second = await container
        .read(localImportProvider.notifier)
        .importExternalFile(vol2.path, fileName: 'Dandadan Vol 2.cbz');
    expect(second?.importedSeriesIds.single, seriesId);

    final detailAfter = await container.read(
      seriesDetailProvider(seriesQuery).future,
    );
    final booksAfter = await container.read(seriesBooksProvider(query).future);
    expect(detailAfter?.booksCount, 2);
    expect(booksAfter.items, hasLength(2));
  });

  test('取消选择文件夹时直接返回 null，不再错误回退弹出相册选择器', () async {
    final result = await container
        .read(localImportProvider.notifier)
        .pickAndImportDirectory();
    expect(result, isNull);
    expect(picker.pickImagePagesCallCount, 0);
  });

  test('importExternalDirectoryRoot 导入未挂载 SAF 目录后自动释放临时权限', () async {
    externalBridge.files
      ..clear()
      ..addAll(<String, Uint8List>{
        '00_cover.png': _fakePng(),
        '01.png': _fakePng(),
      });

    const picked = MountedExternalRoot(
      id: 'root_temp_1',
      kind: ExternalRootKind.androidSaf,
      uriOrBookmark: 'content://tree/temp_folder',
      displayName: 'Pepper_and_Carrot_Ep03_Images',
    );
    final result = await container
        .read(localImportProvider.notifier)
        .importExternalDirectoryRoot(picked);

    expect(result?.importedCount, 1);
    expect(externalBridge.releasedUris, <String>['content://tree/temp_folder']);
    await Future<void>.delayed(Duration.zero);
  });
}
