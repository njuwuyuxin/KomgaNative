import 'package:drift/drift.dart';

/// HTTP 响应缓存（离线读的底座）。
class CachedResponses extends Table {
  /// 服务器身份（规范化 baseUrl），多服务器共库不串数据。
  TextColumn get scope => text()();

  /// 完整请求地址，含查询串。
  TextColumn get url => text()();

  /// `CacheKind.name`：json / image。
  TextColumn get kind => text()();

  IntColumn get byteSize => integer()();

  BlobColumn get body => blob()();

  /// 最近使用序号（单调递增）。
  IntColumn get lastUsedSeq => integer()();

  /// 是否属于整本下载受保护的页图（ARC-08）：`true` 不计入被动浏览 256 MB 预算，且永不被 LRU 驱逐。
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{scope, url};
}

/// 已下载（整本）的书（ARC-07：按 `{scope, bookId}` 复合主键隔离多服务器）。
class DownloadedBooks extends Table {
  /// 服务器分区键（规范化 baseUrl）；空串兼容单测默认值。
  TextColumn get scope => text().withDefault(const Constant(''))();

  TextColumn get bookId => text()();

  TextColumn get seriesId => text()();

  IntColumn get pageCount => integer()();

  /// 这次下载实际抓到的字节数（设置页/详情页展示用）。
  IntColumn get bytes => integer()();

  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{scope, bookId};
}

/// 下载队列的持久化条目（FIX-07 / ARC-07：按 `{scope, bookId}` 复合主键隔离多服务器）。
class DownloadQueueEntries extends Table {
  /// 服务器分区键（规范化 baseUrl）；空串兼容单测默认值。
  TextColumn get scope => text().withDefault(const Constant(''))();

  TextColumn get bookId => text()();

  TextColumn get seriesId => text()();

  TextColumn get name => text()();

  TextColumn get number => text().withDefault(const Constant(''))();

  IntColumn get pagesCount => integer()();

  /// `queued` / `active`；重启后一律按 `queued` 处理。
  TextColumn get state => text()();

  /// 已完成页数 / 总页数。
  IntColumn get done => integer().withDefault(const Constant(0))();

  IntColumn get total => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{scope, bookId};
}

/// 缓存占用统计（设置页展示）。
class CacheUsage {
  const CacheUsage({required this.bytes, required this.entries});

  static const CacheUsage empty = CacheUsage(bytes: 0, entries: 0);

  final int bytes;
  final int entries;

  bool get isEmpty => entries == 0;

  String get humanSize {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
