import 'dart:convert';
import 'dart:typed_data';

import 'package:yomu_domain/yomu_domain.dart';

/// 解析自 `ComicInfo.xml`（Anansi Project v2.0/v2.1）的漫画元数据。
final class ComicInfoMetadata {
  const ComicInfoMetadata({
    this.series,
    this.title,
    this.number,
    this.volume,
    this.count,
    this.summary,
    this.authors = const <String>[],
    this.publisher,
    this.releaseDate,
    this.tags = const <String>[],
    this.readingDirection = ReadingDirection.unknown,
    this.frontCoverPageIndex,
    this.pageBookmarks = const <({String title, int pageIndex})>[],
  });

  final String? series;
  final String? title;
  final String? number;
  final int? volume;
  final int? count;
  final String? summary;
  final List<String> authors;
  final String? publisher;
  final DateTime? releaseDate;
  final List<String> tags;
  final ReadingDirection readingDirection;

  /// `ComicInfo.xml` `<Pages>` 中标记为 `Type="FrontCover"` 的 0 基图片序号。
  final int? frontCoverPageIndex;

  /// `ComicInfo.xml` `<Pages>` 中带 `Bookmark="..."` 属性的 0 基页章节书签。
  final List<({String title, int pageIndex})> pageBookmarks;
}

/// 零外部依赖解析 `ComicInfo.xml` 字节。畸形或空白字段自动优雅忽略，永不抛异常。
ComicInfoMetadata parseComicInfoXml(Uint8List rawBytes) {
  if (rawBytes.isEmpty) return const ComicInfoMetadata();
  final start =
      (rawBytes.length >= 3 &&
          rawBytes[0] == 0xEF &&
          rawBytes[1] == 0xBB &&
          rawBytes[2] == 0xBF)
      ? 3
      : 0;
  final xml = utf8.decode(
    Uint8List.sublistView(rawBytes, start),
    allowMalformed: true,
  );

  String? tagValue(String tagName) {
    final pattern = RegExp(
      '<$tagName(?:\\s[^>]*)?>([\\s\\S]*?)</$tagName>',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(xml);
    if (match == null) return null;
    final text = _unescapeXml(match.group(1)!).trim();
    return text.isEmpty ? null : text;
  }

  final authors = <String>[];
  final seenAuthors = <String>{};
  for (final role in const <String>[
    'Writer',
    'Penciller',
    'Inker',
    'Colorist',
    'CoverArtist',
  ]) {
    final raw = tagValue(role);
    if (raw == null) continue;
    for (final part in raw.split(',')) {
      final trimmed = part.trim();
      if (trimmed.isNotEmpty && seenAuthors.add(trimmed)) {
        authors.add(trimmed);
      }
    }
  }

  final tags = <String>[];
  final seenTags = <String>{};
  for (final field in const <String>['Genre', 'Tags']) {
    final raw = tagValue(field);
    if (raw == null) continue;
    for (final part in raw.split(RegExp('[,;]'))) {
      final trimmed = part.trim();
      if (trimmed.isNotEmpty && seenTags.add(trimmed)) {
        tags.add(trimmed);
      }
    }
  }

  final year = int.tryParse(tagValue('Year') ?? '');
  final month = int.tryParse(tagValue('Month') ?? '');
  final day = int.tryParse(tagValue('Day') ?? '');
  DateTime? releaseDate;
  if (year != null && year >= 1900 && year <= 2200) {
    releaseDate = DateTime.utc(
      year,
      (month != null && month >= 1 && month <= 12) ? month : 1,
      (day != null && day >= 1 && day <= 31) ? day : 1,
    );
  }

  final mangaRaw = (tagValue('Manga') ?? '').toLowerCase();
  final direction = switch (mangaRaw) {
    'yesandrighttoleft' || 'yes' || 'rtl' => ReadingDirection.rightToLeft,
    'no' || 'ltr' => ReadingDirection.leftToRight,
    _ => ReadingDirection.unknown,
  };

  final pageDetails = _parseComicInfoPages(xml);
  return ComicInfoMetadata(
    series: tagValue('Series'),
    title: tagValue('Title'),
    number: tagValue('Number'),
    volume: int.tryParse(tagValue('Volume') ?? ''),
    count: int.tryParse(tagValue('Count') ?? ''),
    summary: tagValue('Summary'),
    authors: List<String>.unmodifiable(authors),
    publisher: tagValue('Publisher'),
    releaseDate: releaseDate,
    tags: List<String>.unmodifiable(tags),
    readingDirection: direction,
    frontCoverPageIndex: pageDetails.frontCoverIndex,
    pageBookmarks: pageDetails.bookmarks,
  );
}

({int? frontCoverIndex, List<({String title, int pageIndex})> bookmarks})
_parseComicInfoPages(String xml) {
  final pageTagPattern = RegExp(r'<Page\b([^>]*)/?>', caseSensitive: false);
  final typePattern = RegExp(
    r'''\bType\s*=\s*["']([^"']*)["']''',
    caseSensitive: false,
  );
  final imagePattern = RegExp(
    r'''\bImage\s*=\s*["'](\d+)["']''',
    caseSensitive: false,
  );
  final bookmarkPattern = RegExp(
    r'''\bBookmark\s*=\s*(?:"([^"]*)"|'([^']*)')''',
    caseSensitive: false,
  );

  int? frontCover;
  final bookmarks = <({String title, int pageIndex})>[];
  for (final match in pageTagPattern.allMatches(xml)) {
    final attrs = match.group(1) ?? '';
    final indexStr = imagePattern.firstMatch(attrs)?.group(1);
    final idx = indexStr == null ? null : int.tryParse(indexStr);
    if (idx == null || idx < 0) continue;

    final type = typePattern.firstMatch(attrs)?.group(1)?.toLowerCase();
    if (type == 'frontcover' && frontCover == null) {
      frontCover = idx;
    }

    final bmMatch = bookmarkPattern.firstMatch(attrs);
    final rawBm = bmMatch?.group(1) ?? bmMatch?.group(2);
    if (rawBm != null) {
      final clean = _unescapeXml(rawBm).trim();
      if (clean.isNotEmpty) {
        bookmarks.add((title: clean, pageIndex: idx));
      }
    }
  }
  return (
    frontCoverIndex: frontCover,
    bookmarks: List<({String title, int pageIndex})>.unmodifiable(bookmarks),
  );
}

String _unescapeXml(String input) {
  final cdataStripped = input.replaceAllMapped(
    RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>'),
    (Match m) => m.group(1) ?? '',
  );
  return cdataStripped.replaceAllMapped(
    RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);'),
    (Match m) {
      final token = m.group(1)!;
      switch (token) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
        default:
          final code = token.startsWith('#x') || token.startsWith('#X')
              ? int.tryParse(token.substring(2), radix: 16)
              : int.tryParse(token.substring(1));
          if (code != null && code > 0 && code <= 0x10FFFF) {
            return String.fromCharCode(code);
          }
          return m.group(0)!;
      }
    },
  );
}

