import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/data/cache/drift_http_cache.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/widgets/offline_banner.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late HttpCacheDatabase db;
  late DriftHttpCache cache;

  setUp(() {
    db = HttpCacheDatabase(NativeDatabase.memory());
    cache = DriftHttpCache(db);
  });

  tearDown(() async {
    cache.dispose();
    await db.close();
  });

  Future<void> pumpBanner(WidgetTester tester, {VoidCallback? onRetry}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[httpCacheProvider.overrideWithValue(cache)],
        child: MaterialApp(
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

  testWidgets('传输层报告离线后出现提示，恢复后自动消失', (WidgetTester tester) async {
    await pumpBanner(tester);

    cache.reportOffline('https://komga.example.com');
    await tester.pump();
    expect(find.byKey(const Key('offline-banner')), findsOneWidget);
    expect(find.textContaining('Offline'), findsOneWidget);

    cache.reportOnline('https://komga.example.com');
    await tester.pump();
    expect(find.byKey(const Key('offline-banner')), findsNothing);
  });

  testWidgets('点 Retry 回调一次', (WidgetTester tester) async {
    var retries = 0;
    await pumpBanner(tester, onRetry: () => retries++);

    cache.reportOffline('https://komga.example.com');
    await tester.pump();
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(retries, 1);
  });
}
