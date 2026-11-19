import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/search_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// UI-P3-9：全局搜索把系列与书两个来源合并在一个输入框下。
void main() {
  testWidgets('输入后同时查书和系列', (WidgetTester tester) async {
    final repository = FakeLibraryRepository(series: demoShelf());
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SearchScreen(),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('search-field')), 'Search');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.textContaining('Search result 0'), findsOneWidget);
    expect(find.text('Books'), findsOneWidget);
  });
}
