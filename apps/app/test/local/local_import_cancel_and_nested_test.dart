import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/providers/local_import_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_domain/yomu_domain.dart';

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

Uint8List _buildStoredZip(Map<String, List<int>> entries) {
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
  group('P2-8 批量导入取消与嵌套合集全失败保留原压缩包', () {
    late Directory sandboxDir;
    late ProgressDatabase db;
    late LocalComicsStorage storage;
    late LocalComicImporter importer;

    setUp(() {
      sandboxDir = Directory.systemTemp.createTempSync('yomu_p28_');
      db = ProgressDatabase(NativeDatabase.memory());
      storage = LocalComicsStorage(rootResolver: () async => sandboxDir);
      importer = LocalComicImporter(
        db: db,
        storage: storage,
        coverEncoder: (
          Uint8List raw, {
          required ReadingDirection direction,
        }) async => raw,
      );
    });

    tearDown(() async {
      await db.close();
      if (sandboxDir.existsSync()) sandboxDir.deleteSync(recursive: true);
    });

    test('批量导入中途取消：保留已入库书籍、立即中止后续项并标记 cancelled', () async {
      final goodZip = _buildStoredZip(<String, List<int>>{
        '01.png': _fakePng(800, 1200),
      });
      final token = ImportCancellationToken();

      final files = <PickedComicFile>[
        PickedComicFile(
          name: 'Vol.1.cbz',
          sizeBytes: goodZip.length,
          openRead: () => Stream<Uint8List>.value(goodZip),
        ),
        PickedComicFile(
          name: 'Vol.2.cbz',
          sizeBytes: goodZip.length,
          openRead: () => Stream<Uint8List>.value(goodZip),
        ),
        PickedComicFile(
          name: 'Vol.3.cbz',
          sizeBytes: goodZip.length,
          openRead: () => Stream<Uint8List>.value(goodZip),
        ),
      ];

      final result = await importer.importArchiveFiles(
        files,
        cancelToken: token,
        onProgress: (int completed, int total, String currentName) {
          // 第一本开始后即请求取消：第二本不得被导入。
          if (completed == 1) token.cancel();
        },
      );

      expect(result.cancelled, isTrue);
      expect(result.importedCount, 1);
      final series = (await db.queryLocalSeries()).items;
      expect(series, hasLength(1));
      expect(series.single.booksCount, 1);
    });

    test('LocalImportController.cancelImport 立即取消进行中的批量导入并释放 busy 锁', () async {
      final goodZip = _buildStoredZip(<String, List<int>>{
        '01.png': _fakePng(800, 1200),
      });
      final secondGate = Completer<void>();
      final secondStarted = Completer<void>();

      final picker = _StubPicker(
        batches: <List<PickedComicFile>>[
          <PickedComicFile>[
            PickedComicFile(
              name: 'First.cbz',
              sizeBytes: goodZip.length,
              openRead: () => Stream<Uint8List>.value(goodZip),
            ),
            PickedComicFile(
              name: 'Slow.cbz',
              sizeBytes: goodZip.length,
              openRead: () async* {
                secondStarted.complete();
                await secondGate.future;
                yield goodZip;
              },
            ),
          ],
          <PickedComicFile>[
            PickedComicFile(
              name: 'NextBatch.cbz',
              sizeBytes: goodZip.length,
              openRead: () => Stream<Uint8List>.value(goodZip),
            ),
          ],
        ],
      );

      final container = ProviderContainer(
        overrides: <Override>[
          serverStoreProvider.overrideWithValue(InMemoryServerStore()),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          progressDatabaseProvider.overrideWithValue(db),
          localComicsStorageProvider.overrideWithValue(storage),
          comicFilePickerProvider.overrideWithValue(picker),
          localComicImporterProvider.overrideWithValue(importer),
        ],
      );
      addTearDown(container.dispose);

      final ctrl = container.read(localImportProvider.notifier);
      final firstRun = ctrl.pickAndImportArchives();
      await secondStarted.future;

      expect(container.read(localImportProvider).busy, isTrue);
      ctrl.cancelImport();
      expect(container.read(localImportProvider).cancelling, isTrue);

      secondGate.complete();
      final firstResult = await firstRun;
      expect(firstResult?.cancelled, isTrue);
      expect(firstResult?.importedCount, 1);
      expect(container.read(localImportProvider).busy, isFalse);
      expect(container.read(localImportProvider).cancelling, isFalse);

      // 取消后可立刻发起新一轮导入，不再被 busy 锁死。
      final secondResult = await ctrl.pickAndImportArchives();
      expect(secondResult?.cancelled, isFalse);
      expect(secondResult?.importedCount, 1);
    });

    test('嵌套合集所有子书都失败时保留外层原压缩包，不默默删除', () async {
      final brokenChild = Uint8List.fromList(<int>[0x50, 0x4B, 0x03, 0x04]);
      final nestedCollection = _buildStoredZip(<String, List<int>>{
        'broken1.cbz': brokenChild,
        'broken2.cbz': brokenChild,
      });

      final result = await importer.importArchiveFiles(<PickedComicFile>[
        PickedComicFile(
          name: 'BrokenPack.zip',
          sizeBytes: nestedCollection.length,
          openRead: () => Stream<Uint8List>.value(nestedCollection),
        ),
      ]);

      expect(result.importedCount, 0);
      expect(result.failures, hasLength(2));
      expect(result.preservedArchivePaths, hasLength(1));
      final preservedFile = File(result.preservedArchivePaths.single);
      expect(preservedFile.existsSync(), isTrue);
      expect(preservedFile.lengthSync(), nestedCollection.length);
    });

    test('嵌套合集至少拆出一本成功子书时清理外层原压缩包避免双份占盘', () async {
      final goodChild = _buildStoredZip(<String, List<int>>{
        '01.png': _fakePng(800, 1200),
      });
      final brokenChild = Uint8List.fromList(<int>[0x50, 0x4B, 0x03, 0x04]);
      final mixedCollection = _buildStoredZip(<String, List<int>>{
        'Vol.1.cbz': goodChild,
        'Vol.2.cbz': brokenChild,
      });

      final result = await importer.importArchiveFiles(<PickedComicFile>[
        PickedComicFile(
          name: 'MixedPack.zip',
          sizeBytes: mixedCollection.length,
          openRead: () => Stream<Uint8List>.value(mixedCollection),
        ),
      ]);

      expect(result.importedCount, 1);
      expect(result.failures, hasLength(1));
      expect(result.preservedArchivePaths, isEmpty);
    });
  });
}

final class _StubPicker implements ComicFilePicker {
  _StubPicker({required this.batches});

  final List<List<PickedComicFile>> batches;
  int _idx = 0;

  @override
  Future<List<PickedComicFile>> pickArchiveFiles() async =>
      _idx < batches.length ? batches[_idx++] : const <PickedComicFile>[];

  @override
  Future<String?> pickComicDirectory() async => null;

  @override
  Future<List<PickedComicFile>> pickImagePages() async =>
      const <PickedComicFile>[];

  @override
  Future<void> clearTemporaryCache() async {}
}
