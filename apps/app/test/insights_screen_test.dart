import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/screens/insights_screen.dart';
import 'package:material_ui/material_ui.dart';

/// HIS-03：Insights 页只认注入的“今天”。
///
/// 这组用例是给一次 CI 事故补的：页面原本直接读 `DateTime.now()`，黄金图基线在
/// 本地（+08）烙、CI 跑在 UTC，跨日之后“本月”少算一个会话（252 vs 270 分钟），
/// 三张 insights 基线全部失配——而本地永远是绿的。
/// 所以这里钉死两件事：注入的 [InsightsScreen.now] 必须生效，且结果随它变化。
void main() {
  // 与黄金图同一份数据形状：21 天里每 4 天休一天，每次读 18 分钟。
  final now = DateTime(2026, 11, 25, 20, 30);
  late HttpCacheDatabase db;

  setUp(() async {
    db = HttpCacheDatabase(NativeDatabase.memory());
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
        overrides: <Override>[httpCacheDatabaseProvider.overrideWithValue(db)],
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
}
