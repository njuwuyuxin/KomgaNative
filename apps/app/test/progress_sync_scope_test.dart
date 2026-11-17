import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/data/progress/progress_store.dart';
import 'package:komga_native/src/data/progress/progress_sync_service.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/progress_providers.dart';
import 'package:komga_native/src/session/server_store.dart';
import 'package:komga_native/src/session/session_controller.dart';
import 'package:komga_native/src/widgets/progress_sync_scope.dart';
import 'package:komga_sync_engine/komga_sync_engine.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fakes.dart';

/// 补交时机：启动时、**会话连上时**、回到前台。
void main() {
  testWidgets('启动即 flush，回到前台再 flush', (WidgetTester tester) async {
    final uploads = <ProgressTarget>[];
    final store = InMemoryProgressStore();
    await store.enqueue(
      const ProgressTarget(bookId: 'b1', page: 4, completed: false),
    );
    final sync = ProgressSyncService(
      store: store,
      upload: (ProgressTarget target) async => uploads.add(target),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[progressSyncProvider.overrideWithValue(sync)],
        child: const ProgressSyncScope(child: SizedBox.shrink()),
      ),
    );
    await tester.pumpAndSettle();

    expect(uploads.single.page, 4, reason: '启动时应把积压的进度补交');

    // 再积压一条，模拟"在别处读了一页"，然后回到前台。
    await store.enqueue(
      const ProgressTarget(bookId: 'b2', page: 2, completed: false),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(uploads.last.bookId, 'b2');
    expect(await store.pending(), isEmpty);
  });

  testWidgets('冷启动时会话还没恢复：连上之后必须再补交一次', (WidgetTester tester) async {
    final uploads = <ProgressTarget>[];
    final store = InMemoryProgressStore();
    await store.enqueue(
      const ProgressTarget(bookId: 'b1', page: 7, completed: false),
    );

    late final ProviderContainer container;
    // 与生产一致：没连服务器时上传抛 NetworkFailure，pending 必须留着。
    final sync = ProgressSyncService(
      store: store,
      upload: (ProgressTarget target) async {
        if (container.read(sessionProvider) is! SessionConnected) {
          throw const NetworkFailure();
        }
        uploads.add(target);
      },
    );

    container = ProviderContainer(
      overrides: <Override>[
        serverStoreProvider.overrideWithValue(InMemoryServerStore()),
        connectionServiceProvider.overrideWithValue(FakeConnectionService()),
        progressSyncProvider.overrideWithValue(sync),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ProgressSyncScope(child: SizedBox.shrink()),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.pump(Duration.zero);
    }

    // 还没连服务器：上传会失败，进度留着。
    expect(container.read(sessionProvider), isA<SessionDisconnected>());
    expect(uploads, isEmpty);
    expect(await store.pending(), hasLength(1));

    await container
        .read(sessionProvider.notifier)
        .connectWithApiKey(rawUrl: 'https://k.example.com', apiKey: 'K');
    await tester.pumpAndSettle();

    expect(uploads.single.page, 7, reason: '连上后应立刻补交积压的进度');
    expect(await store.pending(), isEmpty);
  });
}
