import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:komga_native/src/data/settings_store.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_native/src/screens/library_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// LIB-04：筛选菜单里的"保存当前筛选"与已保存组合的应用。
void main() {
  late FakeLibraryRepository repository;

  Future<ProviderContainer> pumpShelf(WidgetTester tester) async {
    repository = FakeLibraryRepository(series: demoShelf());
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(repository),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
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

  Future<void> openFilterMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('shelf-filter-menu')));
    await tester.pumpAndSettle();
  }

  testWidgets('没有筛选时"保存当前筛选"是禁用状态', (WidgetTester tester) async {
    await pumpShelf(tester);
    await openFilterMenu(tester);

    final save = find.byKey(const Key('shelf-filter-save'));
    expect(save, findsOneWidget);
    expect(
      tester.widget<GlassMenuItemButton>(save).enabled,
      isFalse,
      reason: '"什么都不筛"没有保存价值',
    );
  });

  testWidgets('选中筛选后保存 → 出现在菜单里 → 可应用', (WidgetTester tester) async {
    final container = await pumpShelf(tester);
    final controller = container.read(shelfProvider.notifier);
    controller.setReadStatus(SeriesReadStatus.unread);
    await tester.pumpAndSettle();

    await openFilterMenu(tester);
    final save = find.byKey(const Key('shelf-filter-save'));
    expect(tester.widget<GlassMenuItemButton>(save).enabled, isTrue);

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shelf-preset-name-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('shelf-preset-name-field')),
      '未读',
    );
    await tester.tap(find.byKey(const Key('shelf-preset-save-confirm')));
    await tester.pumpAndSettle();

    final preset = container.read(shelfProvider).presets.single;
    expect(preset.name, '未读');
    expect(preset.readStatus, SeriesReadStatus.unread);

    // 清掉筛选，再从菜单里应用回来。
    controller.setReadStatus(null);
    await tester.pumpAndSettle();
    expect(container.read(shelfProvider).readStatus, isNull);

    await openFilterMenu(tester);
    await tester.tap(find.byKey(Key('shelf-preset-${preset.id}')));
    await tester.pumpAndSettle();

    expect(container.read(shelfProvider).readStatus, SeriesReadStatus.unread);
  });

  testWidgets('删除组合', (WidgetTester tester) async {
    final container = await pumpShelf(tester);
    final controller = container.read(shelfProvider.notifier);
    controller.setSort(SeriesSort.titleDesc);
    await tester.pumpAndSettle();
    controller.savePreset('Z-A');
    await tester.pumpAndSettle();
    final preset = container.read(shelfProvider).presets.single;

    await openFilterMenu(tester);
    await tester.tap(find.byKey(Key('shelf-preset-delete-${preset.id}')));
    await tester.pumpAndSettle();

    expect(container.read(shelfProvider).presets, isEmpty);
  });
}
