import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/local/comic_file_picker.dart';
import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/data/local/local_comic_importer.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/local_reader_repository.dart';
import 'package:yomu/src/data/progress/bookmarks_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_platform/yomu_platform.dart';

final class _FakePdfBridge implements NativePdfBridge {
  _FakePdfBridge({this.requiredPassword});

  final String? requiredPassword;
  final List<int> requestedWidths = <int>[];

  @override
  Future<PdfDocumentInfo> inspect(String filePath, {String? password}) async {
    if (requiredPassword != null && password != requiredPassword) {
      throw const PdfPlatformException(
        PdfOpenErrorKind.invalidPassword,
        'Locked PDF',
      );
    }
    return const PdfDocumentInfo(
      pageCount: 3,
      title: 'Ghibli Artbook',
      author: 'Studio',
      pages: <PdfPageMetrics>[
        PdfPageMetrics(pageNumber: 1, widthPt: 600, heightPt: 850),
        PdfPageMetrics(pageNumber: 2, widthPt: 1200, heightPt: 850),
        PdfPageMetrics(pageNumber: 3, widthPt: 600, heightPt: 850),
      ],
      outline: <PdfOutlineItem>[
        PdfOutlineItem(title: 'Cover', startPage: 1),
        PdfOutlineItem(title: 'Concept Art', startPage: 2),
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
    requestedWidths.add(targetWidthPx);
    return Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      pageNumber,
      targetWidthPx & 0xFF,
    ]);
  }

  @override
  Future<void> closeDocument(String filePath) async {}
}

void main() {
  group('LMB-11 原生 PDF 导入、大纲落库与按需光栅化/缩放高清重绘', () {
    test(
      '导入漫画 PDF 自动写入大纲章节，支持快速缩略图(480px)、标准页(1600px)与高清缩放重绘(2800px)',
      () async {
        final srcTemp = Directory.systemTemp.createTempSync('yomu_pdf_src_');
        final sandboxTemp = Directory.systemTemp.createTempSync('yomu_pdf_sb_');
        final db = ProgressDatabase(NativeDatabase.memory());
        addTearDown(() async {
          await db.close();
          if (srcTemp.existsSync()) srcTemp.deleteSync(recursive: true);
          if (sandboxTemp.existsSync()) sandboxTemp.deleteSync(recursive: true);
        });

        final pdfBridge = _FakePdfBridge();
        final storage = LocalComicsStorage(
          rootResolver: () async => sandboxTemp,
        );
        final importer = LocalComicImporter(
          db: db,
          storage: storage,
          pdfBridge: pdfBridge,
          coverEncoder: (
            Uint8List raw, {
            required ReadingDirection direction,
          }) async => raw,
        );

        final pdfFile = File('${srcTemp.path}/Ghibli Vol.1.pdf')
          ..writeAsBytesSync(utf8.encode('%PDF-1.7\n%%EOF\n'));

        final result = await importer.importArchiveFiles(<PickedComicFile>[
          PickedComicFile.fromFile(pdfFile, name: 'Ghibli Vol.1.pdf'),
        ]);
        expect(result.importedCount, 1);
        expect(result.failures, isEmpty);

        final bookId = result.importedBookIds.single;
        final chapters = await db.bookChapters(bookId);
        expect(chapters, const <BookChapter>[
          BookChapter(title: 'Cover', startPage: 1),
          BookChapter(title: 'Concept Art', startPage: 2),
        ]);

        final series = (await db.queryLocalSeries()).items.single;
        expect(series.title, 'Ghibli');

        pdfBridge.requestedWidths.clear();
        final readerRepo = LocalReaderRepository(
          db,
          storage,
          pdfBridge: pdfBridge,
        );
        addTearDown(readerRepo.dispose);

        // 快速缩略图 480px
        await readerRepo.pageThumbnail(bookId, 2);
        // 标准页 1600px
        await readerRepo.pageImage(bookId, 2);
        // 缩放高清重绘 2800px
        final hd = await readerRepo.renderHighResPage(bookId, 2);
        expect(hd, isNotNull);
        expect(pdfBridge.requestedWidths, <int>[480, 1600, 2800]);
      },
    );

    test('加密 PDF 导入失败返回 encrypted 原因并清理沙盒', () async {
      final srcTemp = Directory.systemTemp.createTempSync('yomu_pdf_enc_');
      final sandboxTemp = Directory.systemTemp.createTempSync('yomu_pdf_esb_');
      final db = ProgressDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await db.close();
        if (srcTemp.existsSync()) srcTemp.deleteSync(recursive: true);
        if (sandboxTemp.existsSync()) sandboxTemp.deleteSync(recursive: true);
      });

      final importer = LocalComicImporter(
        db: db,
        storage: LocalComicsStorage(rootResolver: () async => sandboxTemp),
        pdfBridge: _FakePdfBridge(requiredPassword: 'secret'),
      );
      final locked = File('${srcTemp.path}/Secret.pdf')
        ..writeAsBytesSync(utf8.encode('%PDF-1.7\n%%EOF\n'));

      final result = await importer.importArchiveFiles(<PickedComicFile>[
        PickedComicFile.fromFile(locked, name: 'Secret.pdf'),
      ]);
      expect(result.importedCount, 0);
      expect(result.failures.single.reason, ImportFailureReason.encrypted);
    });
  });
}
