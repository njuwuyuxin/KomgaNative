import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:material_ui/material_ui.dart';

/// 玻璃控件（标题栏 / 圆球 / 胶囊按钮 / 分段 / 搜索框 / 分组卡）的行为测试。
///
/// 这里钉的是"页面改版后仍必须成立"的契约：点击派发、读屏标签、墨水屏退化、
/// 标题栏滚动后仍钉在顶部、搜索框清除键。视觉由黄金图负责。
void main() {
  Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
    theme: theme ?? AppTheme.light(),
    home: Scaffold(body: Center(child: child)),
  );

  group('GlassIconButton', () {
    testWidgets('点按派发、读屏标签就是 tooltip 文案、点击区不小于 48', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        host(
          GlassIconButton(
            icon: Icons.search,
            label: 'Search',
            onPressed: () => taps++,
          ),
        ),
      );

      expect(find.bySemanticsLabel('Search'), findsOneWidget);
      expect(find.byTooltip('Search'), findsOneWidget);
      final size = tester.getSize(find.byType(GlassIconButton));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));

      await tester.tap(find.byType(GlassIconButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
      handle.dispose();
    });

    testWidgets('墨水屏：不建 BackdropFilter（纸底墨边由材质退化）', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          GlassIconButton(icon: Icons.close, label: 'Close', onPressed: () {}),
          theme: AppTheme.eink(),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });

  group('GlassPillButton', () {
    testWidgets('点按派发；busy 时不派发也不可点', (WidgetTester tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(GlassPillButton(label: 'Continue', onPressed: () => taps++)),
      );
      await tester.tap(find.byType(GlassPillButton));
      await tester.pumpAndSettle();
      expect(taps, 1);

      await tester.pumpWidget(
        host(
          GlassPillButton(
            label: 'Continue',
            busy: true,
            onPressed: () => taps++,
          ),
        ),
      );
      // 转圈是无限动画：这里不能 pumpAndSettle。
      await tester.pump();
      await tester.tap(find.byType(GlassPillButton));
      await tester.pump();
      expect(taps, 1, reason: '提交中再点不应重复提交');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // 让转圈的 ticker 在测试结束前停掉。
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('GlassSegmentedControl', () {
    testWidgets('点未选中的段才派发；选中段有 selected 语义', (WidgetTester tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        host(
          GlassSegmentedControl<String>(
            segments: const <GlassSegment<String>>[
              GlassSegment<String>(
                value: 'a',
                label: 'Alpha',
                key: Key('seg-a'),
              ),
              GlassSegment<String>(
                value: 'b',
                label: 'Beta',
                key: Key('seg-b'),
              ),
            ],
            selected: 'a',
            onSelected: calls.add,
          ),
        ),
      );

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty, reason: '重复点当前段不该回调');

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      expect(calls, <String>['b']);

      final handle = tester.ensureSemantics();
      final semantics = tester.getSemantics(find.byKey(const Key('seg-a')));
      expect(semantics.flagsCollection.isSelected, Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('横向滚动模式：选项多也不溢出', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 240,
            child: GlassSegmentedControl<int>(
              scrollable: true,
              segments: <GlassSegment<int>>[
                for (var i = 0; i < 8; i++)
                  GlassSegment<int>(value: i, label: 'Library $i'),
              ],
              selected: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Library 7'), findsOneWidget);
    });
  });

  group('GlassSearchField', () {
    testWidgets('输入触发 onChanged；有内容才出现清除键，点它清空', (WidgetTester tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final changes = <String>[];
      await tester.pumpWidget(
        host(
          GlassSearchField(
            controller: controller,
            hintText: 'Search series',
            clearLabel: 'Clear',
            onChanged: changes.add,
          ),
        ),
      );

      expect(find.byIcon(Icons.cancel), findsNothing);
      await tester.enterText(find.byType(TextField), 'vaga');
      await tester.pump();
      expect(controller.text, 'vaga');
      expect(changes.last, 'vaga');
      expect(find.byIcon(Icons.cancel), findsOneWidget);
      expect(find.byTooltip('Clear'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.cancel));
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(changes.last, isEmpty);
      expect(find.byIcon(Icons.cancel), findsNothing);
    });
  });

  group('GlassHeader', () {
    testWidgets('默认条里有标题与动作；高度等于标题栏 token', (WidgetTester tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          GlassHeader(
            title: const Text('Library'),
            actions: <Widget>[
              GlassBarAction(
                icon: Icons.sort,
                label: 'Sort',
                onPressed: () => taps++,
              ),
            ],
            trailing: GlassIconButton(
              icon: Icons.collections_bookmark_outlined,
              label: 'Collections',
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.text('Library'), findsOneWidget);
      expect(tester.getSize(find.text('Library')).height, greaterThan(0));
      expect(
        tester.getSize(find.byType(GlassSurface).first).height,
        AppSizes.glassHeaderHeight,
      );
      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('自定义 bar 整条替换（搜索页 / 收藏集分段）', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          GlassHeader(
            bar: GlassSegmentedControl<int>(
              segments: const <GlassSegment<int>>[
                GlassSegment<int>(value: 0, label: 'Collections'),
                GlassSegment<int>(value: 1, label: 'Read lists'),
              ],
              selected: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('Collections'), findsOneWidget);
      expect(find.text('Read lists'), findsOneWidget);
    });

    testWidgets('sliver 版钉在顶上：滚动后标题仍在可点区域', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: CustomScrollView(
              slivers: <Widget>[
                const GlassHeaderSliver(
                  header: GlassHeader(title: Text('Library')),
                ),
                SliverList.builder(
                  itemCount: 30,
                  itemBuilder: (BuildContext context, int index) =>
                      SizedBox(height: 80, child: Text('row $index')),
                ),
              ],
            ),
          ),
        ),
      );

      final before = tester.getTopLeft(find.text('Library'));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Library'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Library')).dy, before.dy);
      expect(find.text('row 0'), findsNothing);
    });

    testWidgets('appBar 版：preferredSize 不含状态栏，由 SafeArea 补', (
      WidgetTester tester,
    ) async {
      expect(
        const GlassTopBar(header: GlassHeader(title: Text('Detail')))
            .preferredSize
            .height,
        AppSizes.glassHeaderClearance,
      );
    });
  });

  group('AppListGroup', () {
    testWidgets('墨水屏：纸底 + 墨框，没有阴影', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.eink(),
          home: const Scaffold(
            body: AppListGroup(
              header: 'Appearance',
              children: <Widget>[
                ListTile(title: Text('Theme')),
                ListTile(title: Text('Language')),
              ],
            ),
          ),
        ),
      );

      final group = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(AppListGroup),
              matching: find.byType(Material),
            )
            .first,
      );
      final shape = group.shape as RoundedRectangleBorder;
      expect(shape.side.color, AppTheme.einkInk);
      expect(group.color, AppTheme.einkPaper);
      expect(group.elevation, 0);
    });
  });
}
