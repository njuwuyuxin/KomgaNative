import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

/// 一张页缩略图：优先走低精度页缩略图端点 + 解码降采样 + 加载/失败态。
///
/// 使用 Komga `/api/v1/books/{id}/pages/{n}/thumbnail`（长边 300px JPEG），
/// 比全尺寸原图小 1–2 个数量级，先于实际页面原图快速加载显示，且不挤占原图 LRU。
/// 若原图或缩略图已在内存缓存里则首帧同步直出，不闪烁占位块。
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
    final request = (bookId: bookId, page: page);
    final repo = ref.watch(readerRepositoryProvider);
    final syncThumb = repo.cachedPageThumbnail(bookId, page);
    final syncFull = syncThumb == null
        ? repo.cachedPageImage(bookId, page)
        : null;
    if (syncThumb != null || syncFull != null) {
      return Image.memory(
        syncThumb ?? syncFull!,
        fit: fit,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
      );
    }

    final thumb = ref.watch(readerPageThumbnailProvider(request));
    final bytes = thumb.value;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: fit,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
      );
    }
    if (thumb.hasError) {
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
