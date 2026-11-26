import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_api/komga_api.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/progress/progress_store.dart';
import 'package:yomu/src/data/progress/progress_sync_service.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/komga_session_provider.dart';
import 'package:yomu/src/session/server_store.dart';
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

/// 进度同步服务：按显式服务器分区独立上传，不再依赖单会话回退（ARC-07 / ARC-09）。
final Provider<ProgressSyncService> progressSyncProvider =
    Provider<ProgressSyncService>((Ref ref) {
      final service = ProgressSyncService(
        store: ref.watch(progressStoreProvider),
        defaultFlushScopes: () {
          final servers = ref.read(serverListProvider).value;
          if (servers != null && servers.isNotEmpty) {
            return servers.map((StoredServer s) => s.address.baseUrl);
          }
          final session = ref.read(sessionProvider);
          if (session is SessionConnected) {
            return <String>[session.server.address.baseUrl];
          }
          return const <String>[];
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
          service.resetAuthBlock(server.address.baseUrl);
        }
        unawaited(service.flush());
      });
      ref.listen<SessionState>(sessionProvider, (_, SessionState next) {
        if (next is SessionConnected) {
          final url = next.server.address.baseUrl;
          service.resetAuthBlock(url);
          unawaited(service.flush(scope: url));
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
  final komga = ref.read(komgaSessionForServerProvider(scope));
  if (komga == null) throw const NetworkFailure();

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
