import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:material_ui/material_ui.dart';

/// 长按上下文菜单里的一项。
@immutable
class ContextMenuEntry<T> {
  const ContextMenuEntry({
    required this.value,
    required this.label,
    required this.icon,
  });

  final T value;
  final String label;
  final IconData icon;
}

/// 长按弹出的上下文菜单（UI-P2-5）。
///
/// 锚点用被长按的那个 widget 的矩形（[anchor]），而不是手指坐标：
/// 手指坐标在 `InkWell.onLongPress` 里拿不到（要 `onLongPressStart`，
/// 而它会和 `InkWell` 的点击抢手势）。贴在控件旁边也更接近 iOS 的行为。
///
/// 墨水屏上这就是一个普通弹出菜单（`showMenu` 没有动画依赖）；
/// 按下的缩放反馈由 `PressableScale` 负责，它在墨水屏上不缩放。
Future<T?> showContextMenu<T>({
  required BuildContext context,
  required BuildContext anchor,
  required List<ContextMenuEntry<T>> entries,
}) {
  final box = anchor.findRenderObject();
  final overlay = Overlay.of(context).context.findRenderObject();
  Offset position = Offset.zero;
  Size overlaySize = MediaQuery.sizeOf(context);
  if (box is RenderBox && overlay is RenderBox) {
    position = box.localToGlobal(Offset.zero, ancestor: overlay);
    position = Offset(position.dx + AppSpacing.md, position.dy + AppSpacing.md);
    overlaySize = overlay.size;
  }
  return showMenu<T>(
    context: context,
    // 右侧/下侧的"剩余空间"必须按屏幕算，不能写成 dx/dy 本身：
    // 那样等于告诉 showMenu "可用高度 = 0"，菜单会被裁到只剩前两项（踩过）。
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      overlaySize.width - position.dx,
      overlaySize.height - position.dy,
    ),
    items: <PopupMenuEntry<T>>[
      for (final entry in entries)
        PopupMenuItem<T>(
          value: entry.value,
          child: Row(
            children: <Widget>[
              Icon(entry.icon, size: AppSizes.iconMd),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: Text(entry.label)),
            ],
          ),
        ),
    ],
  );
}
