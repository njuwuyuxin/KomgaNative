import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/library_screen.dart';
import 'package:komga_native/src/screens/settings_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// A11Y-01：语义标签与点击区尺寸。
///
/// 这几条是"读屏能念出来、手指点得中"的最小保证；完整走查仍需要真机 + TalkBack。
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('书架：封面项有点击语义与可读标签', (WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const LibraryScreen());

    // 每个系列封面都应该能被读屏"点"到，并念出名字。
    expect(find.bySemanticsLabel(RegExp('Frieren')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Vagabond')), findsWidgets);

    // 顶部三颗动作有 tooltip（=> 语义标签）。
    expect(find.byTooltip('Sort'), findsWidgets);
    handle.dispose();
  });

  testWidgets('书架：图标按钮点击区不小于 44', (WidgetTester tester) async {
    await pump(tester, const LibraryScreen());

    for (final tooltip in <String>['Sort', 'Filter', 'Grid']) {
      final finder = find.byTooltip(tooltip);
      if (finder.evaluate().isEmpty) continue;
      final size = tester.getSize(finder.first);
      expect(
        size.width >= 44 && size.height >= 44,
        isTrue,
        reason: '$tooltip 的点击区只有 $size，低于 44dp 会点不中',
      );
    }
  });

  testWidgets('设置页：开关项有可读标签', (WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const SettingsScreen());

    expect(find.bySemanticsLabel(RegExp('E-ink mode')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Haptic feedback')), findsWidgets);
    handle.dispose();
  });

  testWidgets('2.0× 字号下书架标题不被裁掉（能换行/滚动）', (WidgetTester tester) async {
    await pump(tester, const LibraryScreen(), textScale: 2);

    // 标题仍在，且渲染高度随字号变大——说明没有被固定高度的盒子裁掉。
    final title = find.text('Library');
    expect(title, findsOneWidget);
    expect(tester.getSize(title).height, greaterThan(30));
  });
}
