import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/src/comic_info_parser.dart';

/// OPF manifest 单条资源记录。
final class EpubManifestItem {
  const EpubManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    this.properties = '',
  });

  final String id;
  final String href;
  final String mediaType;
  final String properties;
}

/// 解析后的 OPF 清单、书脊、元数据与目录入口。
final class ParsedEpubOpf {
  const ParsedEpubOpf({
    required this.metadata,
    required this.manifest,
    required this.spineIds,
    required this.direction,
    this.coverImageHref,
    this.navHref,
    this.ncxHref,
  });

  final ComicInfoMetadata metadata;
  final Map<String, EpubManifestItem> manifest;
  final List<String> spineIds;
  final ReadingDirection direction;
  final String? coverImageHref;
  final String? navHref;
  final String? ncxHref;
}

/// 从 `META-INF/container.xml` 提取 `.opf` 的归档相对路径。
String? parseContainerOpfPath(String xml) {
  final rootfile = RegExp(
    r'''<rootfile\b[^>]*\bfull-path\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  ).firstMatch(xml);
  final raw = rootfile?.group(1)?.trim();
  if (raw == null || raw.isEmpty) return null;
  return normalizeArchivePath(raw);
}

/// 解析 EPUB `content.opf`（兼容 EPUB2 与 EPUB3 / Calibre 扩展）。
ParsedEpubOpf parseEpubOpf(String xml, {required String opfPath}) {
  final opfDir = archiveDirName(opfPath);
  final manifest = <String, EpubManifestItem>{};
  String? navHref;
  String? ncxHref;
  String? coverHrefFromProp;

  final itemPattern = RegExp(r'<item\b([^>]*)/?>', caseSensitive: false);
  for (final m in itemPattern.allMatches(xml)) {
    final attrs = m.group(1) ?? '';
    final id = epubXmlAttr(attrs, 'id');
    final rawHref = epubXmlAttr(attrs, 'href');
    if (id == null || rawHref == null) continue;
    final mediaType = (epubXmlAttr(attrs, 'media-type') ?? '').toLowerCase();
    final props = (epubXmlAttr(attrs, 'properties') ?? '').toLowerCase();
    final resolved = resolveArchiveRelativePath(opfDir, rawHref);
    manifest[id] = EpubManifestItem(
      id: id,
      href: resolved,
      mediaType: mediaType,
      properties: props,
    );
    final propTokens = props.split(RegExp(r'\s+'));
    if (propTokens.contains('nav')) navHref ??= resolved;
    if (propTokens.contains('cover-image')) coverHrefFromProp ??= resolved;
    if (mediaType == 'application/x-dtbncx+xml') ncxHref ??= resolved;
  }

  final spineTag = RegExp(
    r'<spine\b([^>]*)>([\s\S]*?)</spine>',
    caseSensitive: false,
  ).firstMatch(xml);
  final spineAttrs = spineTag?.group(1) ?? '';
  final spineBody = spineTag?.group(2) ?? '';
  final ppd = (epubXmlAttr(spineAttrs, 'page-progression-direction') ?? '')
      .toLowerCase();
  final direction = switch (ppd) {
    'rtl' => ReadingDirection.rightToLeft,
    'ltr' => ReadingDirection.leftToRight,
    _ => ReadingDirection.unknown,
  };
  final spineTocId = epubXmlAttr(spineAttrs, 'toc');
  if (spineTocId != null && manifest.containsKey(spineTocId)) {
    ncxHref = manifest[spineTocId]!.href;
  }

  final spineIds = <String>[];
  final itemrefPattern = RegExp(r'<itemref\b([^>]*)/?>', caseSensitive: false);
  for (final m in itemrefPattern.allMatches(spineBody)) {
    final attrs = m.group(1) ?? '';
    final idref = epubXmlAttr(attrs, 'idref');
    if (idref != null && idref.isNotEmpty) spineIds.add(idref);
  }

  final metaCoverId = _metaNameContent(xml, 'cover');
  final coverHref =
      coverHrefFromProp ??
      (metaCoverId != null ? manifest[metaCoverId]?.href : null);

  final title = epubFirstTagText(xml, 'dc:title');
  final creators = _allTagTexts(xml, 'dc:creator');
  final publisher = epubFirstTagText(xml, 'dc:publisher');
  final summary = epubFirstTagText(xml, 'dc:description');
  final tags = _allTagTexts(xml, 'dc:subject');
  final series =
      _metaPropertyText(xml, 'belongs-to-collection') ??
      _metaNameContent(xml, 'calibre:series');
  final number =
      _metaPropertyText(xml, 'group-position') ??
      _metaNameContent(xml, 'calibre:series_index');

  return ParsedEpubOpf(
    metadata: ComicInfoMetadata(
      series: series,
      title: title,
      number: number,
      summary: summary,
      authors: creators,
      publisher: publisher,
      tags: tags,
      readingDirection: direction,
    ),
    manifest: manifest,
    spineIds: spineIds,
    direction: direction,
    coverImageHref: coverHref,
    navHref: navHref,
    ncxHref: ncxHref,
  );
}

String archiveDirName(String path) {
  final norm = normalizeArchivePath(path);
  final idx = norm.lastIndexOf('/');
  return idx < 0 ? '' : norm.substring(0, idx);
}

String normalizeArchivePath(String raw) {
  final decoded = _safeDecodeUriComponent(raw.replaceAll(r'\', '/')).trim();
  final parts = <String>[];
  for (final seg in decoded.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(seg);
    }
  }
  return parts.join('/');
}

String resolveArchiveRelativePath(String baseDir, String rawHref) {
  final cleanHref = rawHref.split('#').first.split('?').first.trim();
  if (cleanHref.startsWith('/')) {
    return normalizeArchivePath(cleanHref.substring(1));
  }
  if (baseDir.isEmpty) return normalizeArchivePath(cleanHref);
  return normalizeArchivePath('$baseDir/$cleanHref');
}

String? epubXmlAttr(String attrs, String name) {
  final match = RegExp(
    '(?:^|\\s)${RegExp.escape(name)}\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')',
    caseSensitive: false,
  ).firstMatch(attrs);
  final raw = match?.group(1) ?? match?.group(2);
  if (raw == null) return null;
  final trimmed = _unescapeBasicXml(raw).trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? epubFirstTagText(String xml, String tagName) {
  final m = RegExp(
    '<${RegExp.escape(tagName)}(?:\\s[^>]*)?>([\\s\\S]*?)</${RegExp.escape(tagName)}>',
    caseSensitive: false,
  ).firstMatch(xml);
  if (m == null) return null;
  final text = cleanInlineXmlText(m.group(1)!);
  return text.isEmpty ? null : text;
}

List<String> _allTagTexts(String xml, String tagName) {
  final pattern = RegExp(
    '<${RegExp.escape(tagName)}(?:\\s[^>]*)?>([\\s\\S]*?)</${RegExp.escape(tagName)}>',
    caseSensitive: false,
  );
  final out = <String>[];
  final seen = <String>{};
  for (final m in pattern.allMatches(xml)) {
    final text = cleanInlineXmlText(m.group(1)!);
    if (text.isNotEmpty && seen.add(text)) out.add(text);
  }
  return List<String>.unmodifiable(out);
}

String? _metaPropertyText(String xml, String property) {
  final pattern = RegExp(
    '''<meta\\b[^>]*\\bproperty\\s*=\\s*["']${RegExp.escape(property)}["'][^>]*>([\\s\\S]*?)</meta>''',
    caseSensitive: false,
  );
  final m = pattern.firstMatch(xml);
  if (m == null) return null;
  final text = cleanInlineXmlText(m.group(1)!);
  return text.isEmpty ? null : text;
}

String? _metaNameContent(String xml, String name) {
  final pattern = RegExp(r'<meta\b([^>]*)/?>', caseSensitive: false);
  for (final m in pattern.allMatches(xml)) {
    final attrs = m.group(1) ?? '';
    if ((epubXmlAttr(attrs, 'name') ?? '').toLowerCase() ==
        name.toLowerCase()) {
      final content = epubXmlAttr(attrs, 'content');
      if (content != null) return content;
    }
  }
  return null;
}

String cleanInlineXmlText(String raw) => _unescapeBasicXml(
  raw
      .replaceAll(RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>'), r'$1')
      .replaceAll(RegExp(r'<[^>]+>'), ' '),
).replaceAll(RegExp(r'\s+'), ' ').trim();

String _unescapeBasicXml(String input) => input.replaceAllMapped(
  RegExp(r'&(amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);'),
  (Match m) {
    final tok = m.group(1)!;
    switch (tok) {
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
        final code = tok.startsWith('#x') || tok.startsWith('#X')
            ? int.tryParse(tok.substring(2), radix: 16)
            : int.tryParse(tok.substring(1));
        if (code != null && code > 0 && code <= 0x10FFFF) {
          return String.fromCharCode(code);
        }
        return m.group(0)!;
    }
  },
);

String _safeDecodeUriComponent(String s) {
  try {
    return Uri.decodeFull(s);
  } on ArgumentError {
    return s;
  }
}
