import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/progress/progress_store.dart';
import 'package:yomu/src/data/progress/progress_sync_service.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_sync/yomu_sync.dart';

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
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/komga_native.sqlite');
      return NativeDatabase.createInBackground(file);
    } on MissingPluginException {
      return NativeDatabase.memory();
    }
  });
}

final Provider<ProgressStore> progressStoreProvider = Provider<ProgressStore>(
  (Ref ref) => DriftProgressStore(ref.watch(progressDatabaseProvider)),
);

/// 进度同步服务：经 [contentSourceDescriptorsProvider] 的 `syncsProgressRemotely`
/// 与 [progressSinkForSourceProvider] 按显式内容源分区独立上传（ARC-07 / P1-4）。
final Provider<ProgressSyncService> progressSyncProvider =
    Provider<ProgressSyncService>((Ref ref) {
      final service = ProgressSyncService(
        store: ref.watch(progressStoreProvider),
        defaultFlushScopes: () => ref
            .read(contentSourceDescriptorsProvider)
            .values
            .where((ContentSource s) => s.capabilities.syncsProgressRemotely)
            .map((ContentSource s) => s.sourceKey),
        syncsRemotely: (String scope) {
          final source = ref.read(contentSourceDescriptorsProvider)[scope];
          return source?.capabilities.syncsProgressRemotely ?? false;
        },
        scopedUpload: (String scope, ProgressTarget target) =>
            _uploadProgress(ref, scope, target),
      );
      ref.listen<AsyncValue<List<StoredServer>>>(serverListProvider, (
        _,
        AsyncValue<List<StoredServer>> next,
      ) {
        final servers = next.value;
        if (servers == null || servers.isEmpty) return;
        for (final server in servers) {
          service.resetAuthBlock(server.id);
        }
        unawaited(service.flush());
      });
      ref.listen<SessionState>(sessionProvider, (_, SessionState next) {
        if (next is SessionConnected) {
          final scope = next.server.id;
          service.resetAuthBlock(scope);
          unawaited(service.flush(scope: scope));
        }
      });
      ref.onDispose(service.dispose);
      return service;
    });

Future<void> _uploadProgress(
  Ref ref,
  String scope,
  ProgressTarget target,
) async {
  final source = ref.read(contentSourceDescriptorsProvider)[scope];
  if (source == null) throw const NetworkFailure();
  if (!source.capabilities.syncsProgressRemotely) return;
  final sink = ref.read(progressSinkForSourceProvider(scope));
  if (sink == null) throw const NetworkFailure();
  await sink.uploadProgress(target);
}
