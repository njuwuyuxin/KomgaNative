import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/local/archive_password_store.dart';
import 'package:yomu/src/data/local/local_archive_import_stream.dart';
import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';
import 'package:yomu_platform/yomu_platform.dart';

void main() {
  group('P0-4 导入写库后失败必须回滚数据库与磁盘，不留幽灵书', () {
    late Directory tempRoot;
    late ProgressDatabase db;
    late LocalComicsStorage storage;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('yomu_p04_');
      db = ProgressDatabase(NativeDatabase.memory());
      storage = LocalComicsStorage(
        rootResolver: () async => Directory('${tempRoot.path}/local_comics'),
      );
    });

    tearDown(() async {
      await db.close();
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    test('加密 CBZ 写库后 saveBookPassword 抛错：回滚数据库记录、封面并删除文件目录', () async {
      final zipBytes = _buildEncryptedZip('01.png', _fakePng(), 'pw123');
      final throwingStore = ArchivePasswordStore(
        storage: const _ThrowingSecureStorage(),
      );

      await expectLater(
        () => importArchiveOrCollectionStream(
          db: db,
          storage: storage,
          coverEncoder: (
            Uint8List raw, {
            required ReadingDirection direction,
          }) async => raw,
          openStream: () => Stream<List<int>>.value(zipBytes),
          displayFileName: 'Secret Vol.1.cbz',
          parentFolderName: null,
          nextId: (String prefix) => '${prefix}_test_1',
          passwordStore: throwingStore,
          password: 'pw123',
        ),
        throwsStateError,
      );

      expect(await db.localBookById('b_test_1'), isNull);
      expect(await db.select(db.localSeriesRows).get(), isEmpty);
      final booksDir = await storage.resolveDirectory('books/b_test_1');
      expect(await booksDir.exists(), isFalse);
      final coversDir = await storage.resolveDirectory('covers');
      if (await coversDir.exists()) {
        expect(coversDir.listSync(), isEmpty);
      }
    });

    test('PDF 写库后 reader.close() 抛错：回滚数据库记录并删除文件目录，且不二次抛错覆盖原异常', () async {
      final pdfHeader = Uint8List.fromList(utf8.encode('%PDF-1.7\n%dummy\n'));
      final bridge = _CloseFailingPdfBridge(_fakePng());

      await expectLater(
        () => importArchiveOrCollectionStream(
          db: db,
          storage: storage,
          coverEncoder: (
            Uint8List raw, {
            required ReadingDirection direction,
          }) async => raw,
          openStream: () => Stream<List<int>>.value(pdfHeader),
          displayFileName: 'BrokenClose.pdf',
          parentFolderName: null,
          nextId: (String prefix) => '${prefix}_pdf_1',
          pdfBridge: bridge,
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(await db.localBookById('b_pdf_1'), isNull);
      expect(await db.select(db.localSeriesRows).get(), isEmpty);
      final booksDir = await storage.resolveDirectory('books/b_pdf_1');
      expect(await booksDir.exists(), isFalse);
    });
  });
}

final class _ThrowingSecureStorage extends FlutterSecureStorage {
  const _ThrowingSecureStorage();

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw StateError('keychain write failed');
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}
}

final class _CloseFailingPdfBridge implements NativePdfBridge {
  _CloseFailingPdfBridge(this._pageBytes);

  final Uint8List _pageBytes;

  @override
  Future<PdfDocumentInfo> inspect(String filePath, {String? password}) async {
    return const PdfDocumentInfo(
      pageCount: 1,
      pages: <PdfPageMetrics>[
        PdfPageMetrics(pageNumber: 1, widthPt: 800, heightPt: 1200),
      ],
    );
  }

  @override
  Future<Uint8List> renderPage({
    required String filePath,
    required int pageNumber,
    required int targetWidthPx,
    String? password,
  }) async => _pageBytes;

  @override
  Future<void> closeDocument(String filePath) async {
    throw const FileSystemException('close handle failed');
  }
}

Uint8List _fakePng() {
  final b = ByteData(33)
    ..setUint32(8, 13)
    ..setUint32(16, 800)
    ..setUint32(20, 1200);
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

Uint8List _buildEncryptedZip(String name, Uint8List plain, String password) {
  final pwd = Uint8List.fromList(utf8.encode(password));
  final crc = computeCrc32(plain);
  final encrypted = encryptZipCryptoPayload(
    plain,
    passwordBytes: pwd,
    checkByte: (crc >> 24) & 0xFF,
  );
  final nameBytes = Uint8List.fromList(utf8.encode(name));
  final out = BytesBuilder(copy: false);

  final lfh = ByteData(30)
    ..setUint32(0, 0x04034b50, Endian.little)
    ..setUint16(4, 20, Endian.little)
    ..setUint16(6, 0x0801, Endian.little)
    ..setUint16(8, 0, Endian.little)
    ..setUint32(14, crc, Endian.little)
    ..setUint32(18, encrypted.length, Endian.little)
    ..setUint32(22, plain.length, Endian.little)
    ..setUint16(26, nameBytes.length, Endian.little)
    ..setUint16(28, 0, Endian.little);
  out
    ..add(lfh.buffer.asUint8List())
    ..add(nameBytes)
    ..add(encrypted);

  final cdOffset = out.length;
  final cfh = ByteData(46)
    ..setUint32(0, 0x02014b50, Endian.little)
    ..setUint16(4, 20, Endian.little)
    ..setUint16(6, 20, Endian.little)
    ..setUint16(8, 0x0801, Endian.little)
    ..setUint16(10, 0, Endian.little)
    ..setUint32(16, crc, Endian.little)
    ..setUint32(20, encrypted.length, Endian.little)
    ..setUint32(24, plain.length, Endian.little)
    ..setUint16(28, nameBytes.length, Endian.little)
    ..setUint16(30, 0, Endian.little)
    ..setUint16(32, 0, Endian.little)
    ..setUint32(42, 0, Endian.little);
  final cd = BytesBuilder(copy: false)
    ..add(cfh.buffer.asUint8List())
    ..add(nameBytes);
  final cdBytes = cd.toBytes();
  out.add(cdBytes);

  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, 1, Endian.little)
    ..setUint16(10, 1, Endian.little)
    ..setUint32(12, cdBytes.length, Endian.little)
    ..setUint32(16, cdOffset, Endian.little)
    ..setUint16(20, 0, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.toBytes();
}
