import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/collections_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// UI-P3-8：收藏集 / 阅读列表入口。
void main() {
  testWidgets('两个 tab 都能列出服务端策展内容', (WidgetTester tester) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CollectionsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reading order'), findsOneWidget);
    expect(find.text('Empty shelf'), findsOneWidget);

    await tester.tap(find.text('Read lists'));
    await tester.pumpAndSettle();
    expect(find.text('Weekend reading'), findsOneWidget);
  });
}
