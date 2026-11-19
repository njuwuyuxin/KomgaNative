import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';
import 'package:komga_native/src/data/download/download_service.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/providers/download_providers.dart';

/// UI-P3-13：下载队列一次只跑一本，后面的显示"排队中"。
void main() {
  test('两本书依次下载：第二本先排队，第一本完成后才开始', () async {
    final service = _QueueDownloadService();
    final container = ProviderContainer(
      overrides: <Override>[
        downloadServiceProvider.overrideWithValue(service),
        httpCacheDatabaseProvider.overrideWithValue(
          HttpCacheDatabase(NativeDatabase.memory()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(downloadsProvider.notifier);

    final first = controller.start(_book('b1'));
    await _drain();
    final second = controller.start(_book('b2'));
    await _drain();

    expect(service.order, <String>['b1']);
    expect(container.read(downloadsProvider)['b1']?.isRunning, isTrue);
    expect(container.read(downloadsProvider)['b2']?.queued, isTrue);

    service.first.complete(true);
    await first;
    await second;

    expect(service.order, <String>['b1', 'b2']);
    expect(container.read(downloadsProvider), isEmpty);
  });
}

Future<void> _drain() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Book _book(String id) => Book(id: id, seriesId: 's1', name: id, pagesCount: 3);

class _QueueDownloadService implements DownloadService {
  final List<String> order = <String>[];
  final Completer<bool> first = Completer<bool>();

  @override
  Future<bool> download(
    Book book, {
    required void Function(DownloadProgress progress) onProgress,
  }) {
    order.add(book.id);
    onProgress(const DownloadProgress(done: 0, total: 1));
    if (order.length == 1) return first.future;
    onProgress(const DownloadProgress(done: 1, total: 1));
    return Future<bool>.value(true);
  }

  @override
  Future<DownloadedBook?> downloaded(String bookId) async => null;

  @override
  void cancel(String bookId) {}

  @override
  Future<void> delete(Book book) async {}
}
