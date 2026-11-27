import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/local/archive_password_store.dart';
import 'package:yomu/src/data/local/comic_reader_factory.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/local_library_repository.dart';
import 'package:yomu/src/data/local/local_reader_repository.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';
import 'package:yomu_platform/yomu_platform.dart';

/// P1-6：LocalStorageKind 枚举解析 + ComicReaderFactory 统一分派（阅读与封面共用）。
void main() {
  test('LocalStorageKind 覆盖全部受管与外部挂载 wireValue 并温和兜底未知值（P1-6）', () {
    for (final kind in LocalStorageKind.values) {
      expect(LocalStorageKind.parse(kind.wireValue), kind);
    }
    expect(LocalStorageKind.parse('unknown_future_kind'), LocalStorageKind.zip);
    expect(LocalStorageKind.pdf.isPdf, isTrue);
    expect(LocalStorageKind.extPdf.isPdf, isTrue);
    expect(LocalStorageKind.safPdf.isPdf, isTrue);
    expect(LocalStorageKind.cb7.isPdf, isFalse);
  });

  test(
    'ComicReaderFactory 统一支持 PDF / CB7 / CBR / 外部挂载，阅读器与封面回退一致（P1-6）',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'yomu_factory_p16_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final db = ProgressDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final storage = LocalComicsStorage(rootResolver: () async => tempDir);
      final passwordStore = ArchivePasswordStore.inMemory();
      await passwordStore.saveBookPassword('b-pdf', 'pdf-secret');
      await passwordStore.saveBookPassword('b-cb7', 'cb7-secret');

      final pdfBytes = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 1, 2]);
      final cb7Bytes = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 3, 4]);
      final fakePdf = _FakePdfBridge(pageBytes: pdfBytes);
      final fakeArchive = _FakeNativeArchiveBridge(pageBytes: cb7Bytes);

      final pdfFile = await storage.resolveFile('books/b-pdf/doc.pdf');
      await pdfFile.parent.create(recursive: true);
      await pdfFile.writeAsBytes(const <int>[0x25, 0x50, 0x44, 0x46]);

      final cb7File = await storage.resolveFile('books/b-cb7/vol.cb7');
      await cb7File.parent.create(recursive: true);
      await cb7File.writeAsBytes(const <int>[0x37, 0x7A, 0xBC, 0xAF]);

      await db.insertImportedLocalBook(
        const LocalBookImportDraft(
          bookId: 'b-pdf',
          seriesTitle: 'PDF Series',
          bookName: 'Doc',
          number: '1',
          numberSort: 1,
          storageKind: 'pdf',
          relativePath: 'books/b-pdf/doc.pdf',
          sizeBytes: 4,
          pages: <ArchivePageEntry>[],
        ),
        generateSeriesId: () => 's-pdf',
      );
      await db.insertImportedLocalBook(
        const LocalBookImportDraft(
          bookId: 'b-cb7',
          seriesTitle: 'CB7 Series',
          bookName: 'Vol 1',
          number: '1',
          numberSort: 1,
          storageKind: 'cb7',
          relativePath: 'books/b-cb7/vol.cb7',
          sizeBytes: 4,
          pages: <ArchivePageEntry>[],
        ),
        generateSeriesId: () => 's-cb7',
      );

      final libraryRepo = LocalLibraryRepository(
        db,
        storage,
        pdfBridge: fakePdf,
        archiveBridge: fakeArchive,
        passwordStore: passwordStore,
      );
      final readerRepo = LocalReaderRepository(
        db,
        storage,
        pdfBridge: fakePdf,
        archiveBridge: fakeArchive,
        passwordStore: passwordStore,
      );
      addTearDown(readerRepo.dispose);

      // 1) PDF：书架封面提取和阅读器读页共用 ComicReaderFactory 并携带已保存密码。
      expect(await libraryRepo.bookCover('b-pdf'), pdfBytes);
      expect(fakePdf.lastPassword, 'pdf-secret');
      expect(await readerRepo.pageImage('b-pdf', 1), pdfBytes);

      // 2) CB7：书架封面提取和阅读器读页同样走 ComicReaderFactory 并携带已保存密码。
      expect(await libraryRepo.bookCover('b-cb7'), cb7Bytes);
      expect(fakeArchive.lastPassword, 'cb7-secret');
      expect(await readerRepo.pageImage('b-cb7', 1), cb7Bytes);

      // 3) 外部挂载目录图片文件夹：无需复制，经 ComicReaderFactory 直接读取。
      final extDir = Directory('${tempDir.path}/ext_comic');
      await extDir.create(recursive: true);
      final extPng = Uint8List.fromList(<int>[
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
        0x02,
        0x00,
        0x00,
        0x00,
        0x90,
        0x77,
        0x53,
        0xDE,
      ]);
      await File('${extDir.path}/001.png').writeAsBytes(extPng);
      await db.insertImportedLocalBook(
        LocalBookImportDraft(
          bookId: 'b-ext-folder',
          seriesTitle: 'Ext Folder',
          bookName: 'Ch 1',
          number: '1',
          numberSort: 1,
          storageKind: LocalStorageKind.extFolder.wireValue,
          relativePath: extDir.path,
          sizeBytes: extPng.length,
          pages: const <ArchivePageEntry>[],
          mountRootId: 'root-1',
        ),
        generateSeriesId: () => 's-ext',
      );
      expect(await libraryRepo.bookCover('b-ext-folder'), extPng);
      expect(await readerRepo.pageImage('b-ext-folder', 1), extPng);

      // 4) CBR：携带已保存密码走原生归档桥提取封面与读页（P2-6）。
      await passwordStore.saveBookPassword('b-cbr', 'cbr-secret');
      final cbrFile = await storage.resolveFile('books/b-cbr/vol.cbr');
      await cbrFile.parent.create(recursive: true);
      await cbrFile.writeAsBytes(const <int>[0x52, 0x61, 0x72, 0x21]);
      await db.insertImportedLocalBook(
        const LocalBookImportDraft(
          bookId: 'b-cbr',
          seriesTitle: 'CBR Series',
          bookName: 'Vol 1',
          number: '1',
          numberSort: 1,
          storageKind: 'cbr',
          relativePath: 'books/b-cbr/vol.cbr',
          sizeBytes: 4,
          pages: <ArchivePageEntry>[],
        ),
        generateSeriesId: () => 's-cbr',
      );
      expect(await libraryRepo.bookCover('b-cbr'), cb7Bytes);
      expect(fakeArchive.lastPassword, 'cbr-secret');
      expect(await readerRepo.pageImage('b-cbr', 1), cb7Bytes);

      // 5) 外部挂载坏文件 / 不存在的文件：封面回退必须返回 null，绝不抛异常打断书架（P2-6）。
      await db.insertImportedLocalBook(
        LocalBookImportDraft(
          bookId: 'b-missing-ext',
          seriesTitle: 'Missing Ext',
          bookName: 'Broken',
          number: '1',
          numberSort: 1,
          storageKind: LocalStorageKind.extZip.wireValue,
          relativePath: '${tempDir.path}/not_there.cbz',
          sizeBytes: 100,
          pages: const <ArchivePageEntry>[],
          mountRootId: 'root-1',
        ),
        generateSeriesId: () => 's-missing',
      );
      expect(await libraryRepo.bookCover('b-missing-ext'), isNull);
      expect(await libraryRepo.seriesCover('s-missing'), isNull);

      // 6) 系列无自定义封面时自动回退到首本的封面提取（P2-6）。
      expect(await libraryRepo.seriesCover('s-pdf'), pdfBytes);
    },
  );
}

