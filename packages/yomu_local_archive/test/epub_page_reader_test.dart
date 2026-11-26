import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

import 'support/zip_builder.dart';

Uint8List _fakePng(int width, int height) {
  final b = Uint8List(32);
  b.setRange(0, 8, const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final view = ByteData.sublistView(b);
  view.setUint32(8, 13);
  b.setRange(12, 16, utf8.encode('IHDR'));
  view.setUint32(16, width);
  view.setUint32(20, height);
  return b;
}

void main() {
  group('EpubComicReader', () {
    test(
      '解析固定版式 RTL 漫画 EPUB3：元数据、RTL 方向、页序、SVG/IMG 混合与 nav.xhtml 章节目录',
      () async {
        final img1 = _fakePng(900, 1400);
        final img2 = _fakePng(1000, 1400);
        final img3 = _fakePng(1800, 1400);

        final epubBytes = buildTestZip(<TestZipEntrySpec>[
          TestZipEntrySpec(
            name: 'mimetype',
            data: utf8.encode('application/epub+zip'),
          ),
          TestZipEntrySpec(
            name: 'META-INF/container.xml',
            data: utf8.encode('''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''),
          ),
          TestZipEntrySpec(
            name: 'OEBPS/content.opf',
            data: utf8.encode('''
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>葬送的芙莉莲 Vol.01</dc:title>
    <dc:creator>山田钟人</dc:creator>
    <dc:creator>阿部司</dc:creator>
    <dc:publisher>小学馆</dc:publisher>
    <dc:description>勇者一行讨伐魔王之后的故事。</dc:description>
    <dc:subject>奇幻</dc:subject>
    <dc:subject>治愈</dc:subject>
    <meta property="belongs-to-collection">葬送的芙莉莲</meta>
    <meta property="group-position">1</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="p1" href="Text/page01.xhtml" media-type="application/xhtml+xml"/>
    <item id="p2" href="Text/page02.xhtml" media-type="application/xhtml+xml"/>
    <item id="p3" href="Text/page03.xhtml" media-type="application/xhtml+xml"/>
    <item id="img1" href="Images/cover.png" media-type="image/png" properties="cover-image"/>
    <item id="img2" href="Images/002.png" media-type="image/png"/>
    <item id="img3" href="Images/003.png" media-type="image/png"/>
  </manifest>
  <spine page-progression-direction="rtl">
    <itemref idref="p1"/>
    <itemref idref="p2"/>
    <itemref idref="p3"/>
  </spine>
</package>'''),
          ),
          TestZipEntrySpec(
            name: 'OEBPS/nav.xhtml',
            data: utf8.encode('''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <body>
    <nav epub:type="toc">
      <ol>
        <li><a href="Text/page01.xhtml">封面</a></li>
        <li><a href="Text/page02.xhtml#top">第 1 话 冒险的终点</a></li>
        <li><a href="Text/page03.xhtml">第 2 话 僧侣的谎言</a></li>
      </ol>
    </nav>
  </body>
</html>'''),
          ),
          TestZipEntrySpec(
            name: 'OEBPS/Text/page01.xhtml',
            data: utf8.encode(
              '<html><body><img src="../Images/cover.png"/></body></html>',
            ),
          ),
          TestZipEntrySpec(
            name: 'OEBPS/Text/page02.xhtml',
            data: utf8.encode(
              '<html><body><svg><image xlink:href="../Images/002.png"/></svg></body></html>',
            ),
          ),
          TestZipEntrySpec(
            name: 'OEBPS/Text/page03.xhtml',
            data: utf8.encode(
              '<html><body><img src="../Images/003.png"/></body></html>',
            ),
            deflate: true,
          ),
          TestZipEntrySpec(name: 'OEBPS/Images/cover.png', data: img1),
          TestZipEntrySpec(
            name: 'OEBPS/Images/002.png',
            data: img2,
            deflate: true,
          ),
          TestZipEntrySpec(name: 'OEBPS/Images/003.png', data: img3),
        ]);

        final reader = await openComicArchive(MemoryByteSource(epubBytes));
        expect(reader, isA<EpubComicReader>());
        expect(reader.pages.length, 3);
        expect(reader.pages[0].width, 900);
        expect(reader.pages[1].width, 1000);
        expect(reader.pages[2].width, 1800);

        final meta = reader.embeddedMetadata!;
        expect(meta.series, '葬送的芙莉莲');
        expect(meta.title, '葬送的芙莉莲 Vol.01');
        expect(meta.number, '1');
        expect(meta.authors, const <String>['山田钟人', '阿部司']);
        expect(meta.publisher, '小学馆');
        expect(meta.tags, const <String>['奇幻', '治愈']);
        expect(meta.readingDirection, ReadingDirection.rightToLeft);
        expect(meta.frontCoverPageIndex, 0);

        expect(reader.chapters, const <ArchiveChapter>[
          ArchiveChapter(title: '封面', startPage: 1),
          ArchiveChapter(title: '第 1 话 冒险的终点', startPage: 2),
          ArchiveChapter(title: '第 2 话 僧侣的谎言', startPage: 3),
        ]);

        expect(await reader.readPage(2), img2);
        expect(await reader.readCoverImage(), isNull);
        await reader.close();
      },
    );

    test('支持 OPF 声明独立 cover-image（未出现在 spine 正文页中）且不污染页表', () async {
      final coverImg = _fakePng(600, 900);
      final page1 = _fakePng(800, 1200);
      final page2 = _fakePng(800, 1200);
      final epubBytes = buildTestZip(<TestZipEntrySpec>[
        TestZipEntrySpec(
          name: 'mimetype',
          data: utf8.encode('application/epub+zip'),
        ),
        TestZipEntrySpec(
          name: 'META-INF/container.xml',
          data: utf8.encode(
            '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>',
          ),
        ),
        TestZipEntrySpec(
          name: 'OEBPS/content.opf',
          data: utf8.encode('''
<package version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>滅鬼之刃, Vol. 1</dc:title>
    <meta property="belongs-to-collection">滅鬼之刃</meta>
    <meta property="group-position">1</meta>
    <meta name="cover" content="cover-image"/>
  </metadata>
  <manifest>
    <item id="cover-image" href="images/cover.png" media-type="image/png" properties="cover-image"/>
    <item id="p1" href="text/p0001.xhtml" media-type="application/xhtml+xml"/>
    <item id="p2" href="text/p0002.xhtml" media-type="application/xhtml+xml"/>
    <item id="i1" href="images/p0001.png" media-type="image/png"/>
    <item id="i2" href="images/p0002.png" media-type="image/png"/>
  </manifest>
  <spine page-progression-direction="rtl">
    <itemref idref="p1"/>
    <itemref idref="p2"/>
  </spine>
</package>'''),
        ),
        TestZipEntrySpec(
          name: 'OEBPS/text/p0001.xhtml',
          data: utf8.encode(
            '<html><body><img src="../images/p0001.png"/></body></html>',
          ),
        ),
        TestZipEntrySpec(
          name: 'OEBPS/text/p0002.xhtml',
          data: utf8.encode(
            '<html><body><img src="../images/p0002.png"/></body></html>',
          ),
        ),
        TestZipEntrySpec(name: 'OEBPS/images/cover.png', data: coverImg),
        TestZipEntrySpec(name: 'OEBPS/images/p0001.png', data: page1),
        TestZipEntrySpec(name: 'OEBPS/images/p0002.png', data: page2),
      ]);

      final reader = await openComicArchive(MemoryByteSource(epubBytes));
      expect(reader, isA<EpubComicReader>());
      expect(reader.pages, hasLength(2));
      expect(reader.embeddedMetadata?.frontCoverPageIndex, isNull);
      expect(await reader.readCoverImage(), coverImg);
      expect(await reader.readPage(1), page1);
      await reader.close();
    });

    test('sidecarCoverPriority 识别 cover/folder/poster 并排除非图片与隐藏项', () {
      expect(sidecarCoverPriority('cover.jpg'), 0);
      expect(sidecarCoverPriority('FOLDER.PNG'), 1);
      expect(sidecarCoverPriority('Poster.webp'), 2);
      expect(isSidecarCoverFileName('sub/cover.jpeg'), isTrue);
      expect(sidecarCoverPriority('001.jpg'), isNull);
      expect(sidecarCoverPriority('cover.txt'), isNull);
      expect(sidecarCoverPriority('.cover.jpg'), isNull);
      expect(sidecarCoverPriority('__MACOSX/cover.jpg'), isNull);
    });

    test('解析 EPUB2 toc.ncx 与 Calibre 系列元数据', () async {
      final p1 = _fakePng(800, 1200);
      final p2 = _fakePng(800, 1200);
      final epubBytes = buildTestZip(<TestZipEntrySpec>[
        TestZipEntrySpec(
          name: 'META-INF/container.xml',
          data: utf8.encode(
            '<container><rootfiles><rootfile full-path="content.opf"/></rootfiles></container>',
          ),
        ),
        TestZipEntrySpec(
          name: 'content.opf',
          data: utf8.encode('''
<package version="2.0">
  <metadata>
    <dc:title>Dungeon Meshi 02</dc:title>
    <meta name="calibre:series" content="Dungeon Meshi"/>
    <meta name="calibre:series_index" content="2"/>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="i1" href="img/1.png" media-type="image/png"/>
    <item id="i2" href="img/2.png" media-type="image/png"/>
  </manifest>
  <spine toc="ncx" page-progression-direction="ltr">
    <itemref idref="c1"/>
    <itemref idref="c2"/>
  </spine>
</package>'''),
        ),
        TestZipEntrySpec(
          name: 'toc.ncx',
          data: utf8.encode('''
<ncx><navMap>
  <navPoint id="np1"><navLabel><text>Chapter 8</text></navLabel><content src="ch1.xhtml"/></navPoint>
  <navPoint id="np2"><navLabel><text>Chapter 9</text></navLabel><content src="ch2.xhtml"/></navPoint>
</navMap></ncx>'''),
        ),
        TestZipEntrySpec(
          name: 'ch1.xhtml',
          data: utf8.encode('<html><body><img src="img/1.png"/></body></html>'),
        ),
        TestZipEntrySpec(
          name: 'ch2.xhtml',
          data: utf8.encode('<html><body><img src="img/2.png"/></body></html>'),
        ),
        TestZipEntrySpec(name: 'img/1.png', data: p1),
        TestZipEntrySpec(name: 'img/2.png', data: p2),
      ]);

      final reader = await EpubComicReader.open(MemoryByteSource(epubBytes));
      expect(reader.embeddedMetadata.series, 'Dungeon Meshi');
      expect(reader.embeddedMetadata.number, '2');
      expect(
        reader.embeddedMetadata.readingDirection,
        ReadingDirection.leftToRight,
      );
      expect(reader.chapters, const <ArchiveChapter>[
        ArchiveChapter(title: 'Chapter 8', startPage: 1),
        ArchiveChapter(title: 'Chapter 9', startPage: 2),
      ]);
      await reader.close();
    });

    test('纯文字流式小说 EPUB 抛出 ArchiveErrorKind.textOnlyEpub', () async {
      final longNovelText = '这是一段很长的纯文字轻小说正文。' * 60;
      final epubBytes = buildTestZip(<TestZipEntrySpec>[
        TestZipEntrySpec(
          name: 'mimetype',
          data: utf8.encode('application/epub+zip'),
        ),
        TestZipEntrySpec(
          name: 'META-INF/container.xml',
          data: utf8.encode(
            '<container><rootfiles><rootfile full-path="content.opf"/></rootfiles></container>',
          ),
        ),
        TestZipEntrySpec(
          name: 'content.opf',
          data: utf8.encode('''
<package version="3.0">
  <metadata><dc:title>Pure Novel</dc:title></metadata>
  <manifest>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="ch1"/></spine>
</package>'''),
        ),
        TestZipEntrySpec(
          name: 'ch1.xhtml',
          data: utf8.encode('<html><body><p>$longNovelText</p></body></html>'),
        ),
      ]);

      await expectLater(
        () => openComicArchive(MemoryByteSource(epubBytes)),
        throwsA(
          isA<ArchiveException>().having(
            (e) => e.kind,
            'kind',
            ArchiveErrorKind.textOnlyEpub,
          ),
        ),
      );
    });
  });
}
