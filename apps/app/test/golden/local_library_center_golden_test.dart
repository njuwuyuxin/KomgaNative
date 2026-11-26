import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/data/cache/http_cache_tables.dart';
import 'package:yomu/src/providers/local_import_provider.dart';
import 'package:yomu/src/providers/local_library_center_provider.dart';
import 'package:yomu/src/screens/local_library_center_screen.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_platform/yomu_platform.dart';

import 'golden_harness.dart';

Future<void> _pumpCenter(
  WidgetTester tester, {
  required Size logicalSize,
  required ThemeData theme,
}) async {
  tester.view.physicalSize = logicalSize * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  final sampleRoots = <MountedRootSummary>[
    MountedRootSummary(
      id: 'root_sd',
      displayName: 'SD Card · Comics',
      uriOrBookmark: 'content://tree/comics',
      kind: ExternalRootKind.androidSaf,
      enabled: true,
      hasNomedia: true,
      booksCount: 28,
      createdAt: DateTime.utc(2026, 11, 20),
    ),
    MountedRootSummary(
      id: 'root_files',
      displayName: 'Files · Yomu',
      uriOrBookmark: '/Documents',
      kind: ExternalRootKind.iosBookmark,
      enabled: true,
      hasNomedia: true,
      booksCount: 12,
      createdAt: DateTime.utc(2026, 11, 22),
    ),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        mountedRootsProvider.overrideWithValue(
          AsyncValue<List<MountedRootSummary>>.data(sampleRoots),
        ),
        localStorageUsageProvider.overrideWithValue(
          const AsyncValue<CacheUsage>.data(
            CacheUsage(bytes: 428 * 1024 * 1024, entries: 40),
          ),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme,
        home: const LocalLibraryCenterScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('local_library_center@phone_light', (WidgetTester tester) async {
    await _pumpCenter(
      tester,
      logicalSize: GoldenSizes.phone,
      theme: AppTheme.light(),
    );
    await expectGolden(tester, 'local_library_center@phone_light');
  });

  testWidgets('local_library_center@tablet_dark', (WidgetTester tester) async {
    await _pumpCenter(
      tester,
      logicalSize: GoldenSizes.tablet,
      theme: AppTheme.dark(),
    );
    await expectGolden(tester, 'local_library_center@tablet_dark');
  });

  testWidgets('local_library_center@eink', (WidgetTester tester) async {
    await _pumpCenter(
      tester,
      logicalSize: GoldenSizes.eink,
      theme: AppTheme.eink(),
    );
    await expectGolden(tester, 'local_library_center@eink');
  });
}
