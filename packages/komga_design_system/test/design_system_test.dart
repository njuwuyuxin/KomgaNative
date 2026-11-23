import 'dart:ui' show Tristate;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';

void main() {
  group('WindowSizeClass', () {
    test('断点映射与列数/导航形式', () {
      expect(WindowSizeClass.of(390), WindowSizeClass.compact);
      expect(WindowSizeClass.of(600), WindowSizeClass.medium);
      expect(WindowSizeClass.of(1023.9), WindowSizeClass.medium);
      expect(WindowSizeClass.of(1024), WindowSizeClass.expanded);

      expect(WindowSizeClass.compact.gridColumns, 2);
      expect(WindowSizeClass.medium.gridColumns, 3);
      expect(WindowSizeClass.expanded.gridColumns, 4);

      expect(WindowSizeClass.compact.useNavigationRail, isFalse);
      expect(WindowSizeClass.medium.useNavigationRail, isTrue);
    });
  });

  group('AppTheme', () {
    test('三套主题都能构建且亮度正确', () {
      expect(AppTheme.light().brightness, Brightness.light);
      expect(AppTheme.dark().brightness, Brightness.dark);
      expect(AppTheme.eink().brightness, Brightness.light);
    });

    test('墨水屏主题是"减法"：无水波纹、零阴影、纯黑白', () {
      final eink = AppTheme.eink();
      expect(eink.splashFactory, NoSplash.splashFactory);
      expect(eink.cardTheme.elevation, 0);
      expect(eink.colorScheme.surface, const Color(0xFFFFFFFF));
      expect(eink.colorScheme.onSurface, const Color(0xFF000000));
    });

    test('亮色主题带品牌色，墨水屏不带', () {
      expect(
        AppTheme.light().colorScheme.primary,
        isNot(const Color(0xFF000000)),
      );
      expect(AppTheme.eink().colorScheme.primary, const Color(0xFF000000));
    });
  });

  group('SkeletonBox', () {
    /// 取骨架块实际的填充色（骨架根本身就是一个 `DecoratedBox`）。
    Color fillOf(WidgetTester tester) {
      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(SkeletonBox),
          matching: find.byType(DecoratedBox),
        ),
      );
      return (box.decoration as ShapeDecoration).color!;
    }

    testWidgets('普通主题用容器色', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SkeletonBox()),
        ),
      );

      expect(
        fillOf(tester),
        AppTheme.light().colorScheme.surfaceContainerHighest,
      );
    });

    testWidgets('墨水屏用墨色填充：容器色会兜底成纸白，骨架会看不见', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.eink(),
          home: const Scaffold(body: SkeletonBox()),
        ),
      );

      final fill = fillOf(tester);
      // 墨水屏的 ColorScheme 没定义 surfaceContainerHighest → 取到的是纸白。
      expect(
        AppTheme.eink().colorScheme.surfaceContainerHighest,
        AppTheme.einkPaper,
      );
      expect(fill, isNot(AppTheme.einkPaper));
      expect(fill.a, greaterThan(0.05), reason: '灰阶屏上要真的看得见');
    });
  });

  group('SeriesTile', () {
    testWidgets('渲染标题与已读进度，并带无障碍标签', (tester) async {
      final handle = tester.ensureSemantics();
      const series = Series(
        id: 's1',
        libraryId: 'l1',
        title: 'Frieren',
        booksCount: 10,
        booksReadCount: 4,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SizedBox(
              width: 200,
              child: SeriesTile(
                series: series,
                semanticsLabel: 'Frieren, 4 of 10 read',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Frieren'), findsOneWidget);
      expect(find.text('4/10'), findsOneWidget);
      // 标签由调用方本地化；设计系统自己不再硬编码「已读」。
      expect(find.bySemanticsLabel('Frieren, 4 of 10 read'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      // 必须在测试体结束前释放：框架会在 tearDown 之前校验未释放的 handle。
      handle.dispose();
    });

    testWidgets('没有语义文案时只播报标题', (tester) async {
      final handle = tester.ensureSemantics();
      const series = Series(
        id: 's1',
        libraryId: 'l1',
        title: 'Frieren',
        booksCount: 10,
        booksReadCount: 4,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SizedBox(width: 200, child: SeriesTile(series: series)),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Frieren'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('点击回调可用', (tester) async {
      var tapped = false;
      const series = Series(
        id: 's1',
        libraryId: 'l1',
        title: 'X',
        booksCount: 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: SeriesTile(series: series, onTap: () => tapped = true),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(SeriesTile));
      expect(tapped, isTrue);
      // 按压反馈由 PressableScale 承担，外层不再套 InkWell（避免点击/选中时在封面与标题外露出圆角深色水波纹框）。
      expect(
        find.descendant(
          of: find.byType(SeriesTile),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });

    testWidgets('多选态：未选展示空心选择环，选中后缩放封面、呈现对勾与 selected 语义', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      const series = Series(
        id: 's1',
        libraryId: 'l1',
        title: 'Frieren',
        booksCount: 10,
        booksReadCount: 4,
      );

      Widget buildTile({required bool selecting, required bool selected}) =>
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SizedBox(
                width: 180,
                height: 280,
                child: SeriesTile(
                  series: series,
                  selecting: selecting,
                  selected: selected,
                  onTap: () {},
                ),
              ),
            ),
          );

      // 非多选态不渲染选择徽章。
      await tester.pumpWidget(buildTile(selecting: false, selected: false));
      expect(find.byKey(const Key('series-selection-badge')), findsNothing);

      // 进入多选但未选中：右上角空心选择环出现，无对勾，无障碍 selected=false。
      await tester.pumpWidget(buildTile(selecting: true, selected: false));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('series-selection-badge')), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      final unselectedScale = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale),
      );
      expect(unselectedScale.scale, 1.0);
      expect(
        tester.getSemantics(find.byType(SeriesTile)).flagsCollection.isSelected,
        Tristate.isFalse,
      );

      // 选中后：封面柔和内收、呈现对勾、无障碍 selected=true。
      await tester.pumpWidget(buildTile(selecting: true, selected: true));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      final selectedScale = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale),
      );
      expect(selectedScale.scale, lessThan(1.0));
      expect(
        tester.getSemantics(find.byType(SeriesTile)).flagsCollection.isSelected,
        Tristate.isTrue,
      );

      handle.dispose();
    });

    testWidgets('墨水屏多选态：保持 1.0 原比例不缩放且无阴影', (WidgetTester tester) async {
      const series = Series(
        id: 's1',
        libraryId: 'l1',
        title: 'Frieren',
        booksCount: 10,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.eink(),
          home: const Scaffold(
            body: SizedBox(
              width: 180,
              height: 280,
              child: SeriesTile(
                series: series,
                selecting: true,
                selected: true,
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scale.scale, 1.0);
      final badgeBox = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(SelectionBadge),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = badgeBox.decoration! as BoxDecoration;
      expect(decoration.color, AppTheme.einkInk);
      expect(decoration.boxShadow, isNull);
    });
  });

  group('SelectionBadge', () {
    testWidgets('列表模式（onCover=false）选中与未选态切换清晰', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SelectionBadge(selected: false)),
        ),
      );
      expect(find.byIcon(Icons.check_rounded), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SelectionBadge(selected: true)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });
}
