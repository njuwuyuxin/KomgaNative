import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/widgets/sliding_branch_container.dart';
import 'package:material_ui/material_ui.dart';

/// 主页面切换的滑动容器：旧页滑出 / 新页滑入、RTL、墨水屏退化、分支状态保留。
void main() {
  List<Widget> pages() => <Widget>[for (var i = 0; i < 4; i++) _Page(index: i)];

  Future<void> pumpContainer(
    WidgetTester tester,
    ValueNotifier<int> index, {
    List<Widget>? children,
    ThemeData? theme,
    TextDirection direction = TextDirection.ltr,
  }) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light(),
        builder: (BuildContext context, Widget? child) => Directionality(
          textDirection: direction,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: index,
            builder: (BuildContext context, int value, _) =>
                SlidingBranchContainer(
                  currentIndex: value,
                  children: children ?? pages(),
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('切换分支：旧页左移、新页从右滑入，结束后旧页离场', (WidgetTester tester) async {
    final index = ValueNotifier<int>(0);
    addTearDown(index.dispose);
    await pumpContainer(tester, index);

    expect(find.text('page 0'), findsOneWidget);
    expect(find.text('page 1'), findsNothing);

    index.value = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final oldPage = tester.getRect(
      find.byKey(const ValueKey<String>('page-0')),
    );
    final newPage = tester.getRect(
      find.byKey(const ValueKey<String>('page-1')),
    );
    expect(oldPage.left, lessThan(0), reason: '旧页应向左滑出');
    expect(newPage.left, greaterThan(0), reason: '新页应从右侧滑入');
    expect(oldPage.right, greaterThan(0), reason: '80ms 时旧页还没完全离场');
    expect(newPage.left, lessThan(400), reason: '80ms 时新页已进入可视区');

    await tester.pumpAndSettle();
    expect(find.text('page 0'), findsNothing);
    expect(find.text('page 1'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey<String>('page-1'))).left,
      moreOrLessEquals(0, epsilon: 1),
    );
  });

  testWidgets('远距离切分支：只滑旧页与新页，不闪中间页', (WidgetTester tester) async {
    final index = ValueNotifier<int>(0);
    addTearDown(index.dispose);
    await pumpContainer(tester, index);

    index.value = 3;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('page 0'), findsOneWidget);
    expect(find.text('page 3'), findsOneWidget);
    expect(find.text('page 1'), findsNothing, reason: '中间分支不应参与这次滑动');
    expect(find.text('page 2'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('page 3'), findsOneWidget);
    expect(find.text('page 0'), findsNothing);
  });

  testWidgets('RTL：新页从左侧滑入', (WidgetTester tester) async {
    final index = ValueNotifier<int>(0);
    addTearDown(index.dispose);
    await pumpContainer(tester, index, direction: TextDirection.rtl);

    index.value = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final oldPage = tester.getRect(
      find.byKey(const ValueKey<String>('page-0')),
    );
    final newPage = tester.getRect(
      find.byKey(const ValueKey<String>('page-1')),
    );
    expect(oldPage.left, greaterThan(0), reason: 'RTL 下旧页向右滑出');
    expect(newPage.left, lessThan(0), reason: 'RTL 下新页从左侧滑入');

    await tester.pumpAndSettle();
    expect(find.text('page 0'), findsNothing);
    expect(find.text('page 1'), findsOneWidget);
  });

  testWidgets('墨水屏：直接切页，不跑弹簧', (WidgetTester tester) async {
    final index = ValueNotifier<int>(0);
    addTearDown(index.dispose);
    await pumpContainer(tester, index, theme: AppTheme.eink());

    index.value = 2;
    await tester.pump();

    expect(find.text('page 0'), findsNothing);
    expect(find.text('page 2'), findsOneWidget);
    expect(
      tester.getCenter(find.text('page 2')).dx,
      moreOrLessEquals(200, epsilon: 1),
    );
  });

  testWidgets('切走再回来：分支页面状态不丢', (WidgetTester tester) async {
    final index = ValueNotifier<int>(0);
    addTearDown(index.dispose);
    await pumpContainer(
      tester,
      index,
      children: const <Widget>[_CounterPage(index: 0), _CounterPage(index: 1)],
    );

    await tester.tap(find.byKey(const Key('counter-0')));
    await tester.pump();
    expect(find.text('count 1'), findsOneWidget);

    index.value = 1;
    await tester.pumpAndSettle();
    expect(find.text('page 1'), findsOneWidget);

    index.value = 0;
    await tester.pumpAndSettle();
    expect(find.text('page 0'), findsOneWidget);
    expect(find.text('count 1'), findsOneWidget, reason: 'Offstage 而不是销毁');
  });

  testWidgets('隐藏分支禁用 HeroMode，不劫持推入页面的 Hero 动画', (WidgetTester tester) async {
    final index = ValueNotifier<int>(1);
    addTearDown(index.dispose);
    await pumpContainer(
      tester,
      index,
      children: const <Widget>[_Page(index: 0), _Page(index: 1)],
    );

    final modes = tester
        .widgetList<HeroMode>(find.byType(HeroMode, skipOffstage: false))
        .toList();
    expect(modes, hasLength(2));
    expect(modes[0].enabled, isFalse, reason: '隐藏的分支不能参与 Hero 匹配');
    expect(modes[1].enabled, isTrue, reason: '当前激活分支保留 Hero 能力');

    index.value = 0;
    await tester.pumpAndSettle();
    final after = tester
        .widgetList<HeroMode>(find.byType(HeroMode, skipOffstage: false))
        .toList();
    expect(after[0].enabled, isTrue);
    expect(after[1].enabled, isFalse);
  });
}

class _Page extends StatelessWidget {
  const _Page({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: ValueKey<String>('page-$index'),
      color: const Color(0xFFF4F4F6),
      child: Center(child: Text('page $index')),
    );
  }
}

class _CounterPage extends StatefulWidget {
  const _CounterPage({required this.index});

  final int index;

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('page ${widget.index}'),
          TextButton(
            key: Key('counter-${widget.index}'),
            onPressed: () => setState(() => _count++),
            child: Text('count $_count'),
          ),
        ],
      ),
    );
  }
}
