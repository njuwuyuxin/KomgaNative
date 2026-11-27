import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/download/download_queue_persistence.dart';
import 'package:yomu/src/data/download/download_service.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/download_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_domain/yomu_domain.dart';

import 'support/fake_library.dart';
import 'support/fake_reader.dart';

void main() {
  const urlA = 'https://komga-a.example.com';
  const urlB = 'https://komga-b.example.com';
  final serverA = StoredServer(
    address: ServerAddress.parse(urlA),
    apiKey: 'k-a',
    accountEmail: 'a@example.com',
  );
  final serverB = StoredServer(
    address: ServerAddress.parse(urlB),
    apiKey: 'k-b',
    accountEmail: 'b@example.com',
  );

  SourceBundle bundle(ContentSource source, DownloadService download) =>
      SourceBundle(
        source: source,
        library: FakeLibraryRepository(),
        reader: FakeReaderRepository(),
        collections: FakeLibraryRepository(),
        readStatus: FakeLibraryRepository(),
        download: download,
      );

  test('下载过程中从服务器 A 切换到本机/服务器 B：队列与运行中状态不清空，并发上限持续生效', () async {
    final db = HttpCacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dlA = _GatedDownloadService();
    final dlB = _GatedDownloadService();

    final registry = SourceRegistry(
      localBundle: bundle(
        const LocalContentSource(),
        const NoopDownloadService(),
      ),
      remoteBundles: <String, SourceBundle>{
        urlA: bundle(remoteSourceOfServer(serverA), dlA),
        urlB: bundle(remoteSourceOfServer(serverB), dlB),
      },
    );

    final container = ProviderContainer(
      overrides: <Override>[
        sourceRegistryProvider.overrideWithValue(registry),
        httpCacheDatabaseProvider.overrideWithValue(db),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        sessionProvider.overrideWith(
          () => _FixedSessionController(SessionConnected(serverA)),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(activeSourceProvider.notifier).selectSource(urlA);
    final controller = container.read(downloadsProvider.notifier);

    final b1 = const Book(
      id: 'a-1',
      seriesId: 's-a',
      name: 'A1',
      pagesCount: 5,
    ).withSource(urlA);
    final b2 = const Book(
      id: 'a-2',
      seriesId: 's-a',
      name: 'A2',
      pagesCount: 5,
    ).withSource(urlA);
    final b3 = const Book(
      id: 'b-1',
      seriesId: 's-b',
      name: 'B1',
      pagesCount: 5,
    ).withSource(urlB);

    unawaited(controller.start(b1));
    await _drain();
    unawaited(controller.start(b2));
    await _drain();

    expect(dlA.started, <String>['a-1']);
    expect(container.read(downloadsProvider)['a-1']?.isRunning, isTrue);
    expect(container.read(downloadsProvider)['a-2']?.queued, isTrue);

    // 切换到本机分组，再切换到服务器 B：队列状态必须完好保留。
    await container
        .read(activeSourceProvider.notifier)
        .selectSource(kLocalSourceKey);
    await _drain();
    expect(container.read(downloadsProvider)['a-1']?.isRunning, isTrue);
    expect(container.read(downloadsProvider)['a-2']?.queued, isTrue);

    await container.read(activeSourceProvider.notifier).selectSource(urlB);
    await _drain();
    // 在服务器 B 再排队一本，默认并发 1 仍应挡住它，直到 a-1 完成。
    unawaited(controller.start(b3));
    await _drain();
    expect(dlB.started, isEmpty, reason: '切分组后并发上限仍应生效');
    expect(container.read(downloadsProvider)['b-1']?.queued, isTrue);

    // 依次放行：a-1 -> a-2（仍走 dlA）-> b-1（走 dlB）。
    dlA.complete('a-1');
    await _drain();
    expect(dlA.started, <String>['a-1', 'a-2']);
    expect(dlB.started, isEmpty);

    dlA.complete('a-2');
    await _drain();
    expect(dlB.started, <String>['b-1']);

    dlB.complete('b-1');
    await _drain();
    expect(container.read(downloadsProvider), isEmpty);
  });

  test('cancelAll 清空全部分区的持久化队列，切回其他服务器时不会复活旧记录', () async {
    final db = HttpCacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.enqueueDownload(
      scope: urlB,
      bookId: 'stale-b',
      seriesId: 's-b',
      name: 'Stale B',
      number: '1',
      pagesCount: 8,
    );

    final dlA = _GatedDownloadService();
    final dlB = _GatedDownloadService();
    final registry = SourceRegistry(
      localBundle: bundle(
        const LocalContentSource(),
        const NoopDownloadService(),
      ),
      remoteBundles: <String, SourceBundle>{
        urlA: bundle(remoteSourceOfServer(serverA), dlA),
        urlB: bundle(remoteSourceOfServer(serverB), dlB),
      },
    );

    final container = ProviderContainer(
      overrides: <Override>[
        sourceRegistryProvider.overrideWithValue(registry),
        httpCacheDatabaseProvider.overrideWithValue(db),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        sessionProvider.overrideWith(
          () => _FixedSessionController(SessionConnected(serverA)),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(activeSourceProvider.notifier).selectSource(urlA);
    final controller = container.read(downloadsProvider.notifier);
    unawaited(
      controller.start(
        const Book(
          id: 'a-1',
          seriesId: 's-a',
          name: 'A1',
          pagesCount: 5,
        ).withSource(urlA),
      ),
    );
    await _drain();

    controller.cancelAll();
    await _drain();

    expect(
      await db.downloadQueue(),
      isEmpty,
      reason: 'cancelAll 必须清空全部分区的持久化队列',
    );

    // 切换到服务器 B：stale-b 已被清空，绝不能复活下载。
    await container.read(activeSourceProvider.notifier).selectSource(urlB);
    await _drain();
    expect(dlB.started, isEmpty);
  });

  test('DownloadQueuePersistence 写盘失败时通过错误回调暴露而非静默吞掉', () async {
    final db = HttpCacheDatabase(NativeDatabase.memory());
    await db.downloadQueue();
    await db.close();

    final errors = <Object>[];
    final store = DownloadQueuePersistence(
      db,
      onError: (Object error, StackTrace _) => errors.add(error),
    );

    store.clear();
    await _drain();

    expect(errors, isNotEmpty);
  });
}

Future<void> _drain() async {
  for (var i = 0; i < 16; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _FixedSessionController extends SessionController {
  _FixedSessionController(this._state);
  final SessionState _state;

  @override
  SessionState build() => _state;
}

final class _GatedDownloadService implements DownloadService {
  final List<String> started = <String>[];
  final List<String> cancelled = <String>[];
  final Map<String, Completer<bool>> _gates = <String, Completer<bool>>{};

  void complete(String bookId) {
    final gate = _gates[bookId];
    if (gate != null && !gate.isCompleted) gate.complete(true);
  }

  @override
  Future<bool> download(
    Book book, {
    required void Function(DownloadProgress progress) onProgress,
  }) {
    started.add(book.id);
    onProgress(DownloadProgress(done: 0, total: book.pagesCount));
    return _gates.putIfAbsent(book.id, Completer<bool>.new).future;
  }

  @override
  Future<DownloadedBook?> downloaded(String bookId) async => null;

  @override
  void cancel(String bookId) {
    cancelled.add(bookId);
    final gate = _gates[bookId];
    if (gate != null && !gate.isCompleted) gate.complete(false);
  }

  @override
  Future<void> delete(Book book) async {}
}
