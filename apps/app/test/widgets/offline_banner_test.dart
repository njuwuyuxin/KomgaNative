import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_api/komga_api.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/data/cache/drift_http_cache.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/widgets/offline_banner.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const scope = 'https://komga.example.com';
  late HttpCacheDatabase db;
  late DateTime fakeNow;
  late DriftHttpCache cache;

  setUp(() {
    db = HttpCacheDatabase(NativeDatabase.memory());
    fakeNow = DateTime.utc(2026, 11, 25, 12);
    cache = DriftHttpCache(db, now: () => fakeNow);
  });

  tearDown(() async {
    cache.dispose();
    await db.close();
  });

  Future<void> pumpBanner(
    WidgetTester tester, {
    VoidCallback? onRetry,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[httpCacheProvider.overrideWithValue(cache)],
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: OfflineBanner(onRetry: onRetry)),
        ),
      ),
    );
  }

  testWidgets('在线时完全不占位', (WidgetTester tester) async {
    await pumpBanner(tester);

    expect(find.byKey(const Key('offline-banner')), findsNothing);
  });

  testWidgets('单次装饰性缩略图失败不显示；连续核心失败后显示，驻留期满后恢复自动消失', (
    WidgetTester tester,
  ) async {
    await pumpBanner(tester);

    cache.reportOffline(scope, priority: RequestPriority.decorative);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('offline-banner')), findsNothing);

    cache
      ..reportOffline(scope)
      ..reportOffline(scope);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('offline-banner')), findsOneWidget);
    expect(find.textContaining('Offline'), findsOneWidget);

    fakeNow = fakeNow.add(const Duration(seconds: 3));
    cache.reportOnline(scope);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('offline-banner')), findsNothing);
  });

  testWidgets('点 Retry 回调一次且成功时绕过最小驻留立刻消失', (WidgetTester tester) async {
    var retries = 0;
    await pumpBanner(tester, onRetry: () => retries++);

    cache
      ..reportOffline(scope)
      ..reportOffline(scope);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retries, 1);

    // 紧接着核心请求成功（未满 2.5s 驻留），应立刻撤掉提示。
    cache.reportOnline(scope);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('offline-banner')), findsNothing);
  });

  testWidgets('OfflineOverlay 悬浮覆盖，出现与消失不改变页面主体布局位置', (
    WidgetTester tester,
  ) async {
    const contentKey = Key('page-content');
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[httpCacheProvider.overrideWithValue(cache)],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                ListView(
                  children: const <Widget>[
                    SizedBox(
                      key: contentKey,
                      height: 120,
                      child: Text('Shelf content'),
                    ),
                  ],
                ),
                const OfflineOverlay(),
              ],
            ),
          ),
        ),
      ),
    );

    final beforeRect = tester.getRect(find.byKey(contentKey));

    cache
      ..reportOffline(scope)
      ..reportOffline(scope);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('offline-banner')), findsOneWidget);
    expect(tester.getRect(find.byKey(contentKey)), beforeRect);
  });

  testWidgets('墨水屏下瞬切显示与隐藏，不依赖过渡动画', (WidgetTester tester) async {
    await pumpBanner(tester, theme: AppTheme.eink());

    cache
      ..reportOffline(scope)
      ..reportOffline(scope);
    await tester.pump();
    expect(find.byKey(const Key('offline-banner')), findsOneWidget);

    fakeNow = fakeNow.add(const Duration(seconds: 3));
    cache.reportOnline(scope);
    await tester.pump();
    expect(find.byKey(const Key('offline-banner')), findsNothing);
  });
}
