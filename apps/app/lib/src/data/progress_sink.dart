import 'package:komga_api/komga_api.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu_sync/yomu_sync.dart';

/// 内容源的远程阅读进度上传端口（P1-4）。
///
/// 仅在内容源声明 `SourceCapabilities.syncsProgressRemotely == true` 时由
/// `ProgressSyncService` 按 `SourceBundle` 分发；不支持远程同步的源
/// （如本机书库、只读 OPDS）使用 [NoopProgressSink]。
abstract interface class ProgressSink {
  Future<void> uploadProgress(ProgressTarget target);
}

/// 空实现：适用于本机书库与只读目录源。
final class NoopProgressSink implements ProgressSink {
  const NoopProgressSink();

  @override
  Future<void> uploadProgress(ProgressTarget target) async {}
}

/// Komga 协议的远程进度上传实现。
final class KomgaProgressSink implements ProgressSink {
  const KomgaProgressSink(this._session);

  final KomgaSession _session;

  @override
  Future<void> uploadProgress(ProgressTarget target) async {
    try {
      await _session.updateReadProgress(
        target.bookId,
        page: target.page,
        completed: target.completed,
      );
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }
}
