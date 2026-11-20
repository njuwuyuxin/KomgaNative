import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';
import 'package:komga_native/src/data/download/download_service.dart';
import 'package:komga_native/src/providers/download_providers.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/series_detail_screen.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// 假下载服务：不落盘、不联网，只验证按钮状态机。
class FakeDownloadService implements DownloadService {
  DownloadedBook? record;
  final List<String> deleted = <String>[];
  int downloads = 0;

  @override
  Future<DownloadedBook?> downloaded(String bookId) async =>
      record?.bookId == bookId ? record : null;

  @override
  Future<bool> download(
    Book book, {
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    downloads++;
    for (var i = 1; i <= 3; i++) {
      onProgress(DownloadProgress(done: i, total: 3));
    }
    record = DownloadedBook(
      scope: '',
      bookId: book.id,
      seriesId: book.seriesId,
      pageCount: 3,
      bytes: 30,
      savedAt: DateTime.utc(2026, 11, 17),
    );
    return true;
  }

  @override
  void cancel(String bookId) {}

  @override
  Future<void> delete(Book book) async {
    deleted.add(book.id);
    record = null;
  }
}

void main() {
  Future<FakeDownloadService> pumpSeries(WidgetTester tester) async {
    final download = FakeDownloadService();
    final repository = FakeLibraryRepository(
      series: demoShelf(),
      libraries: demoLibraries(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(repository),
          downloadServiceProvider.overrideWithValue(download),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const SeriesDetailScreen(seriesId: 's1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return download;
  }

  testWidgets('未下载 → 下载完成后图标变成已下载', (WidgetTester tester) async {
    final download = await pumpSeries(tester);

    expect(find.byIcon(Icons.download_outlined), findsWidgets);
    await tester.tap(find.byKey(const Key('book-download-s1-b1')));
    await tester.pumpAndSettle();

    expect(download.downloads, 1);
    expect(find.byIcon(Icons.download_done), findsOneWidget);
  });

  testWidgets('点已下载图标 → 确认删除 → 回到未下载', (WidgetTester tester) async {
    final download = await pumpSeries(tester);
    await tester.tap(find.byKey(const Key('book-download-s1-b1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book-download-s1-b1')));
    await tester.pumpAndSettle();
    expect(find.text('Remove download?'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(download.deleted, <String>['s1-b1']);
    expect(find.byIcon(Icons.download_done), findsNothing);
  });

  testWidgets('取消对话框不会删除', (WidgetTester tester) async {
    final download = await pumpSeries(tester);
    await tester.tap(find.byKey(const Key('book-download-s1-b1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book-download-s1-b1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(download.deleted, isEmpty);
    expect(find.byIcon(Icons.download_done), findsOneWidget);
  });
}
