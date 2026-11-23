/// 收藏集与阅读列表成员变更的纯计算逻辑。
///
/// 保持零 Flutter 依赖，覆盖单选、批量多选、去重保序，以及 Komga 禁止空集合的删除判定。
library;

/// 目标项集合在某个容器（收藏集/阅读列表）中的归属状态。
enum MembershipState { none, partial, all }

/// 计算 [targetIds] 在 [containerIds] 中的归属状态。
MembershipState membershipOf(
  List<String> containerIds,
  Iterable<String> targetIds,
) {
  final targets = targetIds.toSet();
  if (targets.isEmpty) return MembershipState.none;
  final container = containerIds.toSet();
  var hits = 0;
  for (final id in targets) {
    if (container.contains(id)) hits++;
  }
  if (hits == 0) return MembershipState.none;
  if (hits == targets.length) return MembershipState.all;
  return MembershipState.partial;
}

/// 保持既有顺序，将 [toAdd] 中尚未出现的元素追加到末尾并去重。
List<String> mergeUniqueIds(List<String> existing, Iterable<String> toAdd) {
  final seen = <String>{};
  final result = <String>[];
  for (final id in existing) {
    if (seen.add(id)) result.add(id);
  }
  for (final id in toAdd) {
    if (seen.add(id)) result.add(id);
  }
  return result;
}

/// 保持既有顺序，从 [existing] 中移除所有出现在 [toRemove] 里的元素。
List<String> removeMatchingIds(
  List<String> existing,
  Iterable<String> toRemove,
) {
  final drop = toRemove.toSet();
  if (drop.isEmpty) return List<String>.of(existing);
  return <String>[
    for (final id in existing)
      if (!drop.contains(id)) id,
  ];
}

/// 一次勾选保存产生的服务端变更计划：更新项 + 因变空而需删除的项。
class MembershipChangePlan {
  const MembershipChangePlan({required this.updates, required this.deletions});

  final List<({String id, List<String> nextIds})> updates;
  final List<({String id, String name})> deletions;

  bool get isEmpty => updates.isEmpty && deletions.isEmpty;
}

/// 根据用户在勾选面板里的目标状态，生成最小变更计划。
///
/// - 状态未变化或仍处于 [MembershipState.partial]（批量未改动）的容器跳过；
/// - 勾选 [MembershipState.all] → 追加缺失的目标 id；
/// - 取消勾选 [MembershipState.none] → 移出目标 id；若移出后变空则归入
///   [MembershipChangePlan.deletions]（Komga 1.30.1 实测拒绝空的 PATCH）。
MembershipChangePlan planMembershipChanges({
  required List<({String id, String name, List<String> memberIds})> containers,
  required List<String> targetIds,
  required Map<String, MembershipState> desiredStates,
}) {
  final updates = <({String id, List<String> nextIds})>[];
  final deletions = <({String id, String name})>[];
  if (targetIds.isEmpty) {
    return MembershipChangePlan(updates: updates, deletions: deletions);
  }

  for (final container in containers) {
    final initial = membershipOf(container.memberIds, targetIds);
    final desired = desiredStates[container.id] ?? initial;
    if (desired == initial || desired == MembershipState.partial) continue;

    if (desired == MembershipState.all) {
      final next = mergeUniqueIds(container.memberIds, targetIds);
      if (next.length != container.memberIds.length) {
        updates.add((id: container.id, nextIds: next));
      }
    } else {
      final next = removeMatchingIds(container.memberIds, targetIds);
      if (next.isEmpty) {
        deletions.add((id: container.id, name: container.name));
      } else if (next.length != container.memberIds.length) {
        updates.add((id: container.id, nextIds: next));
      }
    }
  }
  return MembershipChangePlan(updates: updates, deletions: deletions);
}
