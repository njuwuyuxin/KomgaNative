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

/// 服务器移除时触发的内存清理回调注册表（单向解耦：`SessionController` 仅广播，
/// `progressSyncProvider` 注册清理动作，避免循环依赖且不受 Riverpod 3 监听暂停影响）。
final Provider<Set<void Function(String scope)>> scopeRemovedListenersProvider =
    Provider<Set<void Function(String scope)>>((Ref ref) {
      final listeners = <void Function(String scope)>{};
      ref.onDispose(listeners.clear);
      return listeners;
    });

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
          if (isLocalSourceKey(scope)) return false;
          final source = ref.read(contentSourceDescriptorsProvider)[scope];
          // 冷启动服务器列表尚未加载完成时，不认识的非本地 scope 一律先入队，待上传时再按能力位决定上传或丢弃（N2）。
          return source?.capabilities.syncsProgressRemotely ?? true;
        },
        scopedUpload: (String scope, ProgressTarget target) =>
            _uploadProgress(ref, scope, target),
      );
      void onScopeRemoved(String scope) {
        unawaited(service.clearScope(scope));
      }

      final removedListeners = ref.read(scopeRemovedListenersProvider)
        ..add(onScopeRemoved);
      ref.listen<Map<String, ContentSource>>(contentSourceDescriptorsProvider, (
        _,
        Map<String, ContentSource> next,
      ) {
        final remoteKeys = next.values
            .where((ContentSource s) => s.capabilities.syncsProgressRemotely)
            .map((ContentSource s) => s.sourceKey)
            .toList(growable: false);
        if (remoteKeys.isEmpty) return;
        for (final key in remoteKeys) {
          service.resetAuthBlock(key);
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
      ref.onDispose(() {
        removedListeners.remove(onScopeRemoved);
        service.dispose();
      });
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
