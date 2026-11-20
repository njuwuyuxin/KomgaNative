import 'dart:async';
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

/// 本地用户资产数据库（Drift）。
final Provider<ProgressDatabase> progressDatabaseProvider =
    Provider<ProgressDatabase>((Ref ref) {
      final serverStore = ref.read(serverStoreProvider);
      final db = ProgressDatabase(
        _openConnection(),
        legacyCacheDbPath: () async {
          final dir = await getApplicationSupportDirectory();
          return '${dir.path}/komga_cache.sqlite';
        },
        defaultLegacyScope: () async {
          final saved = await serverStore.load();
          return saved?.address.baseUrl ?? '';
        },
      );
      ref.onDispose(db.close);
      return db;
    });

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/komga_native.sqlite');
    return NativeDatabase.createInBackground(file);
  });
}

final Provider<ProgressStore> progressStoreProvider = Provider<ProgressStore>(
  (Ref ref) => DriftProgressStore(ref.watch(progressDatabaseProvider)),
);

/// 进度同步服务：按当前活动服务器 `baseUrl` 隔离本地读写与上传队列（ARC-07）。
final Provider<ProgressSyncService> progressSyncProvider =
    Provider<ProgressSyncService>((Ref ref) {
      final service = ProgressSyncService(
        store: ref.watch(progressStoreProvider),
        activeScope: () {
          final session = ref.read(sessionProvider);
          return session is SessionConnected
              ? session.server.address.baseUrl
              : '';
        },
        scopedUpload: (String scope, ProgressTarget target) =>
            _uploadProgress(ref, scope, target),
      );
      // 切换到新服务器或重新登录后，解除该服务器的鉴权停手标记并尝试冲洗其专属队列。
      ref.listen<SessionState>(sessionProvider, (_, SessionState next) {
        if (next is SessionConnected) {
          service.resetAuthBlock(next.server.address.baseUrl);
          unawaited(service.flush());
        }
      });
      return service;
    });

Future<void> _uploadProgress(
  Ref ref,
  String scope,
  ProgressTarget target,
) async {
  final session = ref.read(sessionProvider);
  if (session is! SessionConnected) throw const NetworkFailure();
  // 双重门闩：绝不把服务器 A 的待提交进度发往服务器 B。
  if (scope.isNotEmpty && session.server.address.baseUrl != scope) {
    throw const NetworkFailure();
  }

  final komga = KomgaSession.withApiKey(
    address: session.server.address,
    apiKey: session.server.apiKey,
    trust: session.server.tls,
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
    komga.close();
  }
}
