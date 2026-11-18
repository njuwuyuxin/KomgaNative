import 'package:komga_domain/komga_domain.dart';

/// 把 Komga 的 JSON 映射成领域模型。
///
/// 输入形状全部来自**真实服务器响应**（`test/fixtures/` 里的文件就是从
/// Komga 1.30.1 实例上抓下来的），字段名以 `docs/komga-api-verification.md`
/// 记录的实测结果为准。
///
/// 解析原则：任何缺失或类型不符的字段都退化成安全默认值，**不在解析期抛异常**。
/// 服务端跨版本时"少一个字段"不应该让整页书架空白；结构性错误（不是对象/数组）
/// 由调用方检查后再进这里。
Map<Object?, Object?>? asMap(Object? raw) =>
    raw is Map<Object?, Object?> ? raw : null;

String _str(Object? raw) => raw is String ? raw : '';

String? _strOrNull(Object? raw) => raw is String && raw.isNotEmpty ? raw : null;

int _int(Object? raw) => raw is int ? raw : 0;

int? _intOrNull(Object? raw) => raw is int ? raw : null;

bool _bool(Object? raw) => raw == true;

/// `BookDto.number`：OpenAPI 写的是 `string`，但实测服务器返回的是 **int**（`1`）。
/// 规格与运行时不一致，两种都收。
String _numberString(Object? raw) {
  if (raw is String) return raw;
  if (raw is num) return raw.toString();
  return '';
}

/// Komga 的时间戳是 ISO-8601，实测可能带 7 位小数
/// （`2026-11-17T09:19:11.9617379Z`）；`DateTime.tryParse` 能接受并截断到微秒，
/// 不需要自己处理。解析失败返回 null（调用方按"未读/无进度"处理）。
DateTime? parseServerDate(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

Library libraryFromJson(Map<Object?, Object?> json) => Library(
  id: _str(json['id']),
  name: _str(json['name']),
  unavailable: _bool(json['unavailable']),
);

Account accountFromJson(Map<Object?, Object?> json) {
  final roles = json['roles'];
  return Account(
    id: _str(json['id']),
    email: _str(json['email']),
    roles: roles is List<Object?>
        ? roles.whereType<String>().toList(growable: false)
        : const <String>[],
  );
}

Series seriesFromJson(Map<Object?, Object?> json) {
  final metadata = asMap(json['metadata']);
  // 书籍聚合（`booksMetadata`）：作者、出版日期、标签这些"系列自己没有"的字段
  // 在 Komga 里是从书聚合出来的（字段清单见 OpenAPI 的 BookMetadataAggregationDto）。
  final aggregate = asMap(json['booksMetadata']);
  final title = _str(metadata?['title']);
  final summary = _strOrNull(metadata?['summary']);
  return Series(
    id: _str(json['id']),
    libraryId: _str(json['libraryId']),
    // 实测：`name` 是服务器目录名，`metadata.title` 才是用户可读标题。
    title: title.isNotEmpty ? title : _str(json['name']),
    booksCount: _int(json['booksCount']),
    booksReadCount: _int(json['booksReadCount']),
    readingDirection: ReadingDirection.parse(
      _strOrNull(metadata?['readingDirection']),
    ),
    summary: summary ?? _strOrNull(aggregate?['summary']),
    authors: _authorNames(aggregate?['authors']),
    publisher: _strOrNull(metadata?['publisher']),
    releaseDate: parseServerDate(aggregate?['releaseDate']),
    tags: _stringList(aggregate?['tags']),
  );
}

/// `authors` 是 `[{name, role}]` 数组（AuthorDto）；只取名字，空名字丢掉。
List<String> _authorNames(Object? raw) {
  if (raw is! List<Object?>) return const <String>[];
  final names = <String>[];
  for (final entry in raw) {
    final name = _str(asMap(entry)?['name']).trim();
    if (name.isNotEmpty && !names.contains(name)) names.add(name);
  }
  return List<String>.unmodifiable(names);
}

/// 字符串数组（标签）。非字符串项直接跳过，不让一条脏数据毁掉整个系列。
List<String> _stringList(Object? raw) {
  if (raw is! List<Object?>) return const <String>[];
  return List<String>.unmodifiable(raw.whereType<String>());
}

Book bookFromJson(Map<Object?, Object?> json) {
  final media = asMap(json['media']);
  return Book(
    id: _str(json['id']),
    seriesId: _str(json['seriesId']),
    name: _str(json['name']),
    pagesCount: _int(media?['pagesCount']),
    number: _numberString(json['number']),
    mediaProfile: MediaProfile.parse(_strOrNull(media?['mediaProfile'])),
    sizeBytes: _int(json['sizeBytes']),
    readProgress: readProgressFromJson(json['readProgress']),
  );
}

/// `readProgress` 为 `null` 表示未读；没有可用的 `lastModified` 时也按未读处理，
/// 否则多设备对账会拿一个假时间戳去覆盖别的设备。
ReadProgress? readProgressFromJson(Object? raw) {
  final map = asMap(raw);
  if (map == null) return null;
  final lastModified = parseServerDate(map['lastModified']);
  if (lastModified == null) return null;
  return ReadProgress(
    page: _int(map['page']),
    completed: _bool(map['completed']),
    lastModified: lastModified,
    readDate: parseServerDate(map['readDate']),
  );
}

PageInfo pageInfoFromJson(Map<Object?, Object?> json) => PageInfo(
  number: _int(json['number']),
  width: _intOrNull(json['width']),
  height: _intOrNull(json['height']),
  mediaType: _strOrNull(json['mediaType']),
  sizeBytes: _intOrNull(json['sizeBytes']),
);

/// 把 `{content:[…], totalElements:…, number:…, size:…}` 拆成领域分页结果。
PageResult<T> pageResultFromJson<T>(
  Map<Object?, Object?> json,
  T Function(Map<Object?, Object?> item) parse,
) {
  final content = json['content'];
  final items = content is List<Object?>
      ? content
            .whereType<Map<Object?, Object?>>()
            .map(parse)
            .toList(growable: false)
      : <T>[];
  return PageResult<T>(
    items: items,
    totalElements: _int(json['totalElements']),
    page: _int(json['number']),
    size: _int(json['size']),
  );
}
