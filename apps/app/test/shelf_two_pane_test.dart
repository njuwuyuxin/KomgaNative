import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/screens/library_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// PLT-01：平板（≥1024）书架两栏，手机不变。
void main() {
  Future<ProviderContainer> pumpShelf(
    WidgetTester tester, {
    required Size size,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(
            FakeLibraryRepository(
              series: demoShelf(),
              libraries: demoLibraries(),
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const LibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(LibraryScreen)),
    );
  }

  testWidgets('手机（390）不显示左侧库栏', (WidgetTester tester) async {
    await pumpShelf(tester, size: const Size(390, 844));

    expect(find.byKey(const Key('shelf-side-rail')), findsNothing);
    expect(find.byKey(const Key('side-rail-all')), findsNothing);
  });

  testWidgets('平板（1024）显示左侧库栏并可切换库', (WidgetTester tester) async {
    final container = await pumpShelf(tester, size: const Size(1024, 1366));

    expect(find.byKey(const Key('shelf-side-rail')), findsOneWidget);
    expect(find.text('All series'), findsOneWidget);
    expect(find.text('Comics'), findsWidgets);
    expect(find.text('Manga'), findsWidgets);

    // 点"Manga"：书架筛选切到那个库，内容区还在。
    final manga = find.descendant(
      of: find.byKey(const Key('shelf-side-rail')),
      matching: find.text('Manga'),
    );
    await tester.tap(manga);
    await tester.pumpAndSettle();

    final state = container.read(shelfProvider);
    expect(state.libraryId, isNotNull);
    expect(find.byKey(const Key('shelf-scroll')), findsOneWidget);
  });

  testWidgets('切到 1366 宽仍是两栏', (WidgetTester tester) async {
    await pumpShelf(tester, size: const Size(1366, 1024));
    expect(find.byKey(const Key('shelf-side-rail')), findsOneWidget);
  });
}
