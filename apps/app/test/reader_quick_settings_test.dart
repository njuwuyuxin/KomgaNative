import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// RDR-03：顶栏收成 4 槽（返回 / 标题 / AA / ⋯），快捷设置与菜单各自可达。
void main() {
  /// 胶囊行是横向滚动的：先滚进视野再点，否则窄屏上后面几个点不到。
  Future<void> tapPill(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('AA 打开快捷设置：改背景不用进完整面板', (WidgetTester tester) async {
    final store = await pumpReader(tester, book: demoReaderBook());

    await openQuickSettings(tester);
    expect(find.byKey(const Key('quick-brightness-slider')), findsOneWidget);

    await tapPill(tester, 'quick-background-white');

    expect(store.prefs?.global.background, ReaderBackgroundChoice.white);
    // 完整设置面板没有被打开（面板里的"阅读预设"不在这层）。
    expect(find.byKey(const Key('reader-preset-save')), findsNothing);
  });

  testWidgets('快捷设置里能改方向 / 适配 / 锁定缩放', (WidgetTester tester) async {
    final store = await pumpReader(tester, book: demoReaderBook());
    await openQuickSettings(tester);

    await tapPill(tester, 'quick-direction-rightToLeft');
    await tapPill(tester, 'quick-fit-cover');
    await tapPill(tester, 'quick-lock-zoom');

    expect(store.prefs?.global.direction, ReaderDirectionChoice.rightToLeft);
    expect(store.prefs?.global.fit, ReaderFitChoice.cover);
    expect(store.prefs?.global.lockZoom, isTrue);
  });

  testWidgets('墨水屏不提供背景选项（固定白底）', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook(), forceEink: true);
    await openQuickSettings(tester);

    expect(find.byKey(const Key('quick-brightness-slider')), findsOneWidget);
    expect(find.byKey(const Key('quick-background-black')), findsNothing);
  });

  testWidgets('⋯ 菜单里五个入口都在，点"阅读设置"打开完整面板', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());

    await openReaderMenu(tester);
    expect(find.text('Contents'), findsOneWidget);
    expect(find.text('Page thumbnails'), findsOneWidget);
    expect(find.text('Reading settings'), findsOneWidget);
    expect(find.text('Share page'), findsOneWidget);
    expect(find.textContaining('Incognito'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-settings-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-preset-save')), findsOneWidget);
  });

  testWidgets('顶栏常驻按钮齐全，旧的 4 颗图标已收进菜单', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());

    expect(find.byKey(const Key('reader-close-button')), findsOneWidget);
    expect(find.byKey(const Key('reader-save-image-button')), findsOneWidget);
    expect(
      find.byKey(const Key('reader-quick-settings-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reader-more-button')), findsOneWidget);
    // 收起之后这些只在菜单里出现。
    expect(find.byKey(const Key('reader-settings-button')), findsNothing);
    expect(find.byKey(const Key('reader-pages-button')), findsNothing);
    expect(find.byKey(const Key('reader-incognito-button')), findsNothing);
  });
}
