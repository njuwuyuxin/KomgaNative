import 'package:drift/drift.dart';

part 'http_cache_database.g.dart';

/// HTTP 响应缓存（离线读的底座）。
///
/// 和进度库**故意分两个数据库文件**：进度是不可再生的用户数据（丢了就是丢了），
/// 缓存随时可以清空重建。放一起会让"清缓存"有误伤用户数据的风险，
/// 也会让备份/迁移策略互相牵制。
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
  ///
  /// 用序号而不是时间戳：Drift 默认把 DateTime 存成 **秒**，一秒内的多次读写
  /// 全部并列，LRU 就退化成"随机淘汰"（写测试时当场抓到）。序号还没有时钟
  /// 回拨问题——进程重启后从 `MAX(seq)` 续上。
  IntColumn get lastUsedSeq => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{scope, url};
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

@DriftDatabase(tables: <Type>[CachedResponses])
class HttpCacheDatabase extends _$HttpCacheDatabase {
  HttpCacheDatabase(
    super.executor, {
    this.maxImageBytes = defaultMaxImageBytes,
    this.maxJsonRows = 400,
  });

  /// 页图/封面预算。256 MB ≈ 100 页 4K 扫描或 300 页普通页图；
  /// 再大就会在低端机上挤占系统空间，而离线目录本身不该是"整库镜像"。
  static const int defaultMaxImageBytes = 256 * 1024 * 1024;

  final int maxImageBytes;

  /// JSON 条数上限（书架每页一条）。不参与字节淘汰：它很小，却是离线打开的前提。
  final int maxJsonRows;

  /// 进程内的序号种子；第一次用时从库里续上，避免重启后新写入排到旧数据前面。
  int? _seqSeed;

  @override
  int get schemaVersion => 1;

  Future<CachedResponse?> read(String scope, String url) async {
    final row =
        await (select(cachedResponses)
              ..where((t) => t.scope.equals(scope) & t.url.equals(url)))
            .getSingleOrNull();
    if (row == null) return null;
    // 触摸一下：LRU 淘汰靠它。失败（磁盘只读等）不影响本次返回。
    await (update(
      cachedResponses,
    )..where((t) => t.scope.equals(scope) & t.url.equals(url))).write(
      CachedResponsesCompanion(lastUsedSeq: Value<int>(await _nextSeq())),
    );
    return row;
  }

  Future<void> write(
    String scope,
    String url,
    String kind,
    Uint8List body,
  ) async {
    final seq = await _nextSeq();
    await into(cachedResponses).insertOnConflictUpdate(
      CachedResponsesCompanion.insert(
        scope: scope,
        url: url,
        kind: kind,
        byteSize: body.length,
        body: body,
        lastUsedSeq: seq,
      ),
    );
    if (kind == 'image') {
      await _evictImages(keepUrl: url);
    } else {
      await _pruneJson(scope);
    }
  }

  Future<CacheUsage> usage({String? scope}) async {
    final byteSum = cachedResponses.byteSize.sum();
    final count = cachedResponses.url.count();
    final query = selectOnly(cachedResponses)
      ..addColumns(<Expression<Object>>[byteSum, count]);
    final filter = scope;
    if (filter != null) query.where(cachedResponses.scope.equals(filter));
    final row = await query.getSingle();
    return CacheUsage(
      bytes: row.read(byteSum) ?? 0,
      entries: row.read(count) ?? 0,
    );
  }

  Future<void> clear({String? scope}) async {
    final filter = scope;
    final statement = delete(cachedResponses);
    if (filter != null) {
      statement.where((t) => t.scope.equals(filter));
    }
    await statement.go();
  }

  /// 按字节预算淘汰最久未用的图片，直到回到预算内。
  ///
  /// 分批取（每批 32 行）而不是把全部行读进内存：缓存可能有几千条，
  /// 一次性 `get()` 在低端机上就是一次可感知的卡顿。
  ///
  /// [keepUrl] 是刚写入的那条：单条就超预算时（一张 8 MB 长图），
  /// 不能让它把自己挤掉——用户刚等到它下载完。
  Future<void> _evictImages({required String keepUrl}) async {
    var over = await _imageBytes() - maxImageBytes;
    while (over > 0) {
      final rows = await _oldestImages();
      if (rows.isEmpty) return;
      var removedAny = false;
      for (final row in rows) {
        if (over <= 0) return;
        if (row.url == keepUrl) continue;
        await _deleteRow(row);
        over -= row.byteSize;
        removedAny = true;
      }
      // 只剩刚写入的那条：允许暂时超预算，不然"超预算的图永远存不下来"。
      if (!removedAny) return;
    }
  }

  Future<List<CachedResponse>> _oldestImages() {
    return (select(cachedResponses)
          ..where((t) => t.kind.equals('image'))
          ..orderBy(<OrderClauseGenerator<CachedResponses>>[
            (t) => OrderingTerm(expression: t.lastUsedSeq),
          ])
          ..limit(32))
        .get();
  }

  Future<int> _imageBytes() async {
    final byteSum = cachedResponses.byteSize.sum();
    final query = selectOnly(cachedResponses)
      ..addColumns(<Expression<Object>>[byteSum])
      ..where(cachedResponses.kind.equals('image'));
    final row = await query.getSingle();
    return row.read(byteSum) ?? 0;
  }

  /// JSON 只按条数裁剪，且只裁当前服务器：别的服务器的书架不该被这次翻页挤掉。
  Future<void> _pruneJson(String scope) async {
    final count = cachedResponses.url.count();
    final counting = selectOnly(cachedResponses)
      ..addColumns(<Expression<Object>>[count])
      ..where(
        cachedResponses.scope.equals(scope) &
            cachedResponses.kind.equals('json'),
      );
    var over = ((await counting.getSingle()).read(count) ?? 0) - maxJsonRows;
    while (over > 0) {
      final rows =
          await (select(cachedResponses)
                ..where((t) => t.scope.equals(scope) & t.kind.equals('json'))
                ..orderBy(<OrderClauseGenerator<CachedResponses>>[
                  (t) => OrderingTerm(expression: t.lastUsedSeq),
                ])
                ..limit(32))
              .get();
      if (rows.isEmpty) return;
      for (final row in rows) {
        if (over <= 0) return;
        await _deleteRow(row);
        over--;
      }
    }
  }

  Future<void> _deleteRow(CachedResponse row) {
    return (delete(
      cachedResponses,
    )..where((t) => t.scope.equals(row.scope) & t.url.equals(row.url))).go();
  }

  /// 单调序号：`microsecondsSinceEpoch` 在同一毫秒内可能重复（Windows 时钟精度），
  /// 所以再和"上一个序号 + 1"取大者。
  Future<int> _nextSeq() async {
    final seed = _seqSeed ?? await _maxSeq();
    final now = DateTime.now().microsecondsSinceEpoch;
    final seq = now > seed ? now : seed + 1;
    _seqSeed = seq;
    return seq;
  }

  Future<int> _maxSeq() async {
    final maxSeq = cachedResponses.lastUsedSeq.max();
    final query = selectOnly(cachedResponses)
      ..addColumns(<Expression<Object>>[maxSeq]);
    final row = await query.getSingle();
    return row.read(maxSeq) ?? 0;
  }
}
