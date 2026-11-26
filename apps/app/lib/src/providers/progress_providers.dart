import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_api/komga_api.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/progress/progress_store.dart';
import 'package:yomu/src/data/progress/progress_sync_service.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/komga_session_provider.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_sync/yomu_sync.dart';
import 'package:path_provider/path_provider.dart';

export 'package:yomu/src/data/progress/progress_database.dart'
    show ProgressUserDao;

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

/// 进度同步服务：复用共享 [komgaSessionProvider] 连接池按服务器分区上传（ARC-07 / ARC-09）。
final Provider<ProgressSyncService> progressSyncProvider =
    Provider<ProgressSyncService>((Ref ref) {
      final service = ProgressSyncService(
        store: ref.watch(progressStoreProvider),
        activeScope: () =>
            ref.read(komgaSessionProvider)?.address.baseUrl ?? '',
        scopedUpload: (String scope, ProgressTarget target) =>
            _uploadProgress(ref, scope, target),
      );
      ref.listen<KomgaSession?>(komgaSessionProvider, (_, KomgaSession? next) {
        if (next != null) {
          service.resetAuthBlock(next.address.baseUrl);
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
  final komga = ref.read(komgaSessionProvider);
  if (komga == null) throw const NetworkFailure();
  if (scope.isNotEmpty && komga.address.baseUrl != scope) {
    throw const NetworkFailure();
  }

  try {
    await komga.updateReadProgress(
      target.bookId,
      page: target.page,
      completed: target.completed,
    );
  } on KomgaError catch (error) {
    throw shelfFailureOf(error);
  }
}
