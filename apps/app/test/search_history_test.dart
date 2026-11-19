import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:komga_native/src/data/app_settings.dart';
import 'package:komga_native/src/data/settings_store.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_native/src/screens/search_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// SCH-01：搜索历史（最多 10 条、去重、重启保持）与空态。
void main() {
  group('AppSettings 搜索历史', () {
    test('记一条：去重并移到最前，最多 10 条', () {
      var settings = const AppSettings();
      for (var i = 1; i <= 12; i++) {
        settings = settings.withSearchTerm('term$i');
      }
      expect(settings.searchHistory.length, kSearchHistoryLimit);
      expect(settings.searchHistory.first, 'term12');
      expect(settings.searchHistory, isNot(contains('term1')));

      settings = settings.withSearchTerm('term5');
      expect(settings.searchHistory.first, 'term5');
      expect(
        settings.searchHistory.where((String t) => t == 'term5').length,
        1,
        reason: '重复搜索只保留一条',
      );
    });

    test('空白词不记；单删 / 全清', () {
      var settings = const AppSettings().withSearchTerm('a');
      expect(settings.withSearchTerm('   ').searchHistory, <String>['a']);

      settings = settings.withSearchTerm('b');
      expect(settings.withoutSearchTerm('a').searchHistory, <String>['b']);
      expect(settings.clearSearchHistory().searchHistory, isEmpty);
    });

    test('存档往返 + 坏条目容错', () {
      final settings = const AppSettings()
          .withSearchTerm('one')
          .withSearchTerm('two');
      expect(AppSettings.fromJson(settings.toJson()).searchHistory, <String>[
        'two',
        'one',
      ]);

      final broken = AppSettings.fromJson(const <String, Object?>{
        'searchHistory': <Object?>['ok', '', 'ok', 42, null, '  spaced  '],
      });
      expect(broken.searchHistory, <String>['ok', 'spaced']);
    });
  });

  group('搜索页空态', () {
    late InMemorySettingsStore store;

    Future<void> pumpSearch(WidgetTester tester) async {
      store = InMemorySettingsStore(
        const AppSettings()
            .withSearchTerm('frieren')
            .withSearchTerm('vagabond'),
      );
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            libraryRepositoryProvider.overrideWithValue(
              FakeLibraryRepository(series: demoShelf()),
            ),
            settingsStoreProvider.overrideWithValue(store),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: const SearchScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('空态列出最近搜索，点一条回填并搜索', (WidgetTester tester) async {
      await pumpSearch(tester);

      // ignore: avoid_print
      print(
        'store=${store.settings.searchHistory} '
        'guidance=${find.byKey(const Key('search-guidance')).evaluate().length} '
        'hint=${find.byKey(const Key('search-history')).evaluate().length}',
      );
      expect(find.byKey(const Key('search-history')), findsOneWidget);
      // 最新的在前。
      expect(find.byKey(const Key('search-history-vagabond')), findsOneWidget);
      expect(find.byKey(const Key('search-history-frieren')), findsOneWidget);

      await tester.tap(find.byKey(const Key('search-history-frieren')));
      await tester.pumpAndSettle();

      // 回填到输入框，且进入搜索结果态（历史列表消失）。
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'frieren',
      );
      expect(find.byKey(const Key('search-history')), findsNothing);
    });

    testWidgets('删单条与清空都会落盘', (WidgetTester tester) async {
      await pumpSearch(tester);

      await tester.tap(find.byKey(const Key('search-history-remove-frieren')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('search-history-frieren')), findsNothing);
      expect(store.settings.searchHistory, <String>['vagabond']);

      await tester.tap(find.byKey(const Key('search-history-clear')));
      await tester.pumpAndSettle();
      expect(store.settings.searchHistory, isEmpty);
      // 清空后回落到引导态，而不是一片空白。
      expect(find.byKey(const Key('search-guidance')), findsOneWidget);
    });
  });
}
