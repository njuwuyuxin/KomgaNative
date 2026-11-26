import 'package:yomu_domain/yomu_domain.dart';

/// 对账结论。
enum SyncAction {
  /// 本地与服务端一致，什么都不用做。
  inSync,

  /// 服务端更新（别的设备读得更远/刚标记完成），采纳服务端。
  adoptRemote,

  /// 本地有未提交的进度，先推上去。
  pushLocal,

  /// 服务端时间更旧（可能是旧快照/乱序响应），忽略它。
  staleRemote,
}

class SyncDecision {
  const SyncDecision(this.action, {this.remote, this.reason = ''});

  final SyncAction action;

  /// 采纳服务端时给出的新进度（服务端可能已删除进度 → null）。
  final ReadProgress? remote;

  final String reason;

  @override
  String toString() =>
      'SyncDecision($action, remote: $remote, reason: $reason)';
}

/// 决定本书此刻该怎么办。
///
/// [base] 是本地记录的"上次确认过的服务端状态"（未读过则为 null）；
/// [remote] 是刚拉到的服务端进度；
/// [hasPending] 表示本地 outbox 里还有没提交的进度。
///
/// 关键约定：**只信服务端的 `lastModified`，不用设备墙钟**。设备时钟漂移是
/// 多端互相覆盖最常见的原因。
SyncDecision decideSync({
  required ReadProgress? base,
  required ReadProgress? remote,
  required bool hasPending,
}) {
  if (hasPending) {
    return const SyncDecision(SyncAction.pushLocal, reason: '本地有未提交进度，后写者胜');
  }

  if (base == null && remote == null) {
    return const SyncDecision(SyncAction.inSync, reason: '双方都没有进度');
  }
  if (base == null && remote != null) {
    return SyncDecision(
      SyncAction.adoptRemote,
      remote: remote,
      reason: '本地首次见到该书进度',
    );
  }
  if (base != null && remote == null) {
    return const SyncDecision(
      SyncAction.adoptRemote,
      remote: null,
      reason: '服务端进度已被删除（标为未读）',
    );
  }

  final known = base!;
  final incoming = remote!;
  if (incoming.lastModified.isAfter(known.lastModified)) {
    final reason = incoming.page > known.page
        ? '其他设备读得更远（$known.page → ${incoming.page}）'
        : '其他设备更新了进度（${known.page} → ${incoming.page}）';
    return SyncDecision(
      SyncAction.adoptRemote,
      remote: incoming,
      reason: reason,
    );
  }
  return const SyncDecision(SyncAction.staleRemote, reason: '服务端时间不新于本地基准，忽略');
}
