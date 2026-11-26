import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/src/widgets/cover_image.dart';
import 'package:material_ui/material_ui.dart';

/// 系列详情头部的封面槽位：带形状/阴影的封面 + Hero（书架卡片 → 详情头部）。
///
/// 为什么单独抽出来：**加载态和内容态必须共用同一个槽位**。首次打开系列时
/// 元信息还在路上，但封面字节通常已经缓存好了（书架刚画过同一张图），
/// 这时也要把封面和 Hero 落点画出来——从书架点进来的共享元素动画才有终点。
/// 否则第一次打开只是一次全屏加载，同一本书第二次打开才有动画（真机上撞到过）。
///
/// [heroTag] 由调用方传入（见 `seriesHeroTag`）：同一页面上同一个系列可能有多份
/// 副本，tag 必须和**被点的那张卡片**一致，否则会从另一份的位置飞进来。
class SeriesHeaderCover extends StatelessWidget {
  const SeriesHeaderCover({
    required this.bytes,
    required this.heroTag,
    super.key,
  });

  final Uint8List? bytes;
  final String heroTag;

  /// 封面槽位尺寸：宽 `xxl × 2`、高 `xxl × 3`（2:3 的书封比例）。
  static const Size size = Size(AppSpacing.xxl * 2, AppSpacing.xxl * 3);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = AppShapes.of(context, AppShapes.panel);
    final data = bytes;
    final cover = DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: AppShadows.of(context, AppShadows.cover),
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: SizedBox.fromSize(
          size: size,
          // 占位用 SkeletonBox 而不是裸色块：墨水屏的容器色会退化成纸白，
          // 裸色块在灰阶屏上是看不见的。
          child: data == null
              ? const SkeletonBox(shape: RoundedRectangleBorder())
              : CoverImage(bytes: data),
        ),
      ),
    );
    if (AppTheme.isEink(theme)) return cover;
    return Hero(tag: heroTag, child: cover);
  }
}

/// 头部背景：同一张封面放大 + 模糊。
///
/// 用 `ImageFiltered` 而不是 `BackdropFilter`：模糊的是封面自己，便宜得多，
/// 也不违反"页面里不许直接写 BackdropFilter"的约定。
class SeriesHeaderBackdrop extends StatelessWidget {
  const SeriesHeaderBackdrop({required this.bytes, super.key});

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final data = bytes;
    if (data == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      );
    }
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Transform.scale(
          // 放大一点，避免模糊后边缘露出底色。
          scale: 1.2,
          child: Image.memory(
            data,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
          ),
        ),
      ),
    );
  }
}
