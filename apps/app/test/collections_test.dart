import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/screens/collections_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// UI-P3-8：收藏集 / 阅读列表入口。
void main() {
  Widget buildHost(FakeLibraryRepository repository, {ThemeData? theme}) {
    return ProviderScope(
      overrides: <Override>[
        libraryRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CollectionsScreen(),
      ),
    );
  }

  testWidgets('两个 tab 都能列出服务端策展内容', (WidgetTester tester) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(buildHost(repository));
    await tester.pumpAndSettle();

    expect(find.text('Reading order'), findsOneWidget);
    expect(find.text('Empty shelf'), findsOneWidget);

    await tester.tap(find.text('Read lists'));
    await tester.pumpAndSettle();
    expect(find.text('Weekend reading'), findsOneWidget);
  });

  testWidgets('左右滑动切换页面时，顶部 tab 胶囊实时同步跟随且结束后不二次补播动画', (
    WidgetTester tester,
  ) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(buildHost(repository));
    await tester.pumpAndSettle();

    final pillFinder = find.byKey(const Key('sliding-selection-pill'));
    final startPill = tester.getRect(pillFinder);
    final viewRect = tester.getRect(find.byType(TabBarView));

    // 按住并向左拖动 40% 屏宽（未松手）：先越过 touch slop 启动拖拽，再拖动 40%。
    final gesture = await tester.startGesture(viewRect.center);
    await gesture.moveBy(const Offset(-24, 0));
    await gesture.moveBy(Offset(-viewRect.width * 0.4, 0));
    await tester.pump();

    final midDragPill = tester.getRect(pillFinder);
    expect(
      midDragPill.left,
      greaterThan(startPill.left + startPill.width * 0.25),
      reason: '页面拖到 40% 时顶部胶囊必须实时跟进',
    );
    expect(midDragPill.left, lessThan(startPill.left + startPill.width * 0.75));

    // 拖过一半（65%）后松手：完成切换，胶囊直接落到右侧槽位。
    await gesture.moveBy(Offset(-viewRect.width * 0.25, 0));
    await tester.pump();
    final pastHalfPill = tester.getRect(pillFinder);
    expect(pastHalfPill.left, greaterThan(midDragPill.left));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Weekend reading'), findsOneWidget);
    final endPill = tester.getRect(pillFinder);
    expect(endPill.left, greaterThan(startPill.left + startPill.width * 0.9));

    // 拖动不足一半后松手（取消切换）：胶囊应随页面平滑弹回右侧槽位。
    final cancelGesture = await tester.startGesture(viewRect.center);
    await cancelGesture.moveBy(const Offset(24, 0));
    await cancelGesture.moveBy(Offset(viewRect.width * 0.25, 0));
    await tester.pump();
    expect(tester.getRect(pillFinder).left, lessThan(endPill.left - 1));

    await cancelGesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.getRect(pillFinder).left,
      moreOrLessEquals(endPill.left, epsilon: 0.5),
    );
  });

  testWidgets('点击顶部 tab 时页面与胶囊同步过渡；切到墨水屏后瞬切且无异常', (WidgetTester tester) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(buildHost(repository));
    await tester.pumpAndSettle();

    final pillFinder = find.byKey(const Key('sliding-selection-pill'));
    final startPill = tester.getRect(pillFinder);

    await tester.tap(find.text('Read lists'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final midwayPill = tester.getRect(pillFinder);
    expect(midwayPill.left, greaterThan(startPill.left + 1));
    expect(midwayPill.left, lessThan(startPill.left + startPill.width - 1));

    await tester.pumpAndSettle();
    final endPill = tester.getRect(pillFinder);
    expect(endPill.left, greaterThan(startPill.left + startPill.width * 0.9));

    // 运行时切到墨水屏：保留当前页签，点回 Collections 时瞬切。
    await tester.pumpWidget(buildHost(repository, theme: AppTheme.eink()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Weekend reading'), findsOneWidget);

    await tester.tap(find.text('Collections'));
    await tester.pump();
    expect(
      tester.getRect(pillFinder).left,
      moreOrLessEquals(startPill.left, epsilon: 0.5),
    );
    expect(find.text('Reading order'), findsOneWidget);
  });
}
