import 'package:flutter/foundation.dart';
import 'package:komga_api/komga_api.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';

/// [HttpCache] 的 Drift 实现。
///
/// 除了存取，它还负责**广播在线状态**：传输层是唯一知道"这次请求成功了没有"
/// 的地方，UI 只需要监听同一个实例上的 [offline]，不必各自猜。
class DriftHttpCache implements HttpCache {
  DriftHttpCache(this._db);

  final HttpCacheDatabase _db;

  /// true = 最近一次请求失败了，当前内容可能是缓存。UI 据此显示离线提示。
  final ValueNotifier<bool> offline = ValueNotifier<bool>(false);

  @override
  Future<Uint8List?> read(String scope, String url) async {
    final row = await _db.read(scope, url);
    return row?.body;
  }

  @override
  Future<Uint8List?> readPinned(String scope, String url) async {
    final row = await _db.readPinned(scope, url);
    return row?.body;
  }

  @override
  Future<void> write(
    String scope,
    String url,
    CacheKind kind,
    Uint8List body,
  ) => _db.write(scope, url, kind.name, body);

  @override
  void reportOnline(String scope) {
    if (offline.value) offline.value = false;
  }

  @override
  void reportOffline(String scope) {
    if (!offline.value) offline.value = true;
  }

  Future<CacheUsage> usage({String? scope}) => _db.usage(scope: scope);

  Stream<Object?> get updates => _db.cachedResponsesUpdates();

  Future<void> clear({String? scope}) => _db.clear(scope: scope);

  void dispose() => offline.dispose();
}
