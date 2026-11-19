import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:material_ui/material_ui.dart';

/// 在给定主题 / "减少动态效果"下取一次 [AppMotion.of] 等上下文 token。
Future<T> readFromContext<T>(
  WidgetTester tester, {
  required ThemeData theme,
  required T Function(BuildContext context) read,
  bool disableAnimations = false,
}) async {
  late T value;
  await tester.pumpWidget(
    MaterialApp(
      // 每次都是新 key：避免 AnimatedTheme 在两次 pump 之间做主题插值。
      key: UniqueKey(),
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Builder(
          builder: (BuildContext context) {
            value = read(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return value;
}

void main() {
  group('AppTheme.isEink', () {
    test('只有墨水屏主题被识别', () {
      expect(AppTheme.isEink(AppTheme.eink()), isTrue);
      expect(AppTheme.isEink(AppTheme.light()), isFalse);
      expect(AppTheme.isEink(AppTheme.dark()), isFalse);
    });

    test('换字体后仍能识别（黄金图会给主题套测试字体）', () {
      final eink = AppTheme.eink();
      final withFont = eink.copyWith(
        textTheme: eink.textTheme.apply(fontFamily: 'Roboto'),
      );
      expect(AppTheme.isEink(withFont), isTrue);
    });
  });

  group('AppMotion', () {
    test('普通设备：时长递增、曲线非线性、动画开启', () {
      final motion = AppMotion.resolve(eink: false);
      expect(motion.enabled, isTrue);
      expect(motion.quick, lessThan(motion.standard));
      expect(motion.standard, lessThan(motion.emphasized));
      expect(motion.standardCurve, isNot(Curves.linear));
      // 弹簧必须是稳定的（阻尼 > 0），否则会无限振荡。
      expect(motion.snappy.damping, greaterThan(0));
      expect(motion.gentle.damping, greaterThan(0));
    });

    test('墨水屏与"减少动态效果"都退化成零时长、线性、关闭', () {
      for (final motion in <AppMotion>[
        AppMotion.resolve(eink: true),
        AppMotion.resolve(eink: false, disableAnimations: true),
        AppMotion.resolve(eink: true, disableAnimations: true),
      ]) {
        expect(motion.enabled, isFalse);
        expect(motion.quick, Duration.zero);
        expect(motion.standard, Duration.zero);
        expect(motion.emphasized, Duration.zero);
        expect(motion.standardCurve, Curves.linear);
        expect(motion.emphasizedCurve, Curves.linear);
        expect(motion.exitCurve, Curves.linear);
      }
    });

    test('强调曲线两端固定在 0 和 1', () {
      final curve = AppMotion.standardMotion.emphasizedCurve;
      expect(curve.transform(0), 0);
      expect(curve.transform(1), 1);
    });

    testWidgets('of(context)：按主题与 MediaQuery 退化', (tester) async {
      expect(
        (await readFromContext(
          tester,
          theme: AppTheme.light(),
          read: AppMotion.of,
        )).enabled,
        isTrue,
      );
      expect(
        (await readFromContext(
          tester,
          theme: AppTheme.eink(),
          read: AppMotion.of,
        )).enabled,
        isFalse,
      );
      expect(
        (await readFromContext(
          tester,
          theme: AppTheme.dark(),
          disableAnimations: true,
          read: AppMotion.of,
        )).enabled,
        isFalse,
      );
    });
  });

  group('AppMaterial', () {
    test('墨水屏：不模糊、不透明纸色、带墨色描边', () {
      for (final kind in AppMaterialKind.values) {
        for (final dark in <bool>[true, false]) {
          final material = AppMaterial.resolve(kind, eink: true, dark: dark);
          expect(material.blurs, isFalse);
          expect(material.filter, isNull);
          expect(material.tint, AppTheme.einkPaper);
          expect(material.tint.a, 1);
          expect(material.border?.color, AppTheme.einkInk);
        }
      }
    });

    test('普通主题：都模糊、底色半透明；玻璃档额外带反光与高光描边', () {
      for (final kind in AppMaterialKind.values) {
        for (final dark in <bool>[true, false]) {
          final material = AppMaterial.resolve(kind, eink: false, dark: dark);
          expect(material.blurs, isTrue, reason: '$kind dark=$dark');
          expect(material.filter, isNotNull);
          expect(material.tint.a, inExclusiveRange(0, 1));
          if (kind == AppMaterialKind.bar) {
            // 悬浮导航条是"液态玻璃"：只有它带斜向反光与白描边。
            expect(material.highlight, isNotNull, reason: 'bar 要有反光');
            expect(material.border, isNotNull, reason: 'bar 要有高光边');
          } else {
            expect(material.highlight, isNull, reason: '$kind 不该有反光');
            expect(material.border, isNull, reason: '$kind 不该有描边');
          }
        }
      }
    });

    test('阅读器 chrome 不跟随深浅色（永远压在画面上）', () {
      expect(
        AppMaterial.resolve(
          AppMaterialKind.chrome,
          eink: false,
          dark: true,
        ).tint,
        AppMaterial.resolve(
          AppMaterialKind.chrome,
          eink: false,
          dark: false,
        ).tint,
      );
    });
  });

  group('AppShadows', () {
    test('墨水屏没有阴影，普通主题原样返回', () {
      expect(AppShadows.resolve(AppShadows.cover, eink: true), isEmpty);
      expect(
        AppShadows.resolve(AppShadows.cover, eink: false),
        AppShadows.cover,
      );
    });

    test('阴影都是低透明度（"浮在纸上"，不是硬投影）', () {
      for (final shadow in <BoxShadow>[
        ...AppShadows.cover,
        ...AppShadows.card,
        ...AppShadows.floating,
      ]) {
        expect(shadow.color.a, lessThan(0.25));
        expect(shadow.offset.dy, greaterThanOrEqualTo(0));
      }
    });
  });

  group('AppShapes', () {
    test('普通主题用连续曲率，墨水屏是直角', () {
      expect(AppShapes.cover(eink: false), isA<ContinuousRectangleBorder>());
      expect(AppShapes.card(eink: false), isA<ContinuousRectangleBorder>());
      expect(AppShapes.panel(eink: false), isA<ContinuousRectangleBorder>());

      for (final shape in <ShapeBorder>[
        AppShapes.cover(eink: true),
        AppShapes.card(eink: true),
        AppShapes.panel(eink: true),
      ]) {
        expect(shape, isA<RoundedRectangleBorder>());
        expect(
          (shape as RoundedRectangleBorder).borderRadius,
          BorderRadius.zero,
        );
      }
    });

    test('圆角大小按层级递增', () {
      double radiusOf(ShapeBorder shape) =>
          ((shape as ContinuousRectangleBorder).borderRadius as BorderRadius)
              .topLeft
              .x;
      expect(
        radiusOf(AppShapes.cover(eink: false)),
        lessThan(radiusOf(AppShapes.card(eink: false))),
      );
      expect(
        radiusOf(AppShapes.card(eink: false)),
        lessThan(radiusOf(AppShapes.panel(eink: false))),
      );
    });

    test('底部面板只圆顶部两个角；墨水屏改为描边', () {
      final sheet = AppShapes.sheet(eink: false) as RoundedRectangleBorder;
      final radius = sheet.borderRadius as BorderRadius;
      expect(radius.topLeft.x, AppRadii.xl);
      expect(radius.bottomLeft, Radius.zero);
      final eink = AppShapes.sheet(eink: true) as RoundedRectangleBorder;
      expect(eink.side.color, AppTheme.einkInk);
    });

    test('悬浮导航条是胶囊；墨水屏是直角', () {
      expect(AppShapes.bar(eink: false), isA<StadiumBorder>());
      final eink = AppShapes.bar(eink: true) as RoundedRectangleBorder;
      expect(eink.borderRadius, BorderRadius.zero);
    });
  });

  group('AppTypography', () {
    testWidgets('页码用等宽数字；大标题最粗且字距收紧、层级字号递减', (tester) async {
      // 字号来自 Theme.of 本地化后的 TextTheme（ThemeData 原始 textTheme 没有字号）。
      final typography = await readFromContext(
        tester,
        theme: AppTheme.light(),
        read: AppTypography.of,
      );
      expect(
        typography.pageNumber.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(typography.largeTitle.fontWeight, FontWeight.w700);
      expect(typography.largeTitle.letterSpacing, lessThan(0));
      expect(
        typography.largeTitle.fontSize!,
        greaterThan(typography.title.fontSize!),
      );
      expect(
        typography.title.fontSize!,
        greaterThan(typography.caption.fontSize!),
      );
    });

    test('主题被裁剪时不崩溃', () {
      final typography = AppTypography.fromTextTheme(const TextTheme());
      expect(typography.body.height, 1.4);
      expect(typography.label.fontWeight, FontWeight.w600);
    });
  });

  group('AppHaptics', () {
    testWidgets('三种语义映射到系统反馈；关掉后不发', (tester) async {
      final calls = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            calls.add(call.arguments as String?);
          }
          return null;
        },
      );
      addTearDown(() {
        AppHaptics.enabled = true;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await AppHaptics.selection();
      await AppHaptics.light();
      await AppHaptics.success();
      expect(calls, <String>[
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.mediumImpact',
      ]);

      AppHaptics.enabled = false;
      await AppHaptics.light();
      expect(calls, hasLength(3));
    });
  });

  group('PressableScale', () {
    Future<void> pump(WidgetTester tester, ThemeData theme) =>
        tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Center(
              child: PressableScale(
                child: GestureDetector(
                  onTap: () {},
                  child: const ColoredBox(
                    color: Color(0xFF000000),
                    child: SizedBox(
                      key: Key('target'),
                      width: 100,
                      height: 100,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    double scaleOf(WidgetTester tester) {
      final transform = tester.widget<Transform>(
        find
            .ancestor(
              of: find.byKey(const Key('target')),
              matching: find.byType(Transform),
            )
            .first,
      );
      // Transform.scale 是 diag(s, s, 1)：取 x 轴分量（getMaxScaleOnAxis 会拿到 z 的 1）。
      return transform.transform.storage[0];
    }

    testWidgets('按下缩小、松开弹回 1', (tester) async {
      await pump(tester, AppTheme.light());
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('target'))),
      );
      await tester.pumpAndSettle();
      expect(
        scaleOf(tester),
        moreOrLessEquals(PressableScale.defaultPressedScale, epsilon: 0.002),
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(scaleOf(tester), moreOrLessEquals(1, epsilon: 0.002));
    });

    testWidgets('不抢子组件的点击', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Center(
            child: PressableScale(
              child: GestureDetector(
                onTap: () => taps++,
                child: const ColoredBox(
                  color: Color(0xFF000000),
                  child: SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(GestureDetector));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('墨水屏：完全透传，不包 Transform', (tester) async {
      await pump(tester, AppTheme.eink());
      expect(
        find.ancestor(
          of: find.byKey(const Key('target')),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
    });
  });

  group('FrostedSurface', () {
    testWidgets('普通主题有 BackdropFilter，墨水屏没有', (tester) async {
      Widget surface(ThemeData theme) => MaterialApp(
        key: UniqueKey(),
        theme: theme,
        home: const FrostedSurface(child: SizedBox(width: 10, height: 10)),
      );
      await tester.pumpWidget(surface(AppTheme.dark()));
      expect(find.byType(BackdropFilter), findsOneWidget);

      await tester.pumpWidget(surface(AppTheme.eink()));
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });

  group('GlassSurface', () {
    Widget surface(ThemeData theme) => MaterialApp(
      key: UniqueKey(),
      theme: theme,
      home: const Center(
        child: GlassSurface(child: SizedBox(width: 120, height: 48)),
      ),
    );

    /// 玻璃反光层：一个带 gradient 的 ShapeDecoration。
    bool hasGloss(WidgetTester tester) => tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .any(
          (DecoratedBox box) =>
              box.decoration is ShapeDecoration &&
              (box.decoration as ShapeDecoration).gradient != null,
        );

    testWidgets('彩色主题：背景模糊 + 反光层 + 阴影', (tester) async {
      await tester.pumpWidget(surface(AppTheme.light()));
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(hasGloss(tester), isTrue);
      final shadowed = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((DecoratedBox box) => box.decoration)
          .whereType<ShapeDecoration>()
          .where((ShapeDecoration d) => d.shadows?.isNotEmpty ?? false)
          .toList();
      expect(shadowed, isNotEmpty, reason: '浮层要有阴影');
      expect(shadowed.first.shape, isA<StadiumBorder>());
    });

    testWidgets('墨水屏：不模糊、不反光、无阴影，改纸底墨边', (tester) async {
      await tester.pumpWidget(surface(AppTheme.eink()));
      expect(find.byType(BackdropFilter), findsNothing);
      expect(hasGloss(tester), isFalse);
      final boxes = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where((DecoratedBox box) => box.decoration is ShapeDecoration)
          .map((DecoratedBox box) => box.decoration as ShapeDecoration);
      expect(
        boxes.any((ShapeDecoration d) => d.color == AppTheme.einkPaper),
        isTrue,
      );
      expect(
        boxes.any((ShapeDecoration d) => d.shadows?.isNotEmpty ?? false),
        isFalse,
      );
    });
  });
}
