import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

import 'support/zip_builder.dart';

void main() {
  group('ContainerMagic 与异常边界', () {
    test('0 字节文件返回 emptyFile', () async {
      final source = MemoryByteSource(Uint8List(0));
      await expectLater(
        () => ZipComicReader.open(source),
        throwsA(
          isA<ArchiveException>().having(
            (e) => e.kind,
            'kind',
            ArchiveErrorKind.emptyFile,
          ),
        ),
      );
    });

    test('识别 RAR4 / RAR5 / 7z / PDF 魔数并抛出 unsupportedContainer', () async {
      final cases = <(List<int>, ContainerMagic)>[
        (
          <int>[0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00, 0x00],
          ContainerMagic.rar4,
        ),
        (
          <int>[0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00],
          ContainerMagic.rar5,
        ),
        (
          <int>[0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0x00, 0x04],
          ContainerMagic.sevenZip,
        ),
        (
          <int>[0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37],
          ContainerMagic.pdf,
        ),
      ];

      for (final (magicBytes, expected) in cases) {
        final padded = Uint8List.fromList(<int>[
          ...magicBytes,
          ...List<int>.filled(32, 0),
        ]);
        expect(sniffContainerMagic(padded), expected);
        await expectLater(
          () => ZipComicReader.open(MemoryByteSource(padded)),
          throwsA(
            isA<ArchiveException>()
                .having(
                  (e) => e.kind,
                  'kind',
                  ArchiveErrorKind.unsupportedContainer,
                )
                .having((e) => e.detectedMagic, 'detectedMagic', expected),
          ),
        );
      }
    });

    test('合法空 ZIP 或无图片 ZIP 返回 noImages', () async {
      final zip = buildTestZip(<TestZipEntrySpec>[
        TestZipEntrySpec(name: 'readme.txt', data: utf8.encode('hello')),
        TestZipEntrySpec(
          name: '__MACOSX/._001.jpg',
          data: fakePngHeader(10, 10),
        ),
        const TestZipEntrySpec(name: '.DS_Store', data: <int>[1, 2, 3]),
      ]);
      await expectLater(
        () => ZipComicReader.open(MemoryByteSource(zip)),
        throwsA(
          isA<ArchiveException>().having(
            (e) => e.kind,
            'kind',
            ArchiveErrorKind.noImages,
          ),
        ),
      );
    });

    test('加密 ZIP 与不支持的压缩算法返回对应错误类型', () async {
      final encrypted = buildTestZip(<TestZipEntrySpec>[
        TestZipEntrySpec(
          name: '001.png',
          data: fakePngHeader(100, 200),
          encrypted: true,
        ),
      ]);
      await expectLater(
        () => ZipComicReader.open(MemoryByteSource(encrypted)),
        throwsA(
          isA<ArchiveException>().having(
            (e) => e.kind,
            'kind',
            ArchiveErrorKind.encryptedArchive,
          ),
        ),
      );

      final bzip2 = buildTestZip(<TestZipEntrySpec>[
        TestZipEntrySpec(
          name: '001.png',
          data: fakePngHeader(100, 200),
          methodOverride: 12,
        ),
      ]);
      await expectLater(
        () => ZipComicReader.open(MemoryByteSource(bzip2)),
        throwsA(
          isA<ArchiveException>().having(
            (e) => e.kind,
            'kind',
            ArchiveErrorKind.unsupportedCompression,
          ),
        ),
      );
    });
  });

  group('ZipComicReader 随机读取、ZIP64 与并发 FileByteSource', () {
    test('混合 Stored/Deflate、自然排序、垃圾过滤、ComicInfo 提取与 fromIndexedPages', () async {
      final page1 = fakePngHeader(800, 1200);
      final page2 = fakeJpegWithExifHeader(1600, 1200); // 双页宽图
      final page10 = fakePngHeader(800, 1200);
      const xmlText =
          '<ComicInfo><Series>Yomu Test</Series><Manga>Yes</Manga></ComicInfo>';

      final zipBytes = buildTestZip(
        <TestZipEntrySpec>[
          TestZipEntrySpec(
            name: 'ch1/page_10.png',
            data: page10,
            deflate: true,
          ),
          TestZipEntrySpec(name: '__MACOSX/ch1/._page_1.png', data: page1),
          TestZipEntrySpec(name: 'ch1/page_2.jpg', data: page2),
          TestZipEntrySpec(
            name: 'ComicInfo.xml',
            data: utf8.encode(xmlText),
            deflate: true,
          ),
          TestZipEntrySpec(name: 'ch1/page_1.png', data: page1),
        ],
        archiveComment: 'Created for Yomu archive test',
        useZip64: true,
      );

      final reader = await ZipComicReader.open(MemoryByteSource(zipBytes));
      expect(reader.pages, hasLength(3));
      expect(reader.pages.map((p) => p.entryName).toList(), <String>[
        'ch1/page_1.png',
        'ch1/page_2.jpg',
        'ch1/page_10.png',
      ]);
      expect(reader.pages[0].width, 800);
      expect(reader.pages[0].height, 1200);
      expect(reader.pages[1].width, 1600);
      expect(reader.pages[1].height, 1200);
      expect(
        reader.pages[1].toPageInfo().aspectRatio,
        closeTo(1600 / 1200, 0.001),
      );

      expect(reader.comicInfoBytes, isNotNull);
      expect(utf8.decode(reader.comicInfoBytes!), xmlText);

      expect(await reader.readPage(1), page1);
      expect(await reader.readPage(2), page2);
      expect(await reader.readPage(3), page10);

      // 越界页码（0 与 4）
      await expectLater(
        () => reader.readPage(0),
        throwsA(
          isA<ArchiveException>().having(
            (e) => e.kind,
            'kind',
            ArchiveErrorKind.pageOutOfRange,
          ),
        ),
      );
      await expectLater(
        () => reader.readPage(4),
        throwsA(
          isA<ArchiveException>().having(
            (e) => e.kind,
            'kind',
            ArchiveErrorKind.pageOutOfRange,
          ),
        ),
      );

      // 验证缓存索引直开路径无需重扫中央目录即可精确读页
      final indexedReader = ZipComicReader.fromIndexedPages(
        MemoryByteSource(zipBytes),
        reader.pages,
      );
      expect(await indexedReader.readPage(3), page10);
      await reader.close();
      await indexedReader.close();
    });

    test('非 UTF-8 原始字节文件名不会抛解码异常', () async {
      // 模拟 Shift-JIS / GBK 原始字节序列（非合法 UTF-8）
      final nonUtf8Name = Uint8List.fromList(<int>[
        0x82, 0xA0, 0x5F, 0x30, 0x31, 0x2E, 0x70, 0x6E, 0x67, // "..._01.png"
      ]);
      final zipBytes = buildTestZip(<TestZipEntrySpec>[
        TestZipEntrySpec(
          name: 'ignored',
          rawNameBytes: nonUtf8Name,
          data: fakePngHeader(600, 900),
        ),
      ]);
      final reader = await ZipComicReader.open(MemoryByteSource(zipBytes));
      expect(reader.pages, hasLength(1));
      expect(reader.pages.single.width, 600);
    });

    test('FileByteSource 并发读取多页互不串游标，且支持伪后缀 .cbr', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'yomu_archive_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final specs = <TestZipEntrySpec>[
        for (var i = 1; i <= 8; i++)
          TestZipEntrySpec(
            name: '$i.png',
            data: Uint8List.fromList(<int>[
              ...fakePngHeader(100 + i, 200 + i),
              i,
              i,
              i,
            ]),
            deflate: i.isEven,
          ),
      ];
      // 故意使用伪后缀 .cbr，但内容为标准 ZIP
      final file = File('${tempDir.path}/misnamed_comic.cbr');
      await file.writeAsBytes(buildTestZip(specs));

      final source = await FileByteSource.open(file);
      final reader = await ZipComicReader.open(source);
      expect(reader.pages, hasLength(8));

      final results = await Future.wait<Uint8List>(<Future<Uint8List>>[
        for (var p = 8; p >= 1; p--) reader.readPage(p),
      ]);
      for (var idx = 0; idx < 8; idx++) {
        final pageNum = 8 - idx;
        expect(results[idx].last, pageNum);
      }
      await reader.close();
    });
  });

  group('FolderComicReader 文件夹漫画读取', () {
    test('递归扫描图片文件夹、自然排序、提取 ComicInfo 并拦截路径穿越', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'yomu_folder_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      await File('${tempDir.path}/10.png')
          .writeAsBytes(fakePngHeader(700, 1000));
      await File('${tempDir.path}/2.png')
          .writeAsBytes(fakePngHeader(720, 1024));
      await File('${tempDir.path}/.DS_Store').writeAsBytes(const <int>[0, 1]);
      await File('${tempDir.path}/ComicInfo.xml')
          .writeAsString('<ComicInfo><Title>Folder Vol 1</Title></ComicInfo>');

      final reader = await FolderComicReader.open(tempDir);
      expect(reader.pages.map((p) => p.entryName).toList(), <String>[
        '2.png',
        '10.png',
      ]);
      expect(reader.pages.first.width, 720);
      expect(reader.comicInfoBytes, isNotNull);
      expect((await reader.readPage(1)).length, greaterThan(20));

      final malicious = FolderComicReader.fromIndexedPages(
        tempDir,
        const <ArchivePageEntry>[
          ArchivePageEntry(
            number: 1,
            entryName: '../secret.png',
            uncompressedSize: 10,
          ),
        ],
      );
      await expectLater(
        () => malicious.readPage(1),
        throwsA(
          isA<ArchiveException>().having(
            (e) => e.kind,
            'kind',
            ArchiveErrorKind.corruptedArchive,
          ),
        ),
      );
    });
  });
}
