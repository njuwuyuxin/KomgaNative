import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/data/local/local_comic_importer.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/providers/wifi_transfer_provider.dart';
import 'package:yomu/src/widgets/wifi_transfer_sheet.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';

void main() {
  testWidgets('LMB-07 WifiTransferSheet 自动启服展示地址、可切换 PIN 并停服', (
    WidgetTester tester,
  ) async {
    final sandboxTemp = Directory.systemTemp.createTempSync('yomu_wifi_ui_');
    final db = ProgressDatabase(NativeDatabase.memory());
    final server = WifiTransferServer(
      importer: LocalComicImporter(
        db: db,
        storage: LocalComicsStorage(rootResolver: () async => sandboxTemp),
        coverEncoder: (
          Uint8List raw, {
          required ReadingDirection direction,
        }) async => raw,
      ),
      lanAddressesResolver: () async => const <String>['192.168.1.42'],
    );
    addTearDown(() async {
      await server.dispose();
      await db.close();
      if (sandboxTemp.existsSync()) sandboxTemp.deleteSync(recursive: true);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          wifiTransferServerProvider.overrideWithValue(server),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const Scaffold(body: WifiTransferSheet()),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    // 自动启动并展示局域网 URL，默认启用 6 位安全 PIN（P2-1）
    expect(find.byKey(const Key('wifi-transfer-url')), findsOneWidget);
    expect(find.textContaining('http://192.168.1.42:'), findsOneWidget);
    expect(server.isRunning, isTrue);
    expect(server.pin, isNotNull);
    expect(server.pin!.length, 6);
    expect(find.byKey(const Key('wifi-transfer-pin-refresh')), findsOneWidget);

    // 关闭 PIN 开关 -> 服务端 PIN 清除；再次打开 -> 恢复生效
    await tester.tap(find.byKey(const Key('wifi-transfer-pin-toggle')));
    await tester.pumpAndSettle();
    expect(server.pin, isNull);

    await tester.tap(find.byKey(const Key('wifi-transfer-pin-toggle')));
    await tester.pumpAndSettle();
    expect(server.pin, isNotNull);
    expect(server.pin!.length, 6);

    // 点击停止按钮 -> 释放端口
    await tester.tap(find.byKey(const Key('wifi-transfer-toggle-btn')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(server.isRunning, isFalse);
    expect(find.text('Server stopped'), findsOneWidget);
  });
}
