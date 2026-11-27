import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/screens/insights_screen.dart';
import 'package:yomu_design_system/yomu_design_system.dart';

import 'support/fake_library.dart';
import 'support/test_source_overrides.dart';

/// HIS-03：Insights 页的时钟注入、标题样式、热力图对齐与点击查书交互。
void main() {
  // 与黄金图同一份数据形状：21 天里每 4 天休一天，每次读 18 分钟。
  final now = DateTime(2026, 11, 25, 20, 30);
  late ProgressDatabase db;

  setUp(() async {
    db = ProgressDatabase(NativeDatabase.memory());
    for (var i = 0; i < 21; i++) {
      if (i % 4 == 0) continue;
      final startedAt = now.subtract(Duration(days: i, hours: 3));
      await db.addReadingSession(
        bookId: 'b${i % 3}',
        seriesId: 's1',
        bookName: 'Vol. ${i % 3}',
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(minutes: 18)),
        durationMs: 18 * 60 * 1000,
        startPage: 1,
        endPage: 20,
        completed: false,
      );
    }
  });
  tearDown(() => db.close());

  Future<void> pumpInsights(WidgetTester tester, DateTime today) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          progressDatabaseProvider.overrideWithValue(db),
          ...testSourceOverrides(
            library: FakeLibraryRepository(series: demoShelf()),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: InsightsScreen(now: today),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String valueOf(WidgetTester tester, String key) {
    final text = tester.widget<Text>(find.byKey(Key(key)));
    return text.data ?? '';
  }

  testWidgets('注入的“今天”决定周/月汇总与连续天数', (WidgetTester tester) async {
    await pumpInsights(tester, now);

    // 15 个会话 × 18 分钟，全部落在 11 月。
    expect(valueOf(tester, 'insights-month-minutes'), '270 min');
    // 最近 7 天（11-19..11-25）里有 5 个会话。
    expect(valueOf(tester, 'insights-week-minutes'), '90 min');
    // 今天（11-25）没读，从昨天往回数 11-24/23/22 三天。
    expect(valueOf(tester, 'insights-current-streak'), '3 days');
    expect(valueOf(tester, 'insights-longest-streak'), '3 days');
  });

  testWidgets('换一个“今天”，数字跟着变（没有偷读系统时钟）', (WidgetTester tester) async {
    // 三个月后：同一份历史全在本月/本周之外。
    // 如果页面忽略 now 去读系统时钟，这里会是 270/90，用例立刻红。
    await pumpInsights(tester, DateTime(2027, 3, 1));

    expect(valueOf(tester, 'insights-month-minutes'), '0 min');
    expect(valueOf(tester, 'insights-week-minutes'), '0 min');
    expect(valueOf(tester, 'insights-current-streak'), '0 days');
  });

  testWidgets('标题栏不加粗，热力图与上方统计卡片左右对齐', (WidgetTester tester) async {
    await pumpInsights(tester, now);

    final title = tester.widget<Text>(find.byKey(const Key('insights-title')));
    expect(title.style?.fontWeight, FontWeight.w400);

    final groups = find.byType(AppListGroup);
    expect(groups, findsNWidgets(4));
    final firstRect = tester.getRect(groups.first);
    final heatmapGroupRect = tester.getRect(groups.last);
    expect(heatmapGroupRect.left, firstRect.left);
    expect(heatmapGroupRect.right, firstRect.right);

    final heatmapRect = tester.getRect(
      find.byKey(const Key('insights-heatmap')),
    );
    expect(
      heatmapRect.width,
      closeTo(heatmapGroupRect.width - AppSpacing.md * 4, 1),
    );
  });

  testWidgets('默认显示最近读过书的那天，点击热力图方块切换日期与书籍列表', (WidgetTester tester) async {
    await pumpInsights(tester, now);

    // 11-25（i=0）未读，最近读过书的是 11-24（i=1，Vol. 1）。
    await tester.scrollUntilVisible(
      find.byKey(const Key('insights-selected-date')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(valueOf(tester, 'insights-selected-date'), '2026-11-24');
    expect(valueOf(tester, 'insights-selected-minutes'), '18 min');
    expect(find.byKey(const Key('insights-day-book-b1')), findsOneWidget);
    expect(find.text('Vol. 1'), findsOneWidget);

    // 点击 11-23（i=2，Vol. 2）：切换显示当天日期与书籍。
    final nov23 = find.byKey(const Key('heatmap-day-2026-11-23'));
    await tester.ensureVisible(nov23);
    await tester.tap(nov23);
    await tester.pumpAndSettle();

    expect(valueOf(tester, 'insights-selected-date'), '2026-11-23');
    expect(find.byKey(const Key('insights-day-book-b2')), findsOneWidget);
    expect(find.text('Vol. 2'), findsOneWidget);

    // 点击空白日期 11-25（i=0，未读）：显示当天日期与空态提示。
    final nov25 = find.byKey(const Key('heatmap-day-2026-11-25'));
    await tester.ensureVisible(nov25);
    await tester.tap(nov25);
    await tester.pumpAndSettle();

    expect(valueOf(tester, 'insights-selected-date'), '2026-11-25');
    expect(find.byKey(const Key('insights-selected-empty')), findsOneWidget);
    expect(find.byKey(const Key('insights-selected-minutes')), findsNothing);
  });
}
