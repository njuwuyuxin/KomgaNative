import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/screens/library_screen.dart';
import 'package:yomu/src/widgets/series_shelf_tile.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// UI-P2-7：书架视图选项（网格 / 列表、封面三档）。
void main() {
  Future<FakeLibraryRepository> pumpShelf(WidgetTester tester) async {
    final library = FakeLibraryRepository(series: demoShelf());
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(library),
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
    return library;
  }

  testWidgets('默认是网格；切到列表后换成行视图，且不重新请求', (WidgetTester tester) async {
    final repository = await pumpShelf(tester);
    expect(find.byType(SeriesShelfTile), findsWidgets);
    expect(find.byType(SeriesShelfRow), findsNothing);
    final callsBefore = repository.seriesCalls.length;

    await tester.tap(find.byKey(const Key('shelf-view-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-view-list')));
    await tester.pumpAndSettle();

    expect(find.byType(SeriesShelfRow), findsWidgets);
    expect(find.byType(SeriesShelfTile), findsNothing);
    expect(
      repository.seriesCalls.length,
      callsBefore,
      reason: '换视图只是换排版，不该再发一次列表请求',
    );
    expect(find.text('Frieren'), findsOneWidget);
  });

  testWidgets('封面档位：小档位一行放更多列（单元格更窄）', (WidgetTester tester) async {
    await pumpShelf(tester);
    final medium = tester.getRect(find.byKey(const Key('series-s1'))).width;

    await tester.tap(find.byKey(const Key('shelf-view-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-cover-small')));
    await tester.pumpAndSettle();

    final small = tester.getRect(find.byKey(const Key('series-s1'))).width;
    expect(small, lessThan(medium), reason: '小档位在同样宽度里塞更多列，单元格因此更窄');
  });

  testWidgets('列表视图也能长按出菜单', (WidgetTester tester) async {
    await pumpShelf(tester);
    await tester.tap(find.byKey(const Key('shelf-view-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-view-list')));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('series-s1')));
    await tester.pumpAndSettle();
    expect(find.text('Mark all read'), findsOneWidget);
  });

  testWidgets('列表视图里点一行仍然进系列页', (WidgetTester tester) async {
    await pumpShelf(tester);
    await tester.tap(find.byKey(const Key('shelf-view-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-view-list')));
    await tester.pumpAndSettle();

    expect(find.byType(SeriesShelfRow), findsWidgets);
    // 行本身是可点的：语义层把整行当一个按钮，读屏念"标题 + 进度"。
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics &&
            (widget.properties.label ?? '').contains('Frieren'),
      ),
      findsOneWidget,
    );
  });
}
