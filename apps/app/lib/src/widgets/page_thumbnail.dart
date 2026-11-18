import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

/// 一张页缩略图：懒加载 + 解码降采样 + 加载/失败态。
///
/// Komga **没有**页级缩略图端点（`/books/{id}/thumbnail` 是整本封面），页级只有
/// 全尺寸的 `/pages/{n}`，所以这里用页面原图 + `cacheWidth` 降采样解码。
/// 只加载可见页靠调用方：只有被构建出来的实例才会去请求字节（见
/// `ReaderThumbnailStrip` 的 `ListView.builder`）。
class PageThumbnailImage extends ConsumerWidget {
  const PageThumbnailImage({
    required this.bookId,
    required this.page,
    required this.palette,
    this.cacheWidth = 120,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String bookId;

  /// 1 基页码。
  final int page;

  final ReaderPalette palette;

  /// 解码宽度（物理像素）；按显示尺寸 × DPR 给，不要按原图解码。
  final int cacheWidth;

  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(
      readerPageImageProvider((bookId: bookId, page: page)),
    );
    final bytes = image.value;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: fit,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
      );
    }
    if (image.hasError) {
      return Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: AppSizes.iconMd,
          color: palette.muted,
        ),
      );
    }
    // 占位**不用转圈**：一屏十来个缩略图同时转圈既吵又没有任何信息量，
    // 而且会让 `pumpAndSettle` 永远等不到静止（踩过一次，整组测试挂住）。
    return Center(
      child: SizedBox(
        width: AppSizes.iconXs,
        height: AppSizes.iconXs,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.outline,
            borderRadius: BorderRadius.circular(AppRadii.xs),
          ),
        ),
      ),
    );
  }
}
