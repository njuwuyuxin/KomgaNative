import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu/src/widgets/reader_toc_sheet.dart';
import 'package:yomu/src/widgets/reader_top_bar.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';
import 'package:yomu_reader/yomu_reader.dart';

import 'support/fake_library.dart';
import 'support/test_source_overrides.dart';

void main() {
  testWidgets('LMB-05: 顶栏添加页级书签 + 目录面板切换本卷章节/书签与系列各卷 + 跳转与删除书签', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final db = ProgressDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.insertImportedLocalBook(
      const LocalBookImportDraft(
        bookId: 'local:b1',
        seriesTitle: 'Test Series',
        bookName: 'Vol 1',
        storageKind: 'epub',
        relativePath: 'books/b1/archive.epub',
        sizeBytes: 2048,
        pages: <ArchivePageEntry>[
          ArchivePageEntry(
            number: 1,
            entryName: '01.png',
            uncompressedSize: 10,
          ),
          ArchivePageEntry(
            number: 2,
            entryName: '02.png',
            uncompressedSize: 10,
          ),
          ArchivePageEntry(
            number: 3,
            entryName: '03.png',
            uncompressedSize: 10,
          ),
          ArchivePageEntry(
            number: 4,
            entryName: '04.png',
            uncompressedSize: 10,
          ),
          ArchivePageEntry(
            number: 5,
            entryName: '05.png',
            uncompressedSize: 10,
          ),
        ],
        chapters: <ArchiveChapter>[
          ArchiveChapter(title: 'Chapter 1', startPage: 1),
          ArchiveChapter(title: 'Chapter 2', startPage: 4),
        ],
      ),
      generateSeriesId: () => 'local:s1',
    );

    final jumped = <int>[];
    final repo = FakeLibraryRepository(series: demoShelf());

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          progressDatabaseProvider.overrideWithValue(db),
          ...testSourceOverrides(
            library: repo,
            source: const LocalContentSource(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ReaderTopBar(
              bookId: 'local:b1',
              sourceKey: kLocalSourceKey,
              seriesId: 's1',
              title: 'Vol 1',
              pageLabel: '2 / 5',
              palette: ReaderPalette.dark,
              mode: ReadingMode.paged,
              page: 2,
              total: 5,
              onJump: jumped.add,
              onToggleIncognito: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1) 通过顶栏 ⋯ 菜单为第 2 页添加书签
    await tester.tap(find.byKey(const Key('reader-more-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-bookmark-button')));
    await tester.pumpAndSettle();
    expect(find.text('Bookmarked page 2'), findsOneWidget);

    // 2) 打开目录面板，应默认展示「本卷章节与书签」分段，同时有分段切换条
    await tester.tap(find.byKey(const Key('reader-more-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-toc-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader-toc-segment')), findsOneWidget);
    expect(find.byKey(const Key('reader-toc-bookmark-2')), findsOneWidget);
    expect(find.byKey(const Key('reader-toc-chapter-0')), findsOneWidget);
    expect(find.byKey(const Key('reader-toc-chapter-1')), findsOneWidget);

    // 3) 切到「系列各卷」分段能看到系列分卷列表
    await tester.tap(find.byKey(const Key('reader-toc-tab-volumes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-toc-list')), findsOneWidget);

    // 4) 切回本卷并点击 Chapter 2 -> 关闭面板并触发 onJump(4)
    await tester.tap(find.byKey(const Key('reader-toc-tab-book')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-toc-chapter-1')));
    await tester.pumpAndSettle();
    expect(jumped, <int>[4]);

    // 5) 重新打开目录，点击书签删除图标 -> 第 2 页书签被移除
    final ctx = tester.element(find.byType(ReaderTopBar));
    unawaited(
      showReaderTocSheet(
        ctx,
        seriesId: 's1',
        currentBookId: 'local:b1',
        sourceKey: kLocalSourceKey,
        palette: ReaderPalette.dark,
        direction: ReadingDirection.rightToLeft,
        currentPage: 2,
        onJump: jumped.add,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-toc-bookmark-delete-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-toc-bookmark-2')), findsNothing);
  });
}
