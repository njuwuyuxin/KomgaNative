import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_native/src/data/cache/drift_http_cache.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';
import 'package:path_provider/path_provider.dart';

/// 内容缓存库（Drift，独立于进度库）。
///
/// 懒打开：没有请求也不会创建文件。测试里覆盖 [httpCacheProvider] 就不会碰
/// path_provider 的平台通道。
final Provider<HttpCacheDatabase> httpCacheDatabaseProvider =
    Provider<HttpCacheDatabase>((Ref ref) {
      final db = HttpCacheDatabase(_openCacheConnection());
      ref.onDispose(db.close);
      return db;
    });

LazyDatabase _openCacheConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/komga_cache.sqlite');
    return NativeDatabase.createInBackground(file);
  });
}

/// 会话与 UI 共用的缓存实例（同一个 [DriftHttpCache.offline] 通知源）。
final Provider<DriftHttpCache> httpCacheProvider = Provider<DriftHttpCache>((
  Ref ref,
) {
  final cache = DriftHttpCache(ref.watch(httpCacheDatabaseProvider));
  ref.onDispose(cache.dispose);
  return cache;
});

/// 缓存占用（设置页）。清空缓存后 `ref.invalidate(cacheUsageProvider)` 刷新。
final cacheUsageProvider = FutureProvider<CacheUsage>((Ref ref) {
  return ref.watch(httpCacheProvider).usage();
});

/// 当前是否处于"离线（或服务端不可用）"状态。
///
/// 用 [DriftHttpCache.offline] 的 `ValueListenable` 而不是 Riverpod 状态：
/// 状态由传输层写、UI 只读，中间不需要一个可变的 provider 来转发。
final Provider<ValueListenable<bool>> offlineProvider =
    Provider<ValueListenable<bool>>((Ref ref) {
      return ref.watch(httpCacheProvider).offline;
    });
