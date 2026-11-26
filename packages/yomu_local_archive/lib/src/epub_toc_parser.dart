import 'dart:convert';

import 'package:yomu_local_archive/src/archive_errors.dart';
import 'package:yomu_local_archive/src/byte_source.dart';
import 'package:yomu_local_archive/src/chapter_extractor.dart';
import 'package:yomu_local_archive/src/epub_opf_parser.dart';
import 'package:yomu_local_archive/src/zip_directory.dart';
import 'package:yomu_local_archive/src/zip_page_reader.dart';

/// 从 XHTML / HTML / SVG 文档中提取引用图片路径列表与正文纯文本字符数。
({List<String> imagePaths, int textChars}) extractEpubDocumentImages(
  String xhtml, {
  required String documentPath,
}) {
  final docDir = archiveDirName(documentPath);
  final images = <String>[];
  final imgPattern = RegExp(
    r'''<(?:img|image)\b([^>]*)/?>''',
    caseSensitive: false,
  );
  for (final m in imgPattern.allMatches(xhtml)) {
    final attrs = m.group(1) ?? '';
    final raw =
        epubXmlAttr(attrs, 'src') ??
        epubXmlAttr(attrs, 'xlink:href') ??
        epubXmlAttr(attrs, 'href');
    if (raw == null || raw.trim().isEmpty) continue;
    if (raw.startsWith('data:') ||
        raw.startsWith('http://') ||
        raw.startsWith('https://')) {
      continue;
    }
    images.add(resolveArchiveRelativePath(docDir, raw));
  }

  final bodyMatch = RegExp(
    r'<body\b[^>]*>([\s\S]*?)</body>',
    caseSensitive: false,
  ).firstMatch(xhtml);
  final body = bodyMatch?.group(1) ?? xhtml;
  final stripped = body
      .replaceAll(
        RegExp(
          r'<(script|style|title)\b[^>]*>[\s\S]*?</\1>',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), '')
      .trim();

  return (imagePaths: images, textChars: stripped.length);
}

/// 解析 EPUB3 `nav.xhtml` 的 TOC 条目列表 `(title, targetArchivePath)`。
List<({String title, String href})> parseEpub3NavToc(
  String xhtml, {
  required String navPath,
}) {
  final navDir = archiveDirName(navPath);
  final navMatch = RegExp(
    r'''<nav\b[^>]*epub:type\s*=\s*["'][^"']*\btoc\b[^"']*["'][^>]*>([\s\S]*?)</nav>''',
    caseSensitive: false,
  ).firstMatch(xhtml);
  final scope = navMatch?.group(1) ?? xhtml;
  final out = <({String title, String href})>[];
  final anchorPattern = RegExp(
    r'''<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</a>''',
    caseSensitive: false,
  );
  for (final m in anchorPattern.allMatches(scope)) {
    final rawHref = m.group(1)?.trim() ?? '';
    final title = cleanInlineXmlText(m.group(2) ?? '');
    if (rawHref.isEmpty || title.isEmpty) continue;
    final noFrag = rawHref.split('#').first;
    if (noFrag.isEmpty) continue;
    out.add((title: title, href: resolveArchiveRelativePath(navDir, noFrag)));
  }
  return out;
}

/// 解析 EPUB2 `toc.ncx` 的 `<navPoint>` 条目列表 `(title, targetArchivePath)`。
List<({String title, String href})> parseEpub2NcxToc(
  String xml, {
  required String ncxPath,
}) {
  final ncxDir = archiveDirName(ncxPath);
  final out = <({String title, String href})>[];
  final pointPattern = RegExp(
    r'<navPoint\b[^>]*>([\s\S]*?)<content\b([^>]*)/?>',
    caseSensitive: false,
  );
  for (final m in pointPattern.allMatches(xml)) {
    final header = m.group(1) ?? '';
    final contentAttrs = m.group(2) ?? '';
    final title = epubFirstTagText(header, 'text');
    final rawSrc = epubXmlAttr(contentAttrs, 'src');
    if (title == null || rawSrc == null || rawSrc.isEmpty) continue;
    final noFrag = rawSrc.split('#').first;
    if (noFrag.isEmpty) continue;
    out.add((title: title, href: resolveArchiveRelativePath(ncxDir, noFrag)));
  }
  return out;
}

/// 解析 EPUB 内嵌章节列表并映射回 1-based 起始页码。
Future<List<ArchiveChapter>> resolveEpubChapters({
  required RandomAccessByteSource source,
  required ParsedEpubOpf opf,
  required Map<String, ZipEntryInfo> byPath,
  required Map<String, ZipEntryInfo> byLower,
  required Map<String, int> spineHrefToStartPage,
}) async {
  var rawEntries = const <({String title, String href})>[];
  final navHref = opf.navHref;
  if (navHref != null) {
    final navEntry = byPath[navHref] ?? byLower[navHref.toLowerCase()];
    if (navEntry != null && !navEntry.isEncrypted) {
      try {
        final bytes = await ZipComicReader.extractEntry(source, navEntry);
        rawEntries = parseEpub3NavToc(
          utf8.decode(bytes, allowMalformed: true),
          navPath: navHref,
        );
      } on ArchiveException {
        rawEntries = const <({String title, String href})>[];
      }
    }
  }
  if (rawEntries.isEmpty && opf.ncxHref != null) {
    final ncxHref = opf.ncxHref!;
    final ncxEntry = byPath[ncxHref] ?? byLower[ncxHref.toLowerCase()];
    if (ncxEntry != null && !ncxEntry.isEncrypted) {
      try {
        final bytes = await ZipComicReader.extractEntry(source, ncxEntry);
        rawEntries = parseEpub2NcxToc(
          utf8.decode(bytes, allowMalformed: true),
          ncxPath: ncxHref,
        );
      } on ArchiveException {
        rawEntries = const <({String title, String href})>[];
      }
    }
  }

  final chapters = <ArchiveChapter>[];
  final seenPages = <int>{};
  for (final entry in rawEntries) {
    final page = spineHrefToStartPage[entry.href.toLowerCase()];
    if (page != null && seenPages.add(page)) {
      chapters.add(ArchiveChapter(title: entry.title, startPage: page));
    }
  }
  chapters.sort((a, b) => a.startPage.compareTo(b.startPage));
  return chapters;
}
