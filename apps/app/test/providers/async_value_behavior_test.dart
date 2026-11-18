import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/library_providers.dart';

import '../support/fake_library.dart';

/// 记录 Riverpod 3 的一个反直觉行为，防止后来人再踩：
///
/// FutureProvider **首次加载失败**时，状态不是 `AsyncError`，而是
/// `AsyncLoading(error: …, stackTrace: …)`——`isLoading` 和 `hasError` 同时为真。
/// 用 `switch (value) { AsyncError() => … }` 做错误分支会悄悄掉进 loading 分支
/// （书架详情页就这么白屏过）。UI 一律按 `hasError` / `value` 判断。
void main() {
  ProviderContainer containerWith(FakeLibraryRepository repository) {
    final container = ProviderContainer(
      overrides: <Override>[
        libraryRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      seriesBooksProvider((seriesId: 's1', size: 100)),
      (
        AsyncValue<PageResult<Book>>? previous,
        AsyncValue<PageResult<Book>> next,
      ) {},
    );
    addTearDown(subscription.close);
    return container;
  }

  test('失败态：hasError 为真、value 为 null，且不能只认 AsyncError', () async {
    final repository = FakeLibraryRepository(
      series: demoShelf(),
      booksFailure: const NetworkFailure(),
    );
    final container = containerWith(repository);

    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final state = container.read(
      seriesBooksProvider((seriesId: 's1', size: 100)),
    );

    expect(state.hasError, isTrue);
    expect(state.error, isA<NetworkFailure>());
    expect(state.value, isNull);
    expect(
      state is AsyncError<Object?>,
      isFalse,
      reason:
          'Riverpod 3 首次失败给的是 AsyncLoading + error；'
          '若这条断言开始失败，说明行为变了，需要回头检查 UI 的判定方式',
    );
  });

  test('成功态：value 有数据、hasError 为假', () async {
    final container = containerWith(FakeLibraryRepository(series: demoShelf()));

    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final state = container.read(
      seriesBooksProvider((seriesId: 's1', size: 100)),
    );

    expect(state.hasError, isFalse);
    expect(state.value?.items, hasLength(6));
  });
}
