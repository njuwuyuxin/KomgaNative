import 'package:komga_design_system/src/components/glass_surface.dart';
import 'package:komga_design_system/src/shapes.dart';
import 'package:komga_design_system/src/themes.dart';
import 'package:komga_design_system/src/tokens.dart';
import 'package:komga_design_system/src/typography.dart';
import 'package:material_ui/material_ui.dart';

/// 顶部悬浮玻璃标题栏的内容行。
///
/// 形态与底部导航条同源：离屏幕边缘留白、胶囊形、内容从下面模糊穿过。
/// 一行由三段组成：
/// - [leading]：独立的玻璃圆球（返回），**不在**胶囊里；
/// - 中间胶囊：默认放 [title] + [actions]；也可以用 [bar] 整条替换
///   （搜索页放搜索框、收藏集放分段控件）；
/// - [trailing]：右侧独立的玻璃圆球（更多 / 搜索）。
///
/// 只负责排版与材质，不认路由：返回键由调用方传 `GlassIconButton`。
class GlassHeader extends StatelessWidget {
  const GlassHeader({
    this.title,
    this.leading,
    this.actions = const <Widget>[],
    this.trailing,
    this.bar,
    super.key,
  }) : assert(
         title != null || bar != null,
         'title 与 bar 至少要给一个（bar 为空时才画默认胶囊）',
       );

  /// 默认胶囊里的标题；样式由 [GlassHeader] 统一给（调用方不要自己写 style）。
  final Widget? title;

  /// 左侧独立圆球（通常是返回）。
  final Widget? leading;

  /// 胶囊右侧的动作（`GlassBarAction` / `GlassMenuButton(orb: false)`）。
  final List<Widget> actions;

  /// 右侧独立圆球。
  final Widget? trailing;

  /// 整条替换中间胶囊（必须自己带玻璃底：`GlassSurface` / `GlassSegmentedControl`）。
  final Widget? bar;

  @override
  Widget build(BuildContext context) {
    final typography = AppTypography.of(context);
    final bar =
        this.bar ??
        GlassSurface(
          shape: AppShapes.of(context, AppShapes.bar),
          child: Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.md,
              right: AppSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: typography.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: title ?? const SizedBox.shrink(),
                  ),
                ),
                for (final action in actions) ...<Widget>[
                  const SizedBox(width: AppSpacing.xxs),
                  action,
                ],
              ],
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: SizedBox(
              // 默认胶囊 / 自定义 bar 都铺满这一高度：整条标题栏高度一致，
              // 内容（搜索框、分段控件）在条内垂直居中。
              height: AppSizes.glassHeaderHeight,
              child: bar,
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// 钉在滚动内容顶部的玻璃标题栏（`CustomScrollView` 用）。
///
/// 占位高度 = 状态栏 + [AppSizes.glassHeaderClearance]；滚动后内容从玻璃下面
/// 穿过。顶部画一层从表面色到透明的渐变，保证状态栏文字在任何封面上都可读
/// （墨水屏是整块纸色：灰阶上没有"隐约可见"这回事）。
class GlassHeaderSliver extends StatelessWidget {
  const GlassHeaderSliver({required this.header, super.key});

  final GlassHeader header;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return SliverPersistentHeader(
      pinned: true,
      delegate: _GlassHeaderDelegate(
        extent: topInset + AppSizes.glassHeaderClearance,
        topInset: topInset,
        header: header,
      ),
    );
  }
}

/// 用在 `Scaffold.appBar` 上的玻璃标题栏（页面主体不是一条滚动流时用）。
///
/// 与 [GlassHeaderSliver] 共用 [GlassHeader]，形态完全一致；
/// `preferredSize` 不含状态栏，`SafeArea` 会补上（Scaffold 按实际高度布局）。
class GlassTopBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassTopBar({required this.header, super.key});

  final GlassHeader header;

  @override
  Size get preferredSize =>
      const Size.fromHeight(AppSizes.glassHeaderClearance);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: header,
      ),
    );
  }
}

class _GlassHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _GlassHeaderDelegate({
    required this.extent,
    required this.topInset,
    required this.header,
  });

  final double extent;
  final double topInset;
  final GlassHeader header;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final eink = AppTheme.isEink(theme);
    final scrimHeight = topInset + AppSpacing.md;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: scrimHeight,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    scheme.surface.withValues(alpha: eink ? 1 : 0.92),
                    scheme.surface.withValues(alpha: eink ? 1 : 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: topInset + AppSpacing.sm,
          child: header,
        ),
      ],
    );
  }

  @override
  bool shouldRebuild(_GlassHeaderDelegate oldDelegate) =>
      oldDelegate.extent != extent ||
      oldDelegate.topInset != topInset ||
      oldDelegate.header != header;
}
