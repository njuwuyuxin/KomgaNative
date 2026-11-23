import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/data/curation_ops.dart';

void main() {
  group('membershipOf', () {
    test('空目标或空容器返回 none', () {
      expect(
        membershipOf(const <String>['a'], const <String>[]),
        MembershipState.none,
      );
      expect(
        membershipOf(const <String>[], const <String>['a']),
        MembershipState.none,
      );
    });

    test('单个与批量归属计算准确（none / partial / all）', () {
      expect(
        membershipOf(const <String>['s1', 's2'], const <String>['s3']),
        MembershipState.none,
      );
      expect(
        membershipOf(const <String>['s1', 's2'], const <String>['s1']),
        MembershipState.all,
      );
      expect(
        membershipOf(const <String>['s1', 's2'], const <String>['s1', 's3']),
        MembershipState.partial,
      );
      expect(
        membershipOf(
          const <String>['s1', 's2', 's3'],
          const <String>['s2', 's1'],
        ),
        MembershipState.all,
      );
    });
  });

  group('mergeUniqueIds / removeMatchingIds', () {
    test('追加去重并保持既有顺序', () {
      expect(
        mergeUniqueIds(
          const <String>['s2', 's1'],
          const <String>['s1', 's3', 's3'],
        ),
        const <String>['s2', 's1', 's3'],
      );
    });

    test('移出指定元素并保持剩余顺序', () {
      expect(
        removeMatchingIds(
          const <String>['s1', 's2', 's3'],
          const <String>['s2'],
        ),
        const <String>['s1', 's3'],
      );
      expect(
        removeMatchingIds(const <String>['s1'], const <String>['s1']),
        isEmpty,
      );
    });
  });

  group('planMembershipChanges', () {
    test('勾选追加、取消非最后一项走 update、取消最后一项走 deletion、未改/partial 跳过', () {
      final plan = planMembershipChanges(
        containers: const <({String id, String name, List<String> memberIds})>[
          (id: 'c1', name: 'Add here', memberIds: <String>['s1']),
          (id: 'c2', name: 'Remove one', memberIds: <String>['s1', 's2']),
          (id: 'c3', name: 'Becomes empty', memberIds: <String>['s2']),
          (id: 'c4', name: 'Untouched partial', memberIds: <String>['s2']),
        ],
        targetIds: const <String>['s2', 's3'],
        desiredStates: const <String, MembershipState>{
          'c1': MembershipState.all,
          'c2': MembershipState.none,
          'c3': MembershipState.none,
          'c4': MembershipState.partial,
        },
      );

      expect(plan.updates, hasLength(2));
      expect(plan.updates[0].id, 'c1');
      expect(plan.updates[0].nextIds, const <String>['s1', 's2', 's3']);
      expect(plan.updates[1].id, 'c2');
      expect(plan.updates[1].nextIds, const <String>['s1']);
      expect(plan.deletions, hasLength(1));
      expect(plan.deletions.single.id, 'c3');
      expect(plan.deletions.single.name, 'Becomes empty');
      expect(plan.hasAdditions, isTrue);
      expect(plan.hasRemovals, isTrue);
      expect(plan.isPureAddition, isFalse);
    });

    test('仅勾选加入时 isPureAddition 为 true；仅移出时为 false', () {
      final addOnly = planMembershipChanges(
        containers: const <({String id, String name, List<String> memberIds})>[
          (id: 'c1', name: 'Add here', memberIds: <String>['s1']),
        ],
        targetIds: const <String>['s2', 's3'],
        desiredStates: const <String, MembershipState>{
          'c1': MembershipState.all,
        },
      );
      expect(addOnly.isPureAddition, isTrue);

      final removeOnly = planMembershipChanges(
        containers: const <({String id, String name, List<String> memberIds})>[
          (id: 'c1', name: 'Remove here', memberIds: <String>['s1', 's2']),
        ],
        targetIds: const <String>['s2'],
        desiredStates: const <String, MembershipState>{
          'c1': MembershipState.none,
        },
      );
      expect(removeOnly.isPureAddition, isFalse);
    });

    test('目标未变化时计划为空', () {
      final plan = planMembershipChanges(
        containers: const <({String id, String name, List<String> memberIds})>[
          (id: 'c1', name: 'Existing', memberIds: <String>['s1']),
        ],
        targetIds: const <String>['s1'],
        desiredStates: const <String, MembershipState>{
          'c1': MembershipState.all,
        },
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.isPureAddition, isFalse);
    });
  });
}
