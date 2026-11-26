import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:material_ui/material_ui.dart';

import 'golden_harness.dart';

/// 设计系统 token 的视觉基线：毛玻璃三种材质、阴影三档、形状三档、字体层级。
///
/// 不是某个页面，而是"地基长什么样"：以后改 token 时，这张图先变，
/// 能一眼看出是 token 改了还是页面改了。三套主题各一张。
void main() {
  setUpAll(loadAppFonts);

  for (final (name, size, theme) in <(String, Size, ThemeData)>[
    ('design_tokens@phone_light', GoldenSizes.phone, AppTheme.light()),
    ('design_tokens@tablet_dark', GoldenSizes.tablet, AppTheme.dark()),
    ('design_tokens@eink', GoldenSizes.eink, AppTheme.eink()),
  ]) {
    testWidgets(name, (WidgetTester tester) async {
      await pumpGoldenScreen(
        tester,
        screen: const _TokenSheet(),
        size: size,
        theme: theme,
      );
      await expectGolden(tester, name);
    });
  }
}

/// 一张"色卡"：上半是彩色条纹背景 + 三种毛玻璃（看得出模糊和底色），
/// 下半是阴影 / 形状 / 字体层级。
class _TokenSheet extends StatelessWidget {
  const _TokenSheet();

  @override
  Widget build(BuildContext context) {
    final typography = AppTypography.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              // 平板横屏高度不够：内容按手机宽度排，避免示意块被拉得过高。
              constraints: BoxConstraints(maxWidth: GoldenSizes.phone.width),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Design tokens', style: typography.largeTitle),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: 168,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        const _Stripes(),
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            children: <Widget>[
                              for (final kind
                                  in AppMaterialKind.values) ...<Widget>[
                                Expanded(
                                  child: FrostedSurface(
                                    kind: kind,
                                    shape: AppShapes.of(
                                      context,
                                      AppShapes.card,
                                    ),
                                    child: Center(
                                      child: Text(
                                        kind.name,
                                        style: typography.headline,
                                      ),
                                    ),
                                  ),
                                ),
                                if (kind != AppMaterialKind.values.last)
                                  const SizedBox(width: AppSpacing.md),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Shadows · Shapes', style: typography.title),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: <Widget>[
                      for (final (label, shadow, shape)
                          in <(String, List<BoxShadow>, ShapeBorder)>[
                            (
                              'cover',
                              AppShadows.cover,
                              AppShapes.of(context, AppShapes.cover),
                            ),
                            (
                              'card',
                              AppShadows.card,
                              AppShapes.of(context, AppShapes.card),
                            ),
                            (
                              'panel',
                              AppShadows.floating,
                              AppShapes.of(context, AppShapes.panel),
                            ),
                          ]) ...<Widget>[
                        Expanded(
                          child: AspectRatio(
                            aspectRatio: 0.7,
                            child: DecoratedBox(
                              decoration: ShapeDecoration(
                                color: scheme.surfaceContainerHigh,
                                shape: shape,
                                shadows: AppShadows.of(context, shadow),
                              ),
                              child: Center(
                                child: Text(label, style: typography.caption),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Headline', style: typography.headline),
                  Text(
                    'Body text for summaries and lists.',
                    style: typography.body,
                  ),
                  Text('Caption · 12 books', style: typography.caption),
                  Text('LABEL', style: typography.label),
                  Text('Page 10 / 128', style: typography.pageNumber),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 高对比彩色斜条纹：模糊之后能看出"糊了多少"。
class _Stripes extends StatelessWidget {
  const _Stripes();

  static const List<Color> _colors = <Color>[
    Color(0xFFE53935),
    Color(0xFFFFB300),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      // 无子组件的 ColoredBox 高度为 0：必须拉伸到整条带的高度。
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < 16; i++)
          Expanded(child: ColoredBox(color: _colors[i % _colors.length])),
      ],
    );
  }
}
