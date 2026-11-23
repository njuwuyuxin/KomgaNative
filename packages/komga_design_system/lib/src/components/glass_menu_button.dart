import 'dart:async';

import 'package:flutter/services.dart';
import 'package:komga_design_system/src/components/glass_icon_button.dart';
import 'package:komga_design_system/src/components/glass_surface.dart';
import 'package:komga_design_system/src/materials.dart';
import 'package:komga_design_system/src/motion.dart';
import 'package:komga_design_system/src/shapes.dart';
import 'package:komga_design_system/src/tokens.dart';
import 'package:material_ui/material_ui.dart';

part 'glass_menu_button_parts.dart';

/// 玻璃图标 + 带展开/收回动画的弹出玻璃菜单（排序 / 筛选 / 视图 / 更多）。
///
/// 为什么自己用 `OverlayPortal` 而不是 `MenuAnchor`：
/// Flutter M3 的 `MenuAnchor` 开关没有过渡动画（瞬间闪现/消失）。
/// 这里在展开时从触发按钮所在角缩放 + 淡入，收回时反向缩回并淡出，
/// 动画结束后才卸载浮层；墨水屏或"减少动态效果"下退化为瞬切。
class GlassMenuButton extends StatefulWidget {
  const GlassMenuButton({
    required this.icon,
    required this.label,
    required this.menuChildren,
    this.orb = false,
    this.selected = false,
    super.key,
  });

  final IconData icon;

  /// 读屏标签 / 长按提示。
  final String label;

  /// 菜单项：由调用方构造 [GlassMenuItemButton] / `Divider`，key 挂在项上。
  final List<Widget> menuChildren;

  /// true = 独立玻璃圆球；false = 玻璃条内部的图标（标题栏动作）。
  final bool orb;

  final bool selected;

  @override
  State<GlassMenuButton> createState() => _GlassMenuButtonState();
}

class _GlassMenuButtonState extends State<GlassMenuButton>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _anchorKey = GlobalKey();
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener(_onStatus);

  Rect _anchorRect = Rect.zero;
  bool _opening = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && _portal.isShowing && !_opening) {
      _portal.hide();
    }
  }

  void _open() {
    final anchorBox =
        _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (anchorBox != null && overlayBox != null && anchorBox.hasSize) {
      final topLeft = anchorBox.localToGlobal(
        Offset.zero,
        ancestor: overlayBox,
      );
      _anchorRect = topLeft & anchorBox.size;
    } else {
      _anchorRect = Rect.zero;
    }
    _opening = true;
    if (!_portal.isShowing) _portal.show();
    final motion = AppMotion.of(context);
    if (!motion.enabled) {
      _controller.value = 1;
      return;
    }
    _controller
      ..duration = motion.standard
      ..reverseDuration = motion.quick;
    unawaited(_controller.forward());
  }

  void _close() {
    if (!_portal.isShowing) return;
    _opening = false;
    final motion = AppMotion.of(context);
    if (!motion.enabled) {
      _controller.value = 0;
      _portal.hide();
      return;
    }
    _controller.reverseDuration = motion.quick;
    unawaited(_controller.reverse());
  }

  void _toggle() {
    if (_opening && _portal.isShowing) {
      _close();
    } else {
      _open();
    }
  }

  Widget _buildOverlay(BuildContext context) {
    final motion = AppMotion.of(context);
    final media = MediaQuery.of(context);
    final overlaySize = media.size;
    final alignRight = _anchorRect.center.dx > overlaySize.width / 2;
    final spaceBelow =
        overlaySize.height - media.padding.bottom - _anchorRect.bottom;
    final spaceAbove = _anchorRect.top - media.padding.top;
    final openUpward =
        spaceBelow < AppSizes.shelfRowHeight && spaceAbove > spaceBelow;
    final origin = Alignment(alignRight ? 1.0 : -1.0, openUpward ? 1.0 : -1.0);
    final maxMenuHeight =
        (overlaySize.height -
                media.padding.top -
                media.padding.bottom -
                AppSpacing.xl)
            .clamp(AppSizes.minTouch, double.infinity);

    final panel = GlassSurface(
      shape: AppShapes.of(context, AppShapes.panel),
      shadows: AppShadows.floating,
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: AppSpacing.xxl * 3,
            maxHeight: maxMenuHeight,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.menuChildren,
              ),
            ),
          ),
        ),
      ),
    );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: FocusScope(
        autofocus: true,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _close,
              ),
            ),
            CustomSingleChildLayout(
              delegate: _GlassMenuLayoutDelegate(
                anchor: _anchorRect,
                padding: media.padding,
                alignRight: alignRight,
                openUpward: openUpward,
              ),
              child: _GlassMenuScope(
                close: _close,
                isClosing: () => !_opening,
                child: AnimatedBuilder(
                  animation: _controller,
                  child: panel,
                  builder: (BuildContext context, Widget? child) {
                    final v = _controller.value;
                    final reversing =
                        _controller.status == AnimationStatus.reverse;
                    final scaleT =
                        (reversing ? motion.exitCurve : motion.emphasizedCurve)
                            .transform(v);
                    final fadeT =
                        (reversing ? motion.exitCurve : motion.standardCurve)
                            .transform(v)
                            .clamp(0.0, 1.0);
                    return Opacity(
                      opacity: fadeT,
                      child: Transform.scale(
                        scale: 0.86 + 0.14 * scaleT,
                        alignment: origin,
                        child: child,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trigger = widget.orb
        ? GlassIconButton(
            icon: widget.icon,
            label: widget.label,
            selected: widget.selected,
            onPressed: _toggle,
          )
        : GlassBarAction(
            icon: widget.icon,
            label: widget.label,
            selected: widget.selected,
            onPressed: _toggle,
          );
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildOverlay,
      child: KeyedSubtree(key: _anchorKey, child: trigger),
    );
  }
}
