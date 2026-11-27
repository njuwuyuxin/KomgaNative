import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/progress/bookmarks_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/widgets/history_list.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// P1-1：空 sourceKey 迁移到 kLocalSourceKey，且历史跳转始终显式携带 ?source=。
void main() {
  test('ProgressDatabase v6 -> v7 迁移把四张表的空 scope 补齐为 kLocalSourceKey', () async {
    final tempDir = await Directory.systemTemp.createTemp('yomu_p1_1_v7_');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbFile = File('${tempDir.path}/progress_v6.sqlite');

    // 先手工构造一个 schema v6 数据库，并写入带空 scope 与主键冲突的混合行。
    final raw = sql.sqlite3.open(dbFile.path);
    try {
      raw.execute('PRAGMA user_version = 6;');
      raw.execute('''
        CREATE TABLE local_progress (
          scope TEXT NOT NULL DEFAULT '',
          book_id TEXT NOT NULL,
          page INTEGER NOT NULL,
          completed INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL,
          server_last_modified INTEGER NULL,
          pending_seq INTEGER NULL,
          PRIMARY KEY (scope, book_id)
        );
      ''');
      raw.execute('''
        CREATE TABLE reading_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          scope TEXT NOT NULL DEFAULT '',
          book_id TEXT NOT NULL,
          series_id TEXT NOT NULL,
          book_name TEXT NOT NULL DEFAULT '',
          started_at INTEGER NOT NULL,
          ended_at INTEGER NOT NULL,
          duration_ms INTEGER NOT NULL,
          start_page INTEGER NOT NULL DEFAULT 1,
          end_page INTEGER NOT NULL DEFAULT 1,
          completed INTEGER NOT NULL DEFAULT 0
        );
      ''');
      raw.execute('''
        CREATE TABLE pinned_series_rows (
          server_id TEXT NOT NULL,
          series_id TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          PRIMARY KEY (server_id, series_id)
        );
      ''');
      raw.execute('''
        CREATE TABLE page_bookmarks_rows (
          scope TEXT NOT NULL DEFAULT '',
          book_id TEXT NOT NULL,
          page INTEGER NOT NULL,
          note TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL,
          PRIMARY KEY (scope, book_id, page)
        );
      ''');

      // local_progress:
      // - b1 仅空串；
      // - b2 空串更旧、local 更新（冲突时应保留 local）；
      // - b3 空串更新、local 更旧（冲突时应以 updated_at 保留更新的空串记录，N6）。
      raw.execute(
        "INSERT INTO local_progress VALUES ('', 'b1', 12, 0, 1000, NULL, NULL);",
      );
      raw.execute(
        "INSERT INTO local_progress VALUES ('', 'b2', 3, 0, 1000, NULL, NULL);",
      );
      raw.execute(
        "INSERT INTO local_progress VALUES ('$kLocalSourceKey', 'b2', 9, 0, 2000, NULL, NULL);",
      );
      raw.execute(
        "INSERT INTO local_progress VALUES ('', 'b3', 18, 1, 3000, NULL, 99);",
      );
      raw.execute(
        "INSERT INTO local_progress VALUES ('$kLocalSourceKey', 'b3', 5, 0, 2000, NULL, NULL);",
      );
      raw.execute(
        'INSERT INTO reading_sessions '
        '(scope, book_id, series_id, book_name, started_at, ended_at, duration_ms, start_page, end_page, completed) '
        "VALUES ('', 'b1', 's1', 'Vol 1', 1000, 61000, 60000, 1, 12, 0);",
      );
      raw.execute("INSERT INTO pinned_series_rows VALUES ('', 's1', 1000);");
      raw.execute(
        "INSERT INTO page_bookmarks_rows VALUES ('', 'b1', 5, 'note', 1000);",
      );
    } finally {
      raw.close();
    }

    final db = ProgressDatabase(NativeDatabase(dbFile));
    addTearDown(db.close);

    // 触发 migration。
    final b1 = await db.record('b1', scope: kLocalSourceKey);
    expect(b1, isNotNull);
    expect(b1!.page, 12);

    final b2 = await db.record('b2', scope: kLocalSourceKey);
    expect(b2, isNotNull);
    expect(b2!.page, 9);

    final b3 = await db.record('b3', scope: kLocalSourceKey);
    expect(b3, isNotNull);
    expect(b3!.page, 18);
    expect(b3.completed, isTrue);
    expect(b3.pendingSeq, 99);

    final sessions = await db.readingSessionList(scope: kLocalSourceKey);
    expect(sessions, hasLength(1));
    expect(sessions.single.scope, kLocalSourceKey);

    expect(await db.pinnedSeries(''), isEmpty);
    expect(await db.pinnedSeries(kLocalSourceKey), <String>['s1']);

    final bookmarks = await db.pageBookmarks(
      scope: kLocalSourceKey,
      bookId: 'b1',
    );
    expect(bookmarks, hasLength(1));
    expect(bookmarks.single.scope, kLocalSourceKey);
  });

  testWidgets('历史列表点击空 scope 遗留记录也会显式带 ?source=local://device（P1-1）', (
    WidgetTester tester,
  ) async {
    String? navigatedUri;
    final start = DateTime.utc(2026, 11, 20, 10);
    final session = ReadingSession(
      id: 7,
      scope: '',
      bookId: 'local-book-1',
      seriesId: 'local-series-1',
      bookName: 'Legacy Local Vol. 1',
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 2)),
      durationMs: 120000,
      startPage: 1,
      endPage: 15,
      completed: false,
    );

    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) => Scaffold(
            body: CustomScrollView(
              slivers: <Widget>[
                HistoryList(
                  rows: <ReadingSession>[session],
                  existingLocalIds: const <String>{'local-book-1'},
                  onDelete: (_) {},
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/reader/:bookId',
          builder: (BuildContext context, GoRouterState state) {
            navigatedUri = state.uri.toString();
            return const SizedBox.shrink();
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookCoverProvider.overrideWith(
            (Ref ref, CoverQuery key) async => null,
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('history-row-7')));
    await tester.pumpAndSettle();

    expect(
      navigatedUri,
      '/reader/local-book-1?source=${Uri.encodeComponent(kLocalSourceKey)}',
    );
  });
}
