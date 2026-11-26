import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/screens/search_screen.dart';
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

  testWidgets('搜索结果的书行补上系列名（否则一屏都是 Vol. 1）', (WidgetTester tester) async {
    // 搜索来源里有一本 Frieren 的 "Vol. 1"（来自 ondeck 假数据）。
    final repository = FakeLibraryRepository(
      series: demoShelf(),
      ondeck: demoOndeck(),
    );
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

    await tester.enterText(find.byKey(const Key('search-field')), 'Vol');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Frieren · Vol. 1'), findsOneWidget);
  });

  testWidgets('进入搜索页自动聚焦，点击空白处失焦收起键盘', (WidgetTester tester) async {
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
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue, reason: '进入搜索页应自动聚焦弹出键盘');

    // 点击页面下方空白处：应失焦收起键盘。
    final screenSize = tester.getSize(find.byType(SearchScreen));
    await tester.tapAt(Offset(screenSize.width / 2, screenSize.height - 80));
    await tester.pump();
    expect(editable.focusNode.hasFocus, isFalse, reason: '点击屏幕空白处应退出键盘');

    // 再次点输入框重新聚焦。
    await tester.tap(find.byKey(const Key('search-field')));
    await tester.pump();
    expect(editable.focusNode.hasFocus, isTrue);
  });
}
