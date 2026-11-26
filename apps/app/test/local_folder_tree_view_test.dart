import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/data/local/external_roots_dao.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/widgets/local_folder_tree_sliver.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';
import 'package:yomu_platform/yomu_platform.dart';

void main() {
  testWidgets('LMB-10 LocalFolderTreeSliver 支持逐级下钻目录、面包屑回退与点书直开阅读器', (
    WidgetTester tester,
  ) async {
    final db = ProgressDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.upsertMountedRoot(
      const MountedExternalRoot(
        id: 'r_sd',
        displayName: 'SD Manga',
        uriOrBookmark: '/sd/manga',
        kind: ExternalRootKind.localDirectory,
      ),
    );
    await db.insertImportedLocalBook(
      const LocalBookImportDraft(
        bookId: 'local:b1',
        seriesTitle: 'Frieren',
        bookName: 'Vol.1',
        number: '1',
        numberSort: 1,
        storageKind: 'ext_zip',
        relativePath: '/sd/manga/Fantasy/Frieren/Vol.1.cbz',
        sizeBytes: 1024,
        pages: <ArchivePageEntry>[
          ArchivePageEntry(
            number: 1,
            entryName: '01.png',
            uncompressedSize: 10,
          ),
        ],
        mountRootId: 'r_sd',
        sourceRelativePath: 'Fantasy/Frieren/Vol.1.cbz',
      ),
      generateSeriesId: () => 'local:s1',
    );

    String? openedBookId;
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(
                body: CustomScrollView(
                  slivers: <Widget>[LocalFolderTreeSliver()],
                ),
              ),
        ),
        GoRoute(
          path: '/reader/:bookId',
          builder: (BuildContext context, GoRouterState state) {
            openedBookId = state.pathParameters['bookId'];
            return Scaffold(body: Text('opened:$openedBookId'));
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[progressDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1) 根目录展示挂载文件夹 SD Manga
    expect(find.byKey(const Key('folder-node-SD Manga')), findsOneWidget);

    // 2) 逐级下钻 SD Manga -> Fantasy -> Frieren
    await tester.tap(find.byKey(const Key('folder-node-SD Manga')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('folder-node-SD Manga/Fantasy')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('folder-node-SD Manga/Fantasy')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('folder-node-SD Manga/Fantasy/Frieren')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('folder-book-local:b1')), findsOneWidget);

    // 3) 点击书目直接打开阅读器
    await tester.tap(find.byKey(const Key('folder-book-local:b1')));
    await tester.pumpAndSettle();
    expect(openedBookId, 'local:b1');

    // 4) 返回并点击面包屑根目录一键回到顶层
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('folder-crumb-root')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('folder-node-SD Manga')), findsOneWidget);
  });
}
