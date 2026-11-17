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
            body: SizedBox(width: 200, child: SeriesTile(series: series)),
          ),
        ),
      );

      expect(find.text('Frieren'), findsOneWidget);
      expect(find.text('4/10'), findsOneWidget);
      expect(find.bySemanticsLabel('Frieren，4/10 已读'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      // 必须在测试体结束前释放：框架会在 tearDown 之前校验未释放的 handle。
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
    });
  });
}
