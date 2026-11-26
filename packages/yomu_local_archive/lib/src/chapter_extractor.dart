import 'dart:typed_data';

import 'package:yomu_local_archive/src/comic_info_parser.dart';
import 'package:yomu_local_archive/src/zip_page_reader.dart';

/// 归档/漫画书内部的单条章节锚点（1 基起始页码）。
final class ArchiveChapter {
  const ArchiveChapter({required this.title, required this.startPage});

  final String title;
  final int startPage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ArchiveChapter &&
          other.title == title &&
          other.startPage == startPage);

  @override
  int get hashCode => Object.hash(title, startPage);

  @override
  String toString() => 'ArchiveChapter($title -> p.$startPage)';
}

/// 综合提取单本归档的内部章节目录（LMB-05）。
///
/// 优先级：
/// 1. `ComicInfo.xml` 中 `<Page Image="N" Bookmark="..."/>` 显式章节书签；
/// 2. 归档/文件夹内跨越 2 个及以上子目录时按子目录名自动聚合章节。
List<ArchiveChapter> resolveArchiveChapters({
  required List<ArchivePageEntry> pages,
  Uint8List? comicInfoBytes,
}) {
  if (pages.isEmpty) return const <ArchiveChapter>[];

  if (comicInfoBytes != null && comicInfoBytes.isNotEmpty) {
    final meta = parseComicInfoXml(comicInfoBytes);
    if (meta.pageBookmarks.isNotEmpty) {
      final fromXml = <ArchiveChapter>[];
      final seenPages = <int>{};
      for (final bm in meta.pageBookmarks) {
        final page = bm.pageIndex + 1;
        if (page < 1 || page > pages.length) continue;
        if (seenPages.add(page)) {
          fromXml.add(ArchiveChapter(title: bm.title, startPage: page));
        }
      }
      if (fromXml.isNotEmpty) {
        fromXml.sort((a, b) => a.startPage.compareTo(b.startPage));
        return List<ArchiveChapter>.unmodifiable(fromXml);
      }
    }
  }

  return deriveSubfolderChapters(pages);
}

/// 当单本压缩包或图片文件夹内跨越多个子目录时，按子目录名自动生成章节锚点。
///
/// 若所有图片共享同一外层包裹目录（如 `Volume1/Ch01/01.jpg`, `Volume1/Ch02/01.jpg`），
/// 会自动剥离公共外层目录再提取 `Ch01` / `Ch02`。
List<ArchiveChapter> deriveSubfolderChapters(List<ArchivePageEntry> pages) {
  if (pages.length < 2) return const <ArchiveChapter>[];

  final dirSegmentsList = <List<String>>[];
  for (final p in pages) {
    final norm = p.entryName.replaceAll(r'\', '/');
    final parts = norm
        .split('/')
        .where((s) => s.isNotEmpty && s != '.')
        .toList(growable: false);
    if (parts.length <= 1) {
      dirSegmentsList.add(const <String>[]);
    } else {
      dirSegmentsList.add(parts.sublist(0, parts.length - 1));
    }
  }

  // 剥离所有页面共同拥有的外层包裹目录（避免整本只有一层外壳时误识别）。
  var commonPrefixLen = 0;
  if (dirSegmentsList.every((d) => d.isNotEmpty)) {
    final minLen = dirSegmentsList
        .map((d) => d.length)
        .reduce((a, b) => a < b ? a : b);
    while (commonPrefixLen < minLen) {
      final candidate = dirSegmentsList.first[commonPrefixLen];
      final allMatch = dirSegmentsList.every(
        (d) => d[commonPrefixLen] == candidate,
      );
      if (!allMatch) break;
      commonPrefixLen++;
    }
  }

  final chapters = <ArchiveChapter>[];
  String? lastGroup;
  final distinctGroups = <String>{};

  for (var i = 0; i < pages.length; i++) {
    final dirs = dirSegmentsList[i];
    final effective = dirs.length > commonPrefixLen
        ? dirs.sublist(commonPrefixLen)
        : const <String>[];
    if (effective.isEmpty) continue;
    final groupKey = effective.join('/');
    distinctGroups.add(groupKey);
    if (groupKey != lastGroup) {
      lastGroup = groupKey;
      final title = effective.last.trim();
      if (title.isNotEmpty) {
        chapters.add(ArchiveChapter(title: title, startPage: pages[i].number));
      }
    }
  }

  // 仅当存在至少 2 个不同子目录时才视为多章节，避免单目录产生无意义 1 条目目录。
  if (distinctGroups.length < 2 || chapters.length < 2) {
    return const <ArchiveChapter>[];
  }
  return List<ArchiveChapter>.unmodifiable(chapters);
}
