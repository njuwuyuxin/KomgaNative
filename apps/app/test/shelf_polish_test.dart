import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/l10n/l10n.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/library_screen.dart';
import 'package:komga_native/src/screens/series_detail_screen.dart';
import 'package:komga_native/src/widgets/phase_fade.dart';
import 'package:komga_native/src/widgets/series_hero_tag.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// UI-P2-1 封面质感 / UI-P2-2 Hero / UI-P2-3 转场与大标题 / UI-P2-8 骨架与三态过渡。
void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    required ThemeData theme,
    FakeLibraryRepository? repository,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(
            repository ?? FakeLibraryRepository(series: demoShelf()),
          ),
        ],
        child: MaterialApp(
          // 每次 pump 都换一份 key：否则 `AnimatedTheme` 会在两套主题之间插值，
          // 中途 `AppTheme.isEink` 还是 false（踩过一次，微光断言会飘）。
          key: UniqueKey(),
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: theme,
          home: screen,
        ),
      ),
    );
  }

  group('P2-2 Hero', () {
    testWidgets('书架封面挂 Hero，tag 唯一且与详情页同一个来源', (WidgetTester tester) async {
      await pumpScreen(tester, const LibraryScreen(), theme: AppTheme.light());
      await tester.pumpAndSettle();

      final heroes = tester.widgetList<Hero>(find.byType(Hero)).toList();
      expect(heroes, isNotEmpty);
      expect(
        heroes.map((Hero h) => h.tag).toSet(),
        hasLength(heroes.length),
        reason: '同一页面上 Hero tag 必须唯一，否则飞不起来还会抛异常',
      );
      expect(heroes.first.tag, seriesHeroTag('s1'));
    });

    testWidgets('墨水屏不挂 Hero（灰阶屏上就是一层拖影）', (WidgetTester tester) async {
      await pumpScreen(tester, const LibraryScreen(), theme: AppTheme.eink());
      await tester.pumpAndSettle();

      expect(find.byType(Hero), findsNothing);
      expect(find.byKey(const Key('series-s1')), findsOneWidget);
    });

    testWidgets('详情页头部用同一个 tag（书架那边能接到）', (WidgetTester tester) async {
      await pumpScreen(
        tester,
        const SeriesDetailScreen(seriesId: 's1'),
        theme: AppTheme.light(),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Hero && widget.tag == seriesHeroTag('s1'),
        ),
        findsOneWidget,
      );
    });
  });

  group('P2-3 转场与大标题', () {
    test('普通主题用 iOS 式侧滑，墨水屏仍是零转场', () {
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        final builders = theme.pageTransitionsTheme.builders;
        expect(
          builders[TargetPlatform.android],
          isA<IosSlidePageTransitionsBuilder>(),
        );
        expect(
          builders[TargetPlatform.iOS],
          isA<IosSlidePageTransitionsBuilder>(),
        );
      }
      final eink = AppTheme.eink().pageTransitionsTheme.builders;
      expect(
        eink[TargetPlatform.android],
        isNot(isA<IosSlidePageTransitionsBuilder>()),
        reason: '墨水屏保持零转场',
      );
    });

    testWidgets('书架用可折叠的大标题', (WidgetTester tester) async {
      await pumpScreen(tester, const LibraryScreen(), theme: AppTheme.light());
      await tester.pumpAndSettle();

      expect(find.byType(SliverAppBar), findsOneWidget);
      // 大标题同时挂着"收起"和"展开"两份标题。
      expect(find.text('Library'), findsWidgets);
    });
  });

  group('P2-8 骨架与三态过渡', () {
    testWidgets('加载中有微光，墨水屏是静态骨架', (WidgetTester tester) async {
      final gate = Completer<void>();
      final repository = FakeLibraryRepository(series: demoShelf())
        ..gate = gate;

      await pumpScreen(
        tester,
        const LibraryScreen(),
        theme: AppTheme.light(),
        repository: repository,
      );
      await tester.pump();
      expect(find.byKey(const Key('shelf-skeleton')), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const Key('shelf-skeleton')),
          matching: find.byType(ShaderMask),
        ),
        findsOneWidget,
        reason: '普通设备的骨架带一层微光',
      );

      await pumpScreen(
        tester,
        const LibraryScreen(),
        theme: AppTheme.eink(),
        repository: FakeLibraryRepository(series: demoShelf())..gate = gate,
      );
      await tester.pump();
      expect(find.byKey(const Key('shelf-skeleton')), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const Key('shelf-skeleton')),
          matching: find.byType(ShaderMask),
        ),
        findsNothing,
        reason: '墨水屏不画微光（就是一层拖影）',
      );

      repository.gate = null;
      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('详情页头部不在三态切换里，书列表用 PhaseFade 入场淡入', (
      WidgetTester tester,
    ) async {
      // 卡住请求，才观察得到首帧的占位态（假仓库默认在微任务里就返回了）。
      final gate = Completer<void>();
      final repository = FakeLibraryRepository(series: demoShelf())
        ..detailGate = gate
        ..booksGate = gate;
      await pumpScreen(
        tester,
        const SeriesDetailScreen(seriesId: 's1'),
        theme: AppTheme.light(),
        repository: repository,
      );
      await tester.pump();

      // 首帧：头部（含封面 Hero 落点）已经在，书列表区是骨架。
      expect(find.byKey(const Key('series-title-skeleton')), findsOneWidget);
      expect(find.byKey(const Key('series-skeleton')), findsOneWidget);
      expect(find.byType(PhaseFade), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const Key('series-title-skeleton')),
          matching: find.byType(PhaseFade),
        ),
        findsNothing,
        reason: '头部不能跟着列表一起淡出，否则首次打开时 Hero 落点会中途消失',
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('series-skeleton')), findsNothing);
      expect(find.byKey(const Key('series-title-skeleton')), findsNothing);
    });
  });
}
