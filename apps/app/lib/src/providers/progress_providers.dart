import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_api/komga_api.dart';
import 'package:komga_native/src/data/progress/progress_database.dart';
import 'package:komga_native/src/data/progress/progress_store.dart';
import 'package:komga_native/src/data/progress/progress_sync_service.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/session/session_controller.dart';
import 'package:komga_sync_engine/komga_sync_engine.dart';
import 'package:path_provider/path_provider.dart';

/// 本地进度库（Drift）。
///
/// 只在真正需要时才打开（`Provider` 是懒的），测试里覆盖 [progressStoreProvider]
/// 就不会碰 sqlite，也不需要 path_provider 的平台通道。
final Provider<ProgressDatabase> progressDatabaseProvider =
    Provider<ProgressDatabase>((Ref ref) {
      final db = ProgressDatabase(
        _openConnection(),
        legacyCacheDbPath: () async {
          final dir = await getApplicationSupportDirectory();
          return '${dir.path}/komga_cache.sqlite';
        },
      );
      ref.onDispose(db.close);
      return db;
    });

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    // 不用 path 包拼路径：这里只有一层目录，`/` 在 Windows/Android/iOS 都成立。
    final file = File('${dir.path}/komga_native.sqlite');
    return NativeDatabase.createInBackground(file);
  });
}

final Provider<ProgressStore> progressStoreProvider = Provider<ProgressStore>(
  (Ref ref) => DriftProgressStore(ref.watch(progressDatabaseProvider)),
);

/// 进度同步服务：阅读器写、书架读，两边共用同一个实例。
///
/// **上传必须自己建一个短会话**，不能走 `readerRepositoryProvider`：
/// 仓库在构造时依赖本 provider（见 `reader_providers.dart`），
/// 如果这里再反过来读仓库，Riverpod 会判定循环依赖并抛错
/// （真机上表现为"翻页了但服务端永远收不到、日志里一串 CircularDependencyError"）。
final Provider<ProgressSyncService> progressSyncProvider =
    Provider<ProgressSyncService>((Ref ref) {
      return ProgressSyncService(
        store: ref.watch(progressStoreProvider),
        upload: (ProgressTarget target) => _uploadProgress(ref, target),
      );
    });

Future<void> _uploadProgress(Ref ref, ProgressTarget target) async {
  final session = ref.read(sessionProvider);
  if (session is! SessionConnected) throw const NetworkFailure();

  final komga = KomgaSession.withApiKey(
    address: session.server.address,
    apiKey: session.server.apiKey,
    trust: session.server.tls,
    // 只为"PATCH 成功即在线"这一个信号：网络恢复后，补交成功的同时撤掉离线提示。
    cache: ref.read(httpCacheProvider),
  );
  try {
    await komga.updateReadProgress(
      target.bookId,
      page: target.page,
      completed: target.completed,
    );
  } on KomgaError catch (error) {
    throw shelfFailureOf(error);
  } finally {
    // 一次上传一个连接太浪费？这里只发 PATCH，连接复用收益很小，
    // 换来的是"不依赖仓库、不共享 dio 生命周期"，不会被会话重建影响。
    komga.close();
  }
}