/// 当压缩包不含 `ComicInfo.xml` 时，从文件名与可选父目录推导系列名、书名与卷号。
({String seriesTitle, String bookTitle, String number, double numberSort})
inferTitlesFromFileName(String rawFileName, {String? parentFolderName}) {
  var stem = rawFileName.replaceAll(r'\', '/').split('/').last.trim();
  final dot = stem.lastIndexOf('.');
  if (dot > 0) stem = stem.substring(0, dot).trim();

  // 剥离常见的压制组/作者前置方括号（如 `[Kmoe][Author] 迷宫饭 Vol.01`）。
  final strippedBrackets = stem
      .replaceFirst(RegExp(r'^(?:\[[^\]]+\]\s*)+'), '')
      .replaceFirst(RegExp(r'^(?:\([^)]+\)\s*)+'), '')
      .trim();
  final cleanStem = strippedBrackets.isEmpty ? stem : strippedBrackets;

  final volPatterns = <RegExp>[
    RegExp(
      r'^(.*?)\s*(?:vol\.?|volume|v|ch\.?|chapter|#)\s*0*(\d+(?:\.\d+)?)\b.*$',
      caseSensitive: false,
    ),
    RegExp(r'^(.*?)\s*第\s*0*(\d+(?:\.\d+)?)\s*[卷話话集册回].*$'),
    RegExp(r'^(.+?)[_\s-]+0*(\d+(?:\.\d+)?)$'),
  ];

  String? extractedSeries;
  String number = '';
  for (var i = 0; i < volPatterns.length; i++) {
    final m = volPatterns[i].firstMatch(cleanStem);
    if (m != null) {
      final candidateSeries = (m.group(1) ?? '')
          .replaceAll(RegExp(r'[-_.\s]+$'), '')
          .trim();
      final candidateNum = (m.group(2) ?? '').trim();
      // 末尾裸数字（无 Vol./Ch./#/第...卷 前缀）若落在 1900–2099 的四位年份区间，
      // 通常是出版年份（如 `Bobby_Make_Believe_1915`），不应误判为第 1915 卷。
      if (i == volPatterns.length - 1 &&
          _looksLikeFourDigitYear(candidateNum)) {
        continue;
      }
      if (candidateNum.isNotEmpty) {
        number = candidateNum;
        if (candidateSeries.isNotEmpty) {
          extractedSeries = candidateSeries;
        }
        break;
      }
    }
  }

  final cleanParent = parentFolderName?.trim() ?? '';
  final seriesTitle = cleanParent.isNotEmpty
      ? cleanParent
      : (extractedSeries ?? (cleanStem.isEmpty ? 'Untitled' : cleanStem));
  final bookTitle = cleanStem.isEmpty ? seriesTitle : cleanStem;
  final numberSort = double.tryParse(number) ?? 0;

  return (
    seriesTitle: seriesTitle,
    bookTitle: bookTitle,
    number: number,
    numberSort: numberSort,
  );
}

bool _looksLikeFourDigitYear(String candidate) {
  if (candidate.length != 4 || candidate.contains('.')) return false;
  final year = int.tryParse(candidate);
  return year != null && year >= 1900 && year <= 2099;
}
