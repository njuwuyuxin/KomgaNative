import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/app.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/incoming_files_provider.dart';
import 'package:yomu/src/providers/local_import_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/screens/reader_screen.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_platform/yomu_platform.dart';

import 'support/fake_library.dart';
import 'support/fake_reader.dart';

class _FakeIncomingFiles implements IncomingFiles {
  _FakeIncomingFiles(this._initial);

  List<IncomingComicFile> _initial;
  final StreamController<IncomingComicFile> _ctrl =
      StreamController<IncomingComicFile>.broadcast();

  @override
  Future<List<IncomingComicFile>> consumeInitialFiles() async {
    final items = _initial;
    _initial = const <IncomingComicFile>[];
    return items;
  }

  @override
  Stream<IncomingComicFile> get stream => _ctrl.stream;

  @override
  void dispose() {
    unawaited(_ctrl.close());
  }
}

class _FakeCoordinator extends IncomingComicCoordinator {
  _FakeCoordinator(super.ref, this.importedBookId);

  final String importedBookId;
  final List<String> handledNames = <String>[];

  @override
  Future<String?> handleIncomingFile(IncomingComicFile incoming) async {
    handledNames.add(incoming.name);
    return importedBookId;
  }
}

Uint8List _validOnePageCbz() {
  const onePixelPng = <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ];
  final name = '01.png'.codeUnits;
  final out = BytesBuilder();
  final lfh = ByteData(30)
    ..setUint32(0, 0x04034b50, Endian.little)
    ..setUint16(4, 20, Endian.little)
    ..setUint32(18, onePixelPng.length, Endian.little)
    ..setUint32(22, onePixelPng.length, Endian.little)
    ..setUint16(26, name.length, Endian.little);
  out
    ..add(lfh.buffer.asUint8List())
    ..add(name)
    ..add(onePixelPng);
  final cdOffset = out.length;
  final cfh = ByteData(46)
    ..setUint32(0, 0x02014b50, Endian.little)
    ..setUint16(4, 20, Endian.little)
    ..setUint16(6, 20, Endian.little)
    ..setUint32(20, onePixelPng.length, Endian.little)
    ..setUint32(24, onePixelPng.length, Endian.little)
    ..setUint16(28, name.length, Endian.little)
    ..setUint32(42, 0, Endian.little);
  out
    ..add(cfh.buffer.asUint8List())
    ..add(name);
  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, 1, Endian.little)
    ..setUint16(10, 1, Endian.little)
    ..setUint32(12, 46 + name.length, Endian.little)
    ..setUint32(16, cdOffset, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.toBytes();
}

void main() {
  group('LMA-12 外部文件关联与打开入库', () {
    test('IncomingComicCoordinator 导入外部 .cbz 入库并清理 incoming/ 临时文件', () async {
      final tempRoot = Directory.systemTemp.createTempSync('yomu_openwith_io_');
      addTearDown(() {
        if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
      });

      final incomingDir = Directory('${tempRoot.path}/incoming')..createSync();
      final sandboxDir = Directory('${tempRoot.path}/sandbox')..createSync();
      final incomingFile = File('${incomingDir.path}/External_Vol1.cbz')
        ..writeAsBytesSync(_validOnePageCbz());

      final db = ProgressDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final storage = LocalComicsStorage(rootResolver: () async => sandboxDir);

      final container = ProviderContainer(
        overrides: <Override>[
          progressDatabaseProvider.overrideWithValue(db),
          localComicsStorageProvider.overrideWithValue(storage),
          localComicImporterProvider.overrideWithValue(
            LocalComicImporter(
              db: db,
              storage: storage,
              coverEncoder: (
                raw, {
                required ReadingDirection direction,
              }) async => raw,
            ),
          ),
          serverStoreProvider.overrideWithValue(InMemoryServerStore()),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        ],
      );
      addTearDown(container.dispose);

      final bookId = await container
          .read(incomingComicCoordinatorProvider)
          .handleIncomingFile(
            IncomingComicFile(
              path: incomingFile.path,
              name: 'External Vol.1.cbz',
            ),
          );
      expect(bookId, isNotNull);
      expect(bookId, startsWith('local:b_'));
      expect(
        incomingFile.existsSync(),
        isFalse,
        reason: 'incoming/ 临时中转文件入库后应立即清理',
      );
    });

    testWidgets('IncomingFileScope 在启动守卫就绪后自动消费外部文件并打开阅读器路由', (
      WidgetTester tester,
    ) async {
      final db = ProgressDatabase(NativeDatabase.memory());
      final cacheDb = HttpCacheDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await db.close();
        await cacheDb.close();
      });

      final fakeIncoming = _FakeIncomingFiles(<IncomingComicFile>[
        const IncomingComicFile(
          path: '/tmp/incoming/test.cbz',
          name: 'External Vol.1.cbz',
        ),
      ]);
      late _FakeCoordinator coordinator;
      final localBundle = SourceBundle(
        source: const LocalContentSource(),
        library: FakeLibraryRepository(),
        reader: FakeReaderRepository(pageCount: 5),
        collections: FakeLibraryRepository(),
        readStatus: FakeLibraryRepository(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            progressDatabaseProvider.overrideWithValue(db),
            httpCacheDatabaseProvider.overrideWithValue(cacheDb),
            incomingFilesProvider.overrideWithValue(fakeIncoming),
            incomingComicCoordinatorProvider.overrideWith((Ref ref) {
              return coordinator = _FakeCoordinator(ref, 'local:b_ext1');
            }),
            sourceRegistryProvider.overrideWithValue(
              SourceRegistry(
                localBundle: localBundle,
                remoteBundles: const <String, SourceBundle>{},
              ),
            ),
            serverStoreProvider.overrideWithValue(InMemoryServerStore()),
            settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          ],
          child: const KomgaApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(coordinator.handledNames, const <String>['External Vol.1.cbz']);
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(find.text('1 / 5'), findsWidgets);
    });
  });
}
