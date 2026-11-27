import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

import 'support/zip_builder.dart';

void main() {
  group('naturalCompare 自然排序与图片过滤', () {
    test('数字按数值比较且超长 30 位数字不溢出', () {
      final list = <String>[
        '100.jpg',
        '2.jpg',
        '10.jpg',
        '1.jpg',
        '02.jpg',
        'page_999999999999999999999999999999.jpg',
        'page_1000000000000000000000000000000.jpg',
      ]..sort(naturalCompare);

      expect(list, <String>[
        '1.jpg',
        '2.jpg',
        '02.jpg',
        '10.jpg',
        '100.jpg',
        'page_999999999999999999999999999999.jpg',
        'page_1000000000000000000000000000000.jpg',
      ]);
    });

    test('多级子目录先按目录自然序再按页文件名排序', () {
      final list = <String>[r'Ch10\001.webp', 'Ch2/010.webp', 'Ch2/002.webp']
        ..sort(naturalCompare);

      expect(list, <String>['Ch2/002.webp', 'Ch2/010.webp', r'Ch10\001.webp']);
    });

    test('isSupportedComicImagePath 过滤隐藏项与非图片扩展名', () {
      expect(isSupportedComicImagePath('001.webp'), isTrue);
      expect(isSupportedComicImagePath('sub/p01.AVIF'), isTrue);
      expect(isSupportedComicImagePath('__MACOSX/001.jpg'), isFalse);
      expect(isSupportedComicImagePath('sub/._001.jpg'), isFalse);
      expect(isSupportedComicImagePath('.nomedia'), isFalse);
      expect(isSupportedComicImagePath('Thumbs.db'), isFalse);
      expect(isSupportedComicImagePath('ComicInfo.xml'), isFalse);
    });
  });

  group('sniffImageDimensions 多格式头部嗅探', () {
    test('精确解析 PNG、JPEG (SOF0/SOF2 + EXIF)、WebP (VP8/VP8L/VP8X)、GIF、BMP', () {
      expect(sniffImageDimensions(fakePngHeader(1080, 1920)), (
        width: 1080,
        height: 1920,
      ));
      expect(
        sniffImageDimensions(
          fakeJpegWithExifHeader(1400, 2000, sofMarker: 0xC2),
        ),
        (width: 1400, height: 2000),
      );

      // GIF89a: 640x480
      final gif = Uint8List.fromList(const <int>[
        0x47,
        0x49,
        0x46,
        0x38,
        0x39,
        0x61,
        0x80,
        0x02,
        0xE0,
        0x01,
      ]);
      expect(sniffImageDimensions(gif), (width: 640, height: 480));

      // BMP BITMAPINFOHEADER (40 bytes): 320 x -240 (top-down)
      final bmp = ByteData(30)
        ..setUint8(0, 0x42)
        ..setUint8(1, 0x4D)
        ..setUint32(14, 40, Endian.little)
        ..setInt32(18, 320, Endian.little)
        ..setInt32(22, -240, Endian.little);
      expect(sniffImageDimensions(bmp.buffer.asUint8List()), (
        width: 320,
        height: 240,
      ));

      // WebP VP8 (lossy): 1200x1800
      final vp8 = ByteData(30)
        ..setUint16(26, 1200, Endian.little)
        ..setUint16(28, 1800, Endian.little);
      final vp8Bytes = vp8.buffer.asUint8List()
        ..setRange(0, 4, 'RIFF'.codeUnits)
        ..setRange(8, 16, 'WEBPVP8 '.codeUnits)
        ..setRange(23, 26, const <int>[0x9D, 0x01, 0x2A]);
      expect(sniffImageDimensions(vp8Bytes), (width: 1200, height: 1800));

      // WebP VP8L (lossless): 900x1350
      const packed = (900 - 1) | ((1350 - 1) << 14);
      final vp8l = ByteData(30)
        ..setUint8(20, 0x2F)
        ..setUint32(21, packed, Endian.little);
      final vp8lBytes = vp8l.buffer.asUint8List()
        ..setRange(0, 4, 'RIFF'.codeUnits)
        ..setRange(8, 16, 'WEBPVP8L'.codeUnits);
      expect(sniffImageDimensions(vp8lBytes), (width: 900, height: 1350));

      // WebP VP8X (extended): 2048x3072
      final vp8xBytes = Uint8List(30)
        ..setRange(0, 4, 'RIFF'.codeUnits)
        ..setRange(8, 16, 'WEBPVP8X'.codeUnits)
        ..[24] = (2048 - 1) & 0xFF
        ..[25] = ((2048 - 1) >> 8) & 0xFF
        ..[27] = (3072 - 1) & 0xFF
        ..[28] = ((3072 - 1) >> 8) & 0xFF;
      expect(sniffImageDimensions(vp8xBytes), (width: 2048, height: 3072));

      // 截断或未知字节返回 null
      expect(
        sniffImageDimensions(Uint8List.fromList(const <int>[1, 2, 3])),
        isNull,
      );
    });
  });

  group('ComicInfo.xml 解析与文件名启发式推导', () {
    test('处理 UTF-8 BOM、XML 实体、CDATA、RTL 阅读方向与 FrontCover 页索引', () {
      const xml = '''
<ComicInfo>
  <Series>葬送的芙莉莲 &amp; 番外</Series>
  <Title>Vol. 1 &quot;启程&quot;</Title>
  <Number>1.5</Number>
  <Volume>1</Volume>
  <Count>13</Count>
  <Summary><![CDATA[勇者一行击败魔王之后的故事 <第一部>]]></Summary>
  <Writer>山田钟人</Writer>
  <Penciller>阿部司, 山田钟人</Penciller>
  <Publisher>小学馆</Publisher>
  <Year>2020</Year>
  <Month>8</Month>
  <Day>18</Day>
  <Genre>奇幻, 冒险</Genre>
  <Tags>治愈; 奇幻</Tags>
  <Manga>YesAndRightToLeft</Manga>
  <Pages>
    <Page Image="0" Type="InnerCover" />
    <Page Image="2" Type="FrontCover" />
  </Pages>
</ComicInfo>
''';
      final withBom = Uint8List.fromList(<int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(xml),
      ]);
      final meta = parseComicInfoXml(withBom);
      expect(meta.series, '葬送的芙莉莲 & 番外');
      expect(meta.title, 'Vol. 1 "启程"');
      expect(meta.number, '1.5');
      expect(meta.volume, 1);
      expect(meta.count, 13);
      expect(meta.summary, '勇者一行击败魔王之后的故事 <第一部>');
      expect(meta.authors, <String>['山田钟人', '阿部司']);
      expect(meta.publisher, '小学馆');
      expect(meta.releaseDate, DateTime.utc(2020, 8, 18));
      expect(meta.tags, <String>['奇幻', '冒险', '治愈']);
      expect(meta.readingDirection, ReadingDirection.rightToLeft);
      expect(meta.frontCoverPageIndex, 2);
    });

    test('inferTitlesFromFileName 从常见中英日文件名提取系列名与卷号', () {
      final a = inferTitlesFromFileName('[Kmoe][九井谅子] 迷宫饭 第03卷.cbz');
      expect(a.seriesTitle, '迷宫饭');
      expect(a.number, '3');
      expect(a.numberSort, 3);

      final b = inferTitlesFromFileName('Frieren Vol.12.5 (Digital).cbz');
      expect(b.seriesTitle, 'Frieren');
      expect(b.number, '12.5');
      expect(b.numberSort, 12.5);

      final c = inferTitlesFromFileName('04.cbz', parentFolderName: '孤独摇滚');
      expect(c.seriesTitle, '孤独摇滚');

      // 末尾裸四位年份（1900–2099）不应被误判为卷号，带前缀的明确卷号与非年份编号仍保留。
      final year1 = inferTitlesFromFileName('Bobby_Make_Believe_1915.cbt');
      expect(year1.seriesTitle, 'Bobby_Make_Believe_1915');
      expect(year1.number, isEmpty);
      expect(year1.numberSort, 0);

      final year2 = inferTitlesFromFileName('Will_Eisner_M16A1_Comic_1969.zip');
      expect(year2.number, isEmpty);

      final issue = inferTitlesFromFileName('Roy_Rogers_and_Trigger_096.cbr');
      expect(issue.seriesTitle, 'Roy_Rogers_and_Trigger');
      expect(issue.number, '96');
      expect(issue.numberSort, 96);

      final longRun = inferTitlesFromFileName('Detective_Conan_1050.cbz');
      expect(longRun.seriesTitle, 'Detective_Conan');
      expect(longRun.number, '1050');
      expect(longRun.numberSort, 1050);

      final explicitVolYear = inferTitlesFromFileName('Special Vol. 2001.cbz');
      expect(explicitVolYear.seriesTitle, 'Special');
      expect(explicitVolYear.number, '2001');
    });
  });
}
