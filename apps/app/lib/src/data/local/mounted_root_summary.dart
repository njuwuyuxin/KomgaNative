import 'package:yomu_platform/yomu_platform.dart';

/// 已挂载外部本地漫画根目录的展示快照（与 Drift `LocalMountedRootsRow` 解耦，供 UI 层消费）。
final class MountedRootSummary {
  const MountedRootSummary({
    required this.id,
    required this.displayName,
    required this.uriOrBookmark,
    required this.kind,
    required this.enabled,
    required this.hasNomedia,
    required this.booksCount,
    required this.createdAt,
  });

  final String id;
  final String displayName;
  final String uriOrBookmark;
  final ExternalRootKind kind;
  final bool enabled;
  final bool hasNomedia;
  final int booksCount;
  final DateTime createdAt;

  MountedExternalRoot toExternalRoot() => MountedExternalRoot(
    id: id,
    displayName: displayName,
    uriOrBookmark: uriOrBookmark,
    kind: kind,
    hasNomedia: hasNomedia,
  );
}