final class _FakePdfBridge implements NativePdfBridge {
  _FakePdfBridge({required this.pageBytes});

  final Uint8List pageBytes;
  String? lastPassword;

  @override
  Future<PdfDocumentInfo> inspect(String filePath, {String? password}) async {
    lastPassword = password;
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
  }) async {
    lastPassword = password;
    return pageBytes;
  }

  @override
  Future<void> closeDocument(String filePath) async {}
}

final class _FakeNativeArchiveBridge implements NativeArchiveBridge {
  _FakeNativeArchiveBridge({required this.pageBytes});

  final Uint8List pageBytes;
  String? lastPassword;

  @override
  Future<NativeArchiveListing> listEntries(
    String filePath, {
    String? password,
  }) async {
    lastPassword = password;
    return const NativeArchiveListing(
      format: NativeArchiveFormat.sevenZip,
      isSolid: true,
      entries: <NativeArchiveEntry>[
        NativeArchiveEntry(
          entryName: '001.png',
          uncompressedSize: 6,
          isEncrypted: true,
        ),
      ],
    );
  }

  @override
  Future<Uint8List> extractEntry({
    required String filePath,
    required String entryName,
    String? password,
  }) async {
    lastPassword = password;
    return pageBytes;
  }

  @override
  Future<Map<String, Uint8List>> extractWindow({
    required String filePath,
    required List<String> entryNames,
    String? password,
  }) async {
    lastPassword = password;
    return <String, Uint8List>{for (final name in entryNames) name: pageBytes};
  }

  @override
  Future<void> closeArchive(String filePath) async {}
}
