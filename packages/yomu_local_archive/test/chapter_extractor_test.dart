import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

ArchivePageEntry _page(int number, String name) =>
    ArchivePageEntry(number: number, entryName: name, uncompressedSize: 100);

void main() {
  group('resolveArchiveChapters & deriveSubfolderChapters', () {
    test('优先从 ComicInfo.xml <Page Bookmark="..."> 提取 1 基章节并过滤越界页', () {
      final pages = <ArchivePageEntry>[
        _page(1, '001.jpg'),
        _page(2, '002.jpg'),
        _page(3, '003.jpg'),
        _page(4, '004.jpg'),
      ];
      final xml = Uint8List.fromList(
        utf8.encode('''
<ComicInfo>
  <Pages>
    <Page Image="0" Type="FrontCover" Bookmark="Cover &amp; Intro" />
    <Page Image="2" Bookmark="第 2 话" />
    <Page Image="99" Bookmark="OutOfRange" />
  </Pages>
</ComicInfo>'''),
      );

      final chapters = resolveArchiveChapters(
        pages: pages,
        comicInfoBytes: xml,
      );
      expect(chapters, const <ArchiveChapter>[
        ArchiveChapter(title: 'Cover & Intro', startPage: 1),
        ArchiveChapter(title: '第 2 话', startPage: 3),
      ]);
    });

    test('无 ComicInfo 书签时，多级子目录自动剥离公共外壳并按子目录切章节', () {
      final pages = <ArchivePageEntry>[
        _page(1, 'MangaVol1/Ch01/001.jpg'),
        _page(2, 'MangaVol1/Ch01/002.jpg'),
        _page(3, 'MangaVol1/Ch02/001.jpg'),
        _page(4, 'MangaVol1/Ch02/002.jpg'),
        _page(5, 'MangaVol1/Extra/001.jpg'),
      ];

      final chapters = resolveArchiveChapters(pages: pages);
      expect(chapters, const <ArchiveChapter>[
        ArchiveChapter(title: 'Ch01', startPage: 1),
        ArchiveChapter(title: 'Ch02', startPage: 3),
        ArchiveChapter(title: 'Extra', startPage: 5),
      ]);
    });

    test('平铺单目录不产生冗余 1 条目目录', () {
      final flat = <ArchivePageEntry>[
        _page(1, 'Vol1/001.jpg'),
        _page(2, 'Vol1/002.jpg'),
        _page(3, 'Vol1/003.jpg'),
      ];
      expect(deriveSubfolderChapters(flat), isEmpty);
    });
  });
}
