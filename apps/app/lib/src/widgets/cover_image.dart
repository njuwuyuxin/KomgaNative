import 'dart:typed_data';

import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:material_ui/material_ui.dart';

/// 封面图：解码出第一帧时淡入（UI-P2-1）。
///
/// 三处封面（书架卡片 / 继续阅读 / 书末"下一本"）都走这里：
/// 以前是"色块 → 图片"瞬切，现在从 0 淡入，翻书架时不会一下一下地"闪白"。
/// 墨水屏与系统"减少动态效果"时时长为 0（`AppMotion` 已退化），等价于直接出图。
class CoverImage extends StatelessWidget {
  const CoverImage({
    required this.bytes,
    this.fit = BoxFit.cover,
    this.filterQuality = FilterQuality.medium,
    super.key,
  });

  final Uint8List bytes;
  final BoxFit fit;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context);
    return Image.memory(
      bytes,
      fit: fit,
      gaplessPlayback: true,
      filterQuality: filterQuality,
      frameBuilder:
          (
            BuildContext context,
            Widget child,
            int? frame,
            bool wasSynchronouslyLoaded,
          ) {
            // 已在 ImageCache 里的图是同步出帧的，再包一层淡入反而会闪。
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: motion.standard,
              curve: motion.standardCurve,
              child: child,
            );
          },
    );
  }
}
