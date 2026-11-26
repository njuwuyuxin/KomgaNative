import 'dart:async';

import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读器的骨架：阅读区铺满整屏，顶栏与底栏以浮层压在画面之上，外加亮度遮罩。
///
/// 两条硬约束（UI-P1-1）：
/// 1. **阅读区固定按全屏布局**：chrome 显隐、系统栏显隐都不会改变它的尺寸。
///    早先 chrome 占的是 `Column` 的行，一隐藏画面就变大，"点一下中间图会跳"。
/// 2. **chrome 与系统栏同步**：显隐状态由外部传给 [ReaderFrame]，系统栏由
///    `ReaderSystemUi` 跟着切；这里只负责浮层的动画。
///
/// 墨水屏 / 系统"减少动态效果"时退化为瞬切（`AppMotion` 已处理），
/// 材质退化成纸色不透明 + 描边（`ReaderPalette.chromeMaterial` 已处理）。
class ReaderFrame extends StatelessWidget {
  const ReaderFrame({
    required this.palette,
    required this.chromeVisible,
    required this.topBar,
    required this.content,
    required this.bottomBar,
    required this.dimOpacity,
    this.floatingAction,
    super.key,
  });

  final ReaderPalette palette;
  final bool chromeVisible;
  final Widget topBar;
  final Widget content;

  /// 底栏整块（书末卡片 + 缩略图滑条 + 翻页控件），见 `ReaderBottomChrome`。
  final Widget bottomBar;

  /// 亮度遮罩不透明度（0 = 不遮）。
  final double dimOpacity;

  /// 仅在需要时渲染的轻浮操作（如宽页切分态下的「合页查看 / 恢复切分」微胶囊）。
  final Widget? floatingAction;

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context);
    final material = palette.chromeMaterial;
    // 用 `viewPadding` 而不是 `padding`：系统栏隐藏时 `padding` 会变成 0，
    // chrome 的位置就会跟着跳一下；`viewPadding` 与系统栏是否可见无关。
    final insets = MediaQuery.viewPaddingOf(context);

    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 底色单独一层、单独做交叉渐变：动态背景翻页换色时只有这一层在动，
          // 页图和 chrome 不跟着每帧重建（UI-P1-5 / UI-P3-7）。
          AnimatedContainer(
            key: const Key('reader-background'),
            duration: motion.emphasized,
            curve: motion.standardCurve,
            decoration: BoxDecoration(
              color: palette.gradient == null ? palette.background : null,
              gradient: palette.gradient == null
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: palette.gradient!,
                    ),
            ),
          ),
          // 阅读区铺满整屏：不做 SafeArea，画面可以伸到刘海 / 圆角下面。
          content,
          if (floatingAction != null)
            Positioned(
              right: insets.right + AppSpacing.md,
              bottom: chromeVisible ? null : insets.bottom + AppSpacing.md,
              top: chromeVisible
                  ? insets.top + AppSizes.glassHeaderClearance + AppSpacing.xs
                  : null,
              child: floatingAction!,
            ),
          Align(
            alignment: Alignment.topCenter,
            child: _ChromeSlot(
              visible: chromeVisible,
              motion: motion,
              slideFrom: const Offset(0, -AppSpacing.sm),
              child: FrostedSurface(
                material: material,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    insets.left,
                    insets.top,
                    insets.right,
                    0,
                  ),
                  child: topBar,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _ChromeSlot(
              visible: chromeVisible,
              motion: motion,
              slideFrom: const Offset(0, AppSpacing.sm),
              child: FrostedSurface(
                material: material,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    insets.left,
                    0,
                    insets.right,
                    insets.bottom,
                  ),
                  child: bottomBar,
                ),
              ),
            ),
          ),
          // 亮度遮罩：盖住整块阅读区（含 chrome），但不吃点击——
          // 调暗是为了少看光线，不是为了挡住操作。
          if (dimOpacity > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  key: const Key('reader-dimmer'),
                  color: Colors.black.withValues(alpha: dimOpacity),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 宽页自动切分态下的「合页查看 / 恢复切分」微胶囊（LMB-01）。
class ReaderTempMergePill extends StatelessWidget {
  const ReaderTempMergePill({
    required this.merged,
    required this.label,
    required this.palette,
    required this.onPressed,
    super.key,
  });

  final bool merged;
  final String label;
  final ReaderPalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GlassPillButton(
      key: const Key('reader-temp-merge-pill'),
      icon: merged
          ? Icons.vertical_split_outlined
          : Icons.auto_stories_outlined,
      label: label,
      onPressed: onPressed,
    );
  }
}

/// chrome 的显隐容器：淡入淡出 + 一段很小的位移；动画结束后用 `Offstage` 把 chrome
/// 从画面和点击树里摘掉（**不销毁**——缩略图滑条的滚动位置要留着）。
///
/// 不用 `AnimatedSwitcher`：过渡期它会同时挂着两份 chrome，两边都去加载缩略图。
class _ChromeSlot extends StatefulWidget {
  const _ChromeSlot({
    required this.visible,
    required this.motion,
    required this.slideFrom,
    required this.child,
  });

  final bool visible;
  final AppMotion motion;

  /// 隐藏时的位移（按像素算，不随 chrome 尺寸缩放）。
  final Offset slideFrom;

  final Widget child;

  @override
  State<_ChromeSlot> createState() => _ChromeSlotState();
}

class _ChromeSlotState extends State<_ChromeSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.motion.standard,
    value: widget.visible ? 1 : 0,
  );

  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: widget.motion.standardCurve,
    reverseCurve: widget.motion.exitCurve,
  );

  @override
  void didUpdateWidget(_ChromeSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motion.standard != widget.motion.standard) {
      _controller.duration = widget.motion.standard;
    }
    if (oldWidget.visible == widget.visible) return;
    if (!widget.motion.enabled) {
      // 墨水屏 / 减少动态效果：直接到位，不跑动画。
      _controller.value = widget.visible ? 1 : 0;
      return;
    }
    unawaited(widget.visible ? _controller.forward() : _controller.reverse());
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      // child 不参与逐帧重建：缩略图滑条不会因为 chrome 在淡入而重排 60 次。
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final t = _curve.value;
        return Offstage(
          // 动画播完才摘掉：`find.byTooltip` 之类默认会跳过 Offstage。
          offstage: !widget.visible && !_controller.isAnimating,
          child: IgnorePointer(
            // 一按中间就立刻能翻页，不用等淡出播完。
            ignoring: !widget.visible,
            child: Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: widget.slideFrom * (1 - t),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
