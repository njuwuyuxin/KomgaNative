part of 'glass_menu_button.dart';

class _GlassMenuLayoutDelegate extends SingleChildLayoutDelegate {
  const _GlassMenuLayoutDelegate({
    required this.anchor,
    required this.padding,
    required this.alignRight,
    required this.openUpward,
  });

  final Rect anchor;
  final EdgeInsets padding;
  final bool alignRight;
  final bool openUpward;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    const margin = AppSpacing.sm;
    final desiredX = alignRight ? anchor.right - childSize.width : anchor.left;
    final desiredY = openUpward
        ? anchor.top - AppSpacing.xs - childSize.height
        : anchor.bottom + AppSpacing.xs;
    final maxX = (size.width - childSize.width - margin).clamp(
      margin,
      double.infinity,
    );
    final minY = padding.top + margin;
    final maxY = (size.height - padding.bottom - childSize.height - margin)
        .clamp(minY, double.infinity);
    return Offset(desiredX.clamp(margin, maxX), desiredY.clamp(minY, maxY));
  }

  @override
  bool shouldRelayout(_GlassMenuLayoutDelegate oldDelegate) =>
      oldDelegate.anchor != anchor ||
      oldDelegate.padding != padding ||
      oldDelegate.alignRight != alignRight ||
      oldDelegate.openUpward != openUpward;
}

class _GlassMenuScope extends InheritedWidget {
  const _GlassMenuScope({
    required this.close,
    required this.isClosing,
    required super.child,
  });

  final VoidCallback close;
  final bool Function() isClosing;

  static _GlassMenuScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GlassMenuScope>();

  @override
  bool updateShouldNotify(_GlassMenuScope oldWidget) => false;
}

/// 玻璃菜单里的一行：**文本始终居中**，选中对勾放在左侧独立槽位。
class GlassMenuItemButton extends StatelessWidget {
  const GlassMenuItemButton({
    required this.label,
    required this.onPressed,
    this.checked = false,
    this.icon,
    this.enabled = true,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final bool checked;

  /// 未选中时可选的左侧图标。
  final IconData? icon;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withValues(alpha: 0.38);

    void handleTap() {
      final scope = _GlassMenuScope.maybeOf(context);
      if (scope != null && scope.isClosing()) return;
      scope?.close();
      onPressed();
    }

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      selected: checked,
      child: InkWell(
        onTap: enabled ? handleTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.minTouch),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.iconLg,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                    ),
                  ),
                ),
                if (checked)
                  Positioned(
                    left: AppSpacing.xs,
                    top: 0,
                    bottom: 0,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(
                        Icons.check,
                        size: AppSizes.iconXs,
                        color: foreground,
                      ),
                    ),
                  )
                else if (icon != null)
                  Positioned(
                    left: AppSpacing.xs,
                    top: 0,
                    bottom: 0,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(
                        icon,
                        size: AppSizes.iconXs,
                        color: foreground,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
