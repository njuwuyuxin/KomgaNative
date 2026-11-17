import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/providers/router_provider.dart';

import 'golden/golden_harness.dart';

/// 冒烟测试：真实路由 + 真实 Provider 图，确认外壳能渲染、能跳转。
void main() {
  setUpAll(loadAppFonts);

  testWidgets('启动后落在书架，且底部导航存在', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? child) {
            final GoRouter router = ref.watch(routerProvider);
            return MaterialApp.router(
              theme: withTestFont(AppTheme.light()),
              routerConfig: router,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Library'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Frieren'), findsOneWidget);
  });

  testWidgets('点击系列进入阅读器，并能翻页', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? child) {
            final GoRouter router = ref.watch(routerProvider);
            return MaterialApp.router(
              theme: withTestFont(AppTheme.light()),
              routerConfig: router,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Frieren'));
    await tester.pumpAndSettle();

    expect(find.text('1 / 24'), findsOneWidget);

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 24'), findsOneWidget);
  });
}
