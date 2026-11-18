import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';
import 'package:komga_native/src/data/download/download_service.dart';
import 'package:komga_native/src/providers/download_providers.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/library_screen.dart';
import 'package:komga_native/src/screens/reading_now_screen.dart';
import 'package:komga_native/src/screens/series_detail_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';
import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// 无障碍：读屏标签与最小点击区。
///
/// 只覆盖"Agent 最容易改坏"的三处：书架卡片、继续阅读卡片、系列书行；
/// 再加阅读器顶/底栏图标按钮（IconButton + tooltip 的既有语义）。
class _NoopDownloadService implements DownloadService {
  @override
  Future<DownloadedBook?> downloaded(String bookId) async => null;

  @override
  Future<bool> download(
    Book book, {
    required void Function(DownloadProgress progress) onProgress,
  }) async => false;

  @override
  void cancel(String bookId) {}

  @override
  Future<void> delete(Book book) async {}
}

void main() {
  Future<void> pumpApp(
    WidgetTester tester,
    Widget home,
    List<Override> overrides,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectTapTarget(WidgetTester tester, Finder finder) {
    final size = tester.getSize(finder);
    expect(size.width, greaterThanOrEqualTo(48), reason: '最小点击宽度 48');
    expect(size.height, greaterThanOrEqualTo(48), reason: '最小点击高度 48');
  }

  testWidgets('书架卡片：整卡是一个按钮，标签含系列名与已读进度', (WidgetTester tester) async {
    final handle = tester.ensureSemantics();

    await pumpApp(tester, const LibraryScreen(), <Override>[
      libraryRepositoryProvider.overrideWithValue(
        FakeLibraryRepository(series: demoShelf(), ondeck: demoOndeck()),
      ),
    ]);

    final finder = find.byKey(const Key('series-s1'));
    final node = tester.getSemantics(finder);
    expect(node.label, contains('Frieren'));
    expect(node.label, contains('5 of 12 read'));
    expect(node.flagsCollection.isButton, isTrue);
    expectTapTarget(tester, finder);
    handle.dispose();
  });

  testWidgets('继续阅读卡片：标签是"书名 + 进度"，点击区够大', (WidgetTester tester) async {
    final handle = tester.ensureSemantics();

    // 「继续阅读」从书架搬到了"正在读"首页（UI-P2-6）。
    await pumpApp(tester, const ReadingNowScreen(), <Override>[
      libraryRepositoryProvider.overrideWithValue(
        FakeLibraryRepository(series: demoShelf(), ondeck: demoOndeck()),
      ),
    ]);

    final finder = find.byKey(const Key('reading-now-continue'));
    final node = tester.getSemantics(finder);
    expect(node.label, 'Vol. 1, p. 5 / 12');
    expect(node.flagsCollection.isButton, isTrue);
    expectTapTarget(tester, finder);
    handle.dispose();
  });

  testWidgets('系列书行：可读标签，下载按钮是独立按钮且 48 点按区', (WidgetTester tester) async {
    final handle = tester.ensureSemantics();

    await pumpApp(tester, const SeriesDetailScreen(seriesId: 's1'), <Override>[
      libraryRepositoryProvider.overrideWithValue(
        FakeLibraryRepository(series: demoShelf()),
      ),
      downloadServiceProvider.overrideWithValue(_NoopDownloadService()),
    ]);

    final rowFinder = find.byKey(const Key('book-s1-b1'));
    final row = tester.getSemantics(rowFinder);
    expect(row.label, contains('#1 · Vol. 1'));
    expect(row.label, contains('19 pages'));
    expect(row.flagsCollection.isButton, isTrue);

    final downloadFinder = find.byKey(const Key('book-download-s1-b1'));
    final download = tester.getSemantics(downloadFinder);
    // IconButton + Tooltip：文案在 tooltip 属性里，读屏同样会念。
    expect(download.tooltip, 'Download for offline reading');
    expect(download.flagsCollection.isButton, isTrue);
    expectTapTarget(tester, downloadFinder);
    handle.dispose();
  });

  testWidgets('阅读器顶/底栏图标按钮：tooltip 变成语义标签，点击区 48', (WidgetTester tester) async {
    final handle = tester.ensureSemantics();

    await pumpReader(tester, book: demoReaderBook());

    for (final (String key, String label) in <(String, String)>[
      ('reader-close-button', 'Close'),
      ('reader-pages-button', 'Page thumbnails'),
      ('reader-settings-button', 'Reading settings'),
      ('reader-previous-button', 'Previous page'),
      ('reader-next-button', 'Next page'),
    ]) {
      final finder = find.byKey(Key(key));
      final node = tester.getSemantics(finder);
      expect(node.tooltip, label, reason: '$key 的读屏文案');
      expect(node.flagsCollection.isButton, isTrue, reason: '$key 应是按钮');
      expectTapTarget(tester, finder);
    }
    handle.dispose();
  });
}
