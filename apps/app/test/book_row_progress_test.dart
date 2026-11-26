import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/screens/series_detail_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';
import 'support/test_source_overrides.dart';

/// FIX-06：书行要能直接看出"读到第几页"，而不是只有总页数。
void main() {
  Future<void> pumpSeries(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: testSourceOverrides(
          library: FakeLibraryRepository(series: demoShelf()),
        ),
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SeriesDetailScreen(seriesId: 's1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('在读 / 读完 / 未读三种书行文案', (WidgetTester tester) async {
    await pumpSeries(tester);

    // 假数据：第 1 本读到第 5 页共 19 页；第 2 本已读完共 20 页；第 3 本未读 21 页。
    expect(find.text('p. 5/19 · 19 pages'), findsOneWidget);
    expect(find.text('Read · 20 pages'), findsOneWidget);
    expect(find.text('21 pages'), findsOneWidget);
  });
}
