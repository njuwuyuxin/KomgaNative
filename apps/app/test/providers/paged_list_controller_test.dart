import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/paged_list_controller.dart';
import 'package:yomu_domain/yomu_domain.dart';

class _TestPagedController extends PagedListController<String> {
  _TestPagedController(this.onFetch);

  final Future<PageResult<String>> Function(int page, int size) onFetch;

  @override
  int get pageSize => 2;

  @override
  Future<PageResult<String>> fetchPage(int page, int size) =>
      onFetch(page, size);
}

void main() {
  group('P2-4 PagedListController 领域异常与编程错误分流', () {
    test('ShelfFailure 保留已有列表并通过 loadMoreFailure 暴露给 UI', () async {
      final provider =
          AsyncNotifierProvider<_TestPagedController, PageResult<String>>(
            () => _TestPagedController((int page, int size) async {
              if (page == 0) {
                return const PageResult<String>(
                  items: <String>['a', 'b'],
                  totalElements: 4,
                  page: 0,
                  size: 2,
                );
              }
              throw const NetworkFailure();
            }),
          );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final first = await container.read(provider.future);
      expect(first.items, <String>['a', 'b']);

      await container.read(provider.notifier).loadMore();
      final ctrl = container.read(provider.notifier);
      expect(ctrl.loadingMore, isFalse);
      expect(ctrl.loadMoreFailure, isA<NetworkFailure>());
      expect(container.read(provider).value?.items, <String>['a', 'b']);
    });

    test('StateError 等编程错误不再被静默吞掉，抛出同时复位 loadingMore', () async {
      final provider =
          AsyncNotifierProvider<_TestPagedController, PageResult<String>>(
            () => _TestPagedController((int page, int size) async {
              if (page == 0) {
                return const PageResult<String>(
                  items: <String>['a', 'b'],
                  totalElements: 4,
                  page: 0,
                  size: 2,
                );
              }
              throw StateError('unexpected bug in page parser');
            }),
          );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(provider.future);

      await expectLater(
        () => container.read(provider.notifier).loadMore(),
        throwsA(isA<StateError>()),
      );
      expect(container.read(provider.notifier).loadingMore, isFalse);
    });
  });
}
