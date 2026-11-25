import 'package:flutter/foundation.dart';
import 'package:komga_api/komga_api.dart';
import 'package:komga_native/src/data/cache/connectivity_filter.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';

/// [HttpCache] 的 Drift 实现。
///
/// 除了存取，它还负责**广播在线状态**：传输层是唯一知道"这次请求成功了没有"
/// 的地方，经 [ConnectivityFilter] 抗抖动滤波后通过 [offline] 广播给 UI。
class DriftHttpCache implements HttpCache {
  DriftHttpCache(
    this._db, {
    Duration offlineGraceWindow = const Duration(milliseconds: 1800),
    Duration minOfflineDwell = const Duration(milliseconds: 2500),
    int offlineFailureThreshold = 2,
    int decorativeRecoveryThreshold = 3,
    ClockNow? now,
    TimerScheduler? schedule,
  }) {
    _filter = ConnectivityFilter(
      onChanged: _setOffline,
      offlineFailureThreshold: offlineFailureThreshold,
      offlineGraceWindow: offlineGraceWindow,
      minOfflineDwell: minOfflineDwell,
      decorativeRecoveryThreshold: decorativeRecoveryThreshold,
      now: now,
      schedule: schedule,
    );
  }

  final HttpCacheDatabase _db;
  late final ConnectivityFilter _filter;

  /// true = 传输层确认处于离线/服务不可达状态，当前内容可能来自缓存。
  final ValueNotifier<bool> offline = ValueNotifier<bool>(false);

  void _setOffline(bool value) {
    if (offline.value != value) offline.value = value;
  }

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
  void reportOnline(
    String scope, {
    RequestPriority priority = RequestPriority.primary,
  }) => _filter.reportOnline(scope, priority: priority);

  @override
  void reportOffline(
    String scope, {
    RequestPriority priority = RequestPriority.primary,
  }) => _filter.reportOffline(scope, priority: priority);

  /// 用户主动点击重试：下一次核心请求成功可绕过最小驻留时长立刻撤掉离线提示。
  void markRetryRequested() => _filter.markRetryRequested();

  Future<CacheUsage> usage({String? scope}) => _db.usage(scope: scope);

  Stream<Object?> get updates => _db.cachedResponsesUpdates();

  Future<void> clear({String? scope}) => _db.clear(scope: scope);

  void dispose() {
    _filter.dispose();
    offline.dispose();
  }
}
