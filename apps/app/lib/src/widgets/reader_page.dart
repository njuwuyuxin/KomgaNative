import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/widgets/reader_chrome.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu_reader/yomu_reader.dart';
import 'package:material_ui/material_ui.dart';

/// 服务端没返回尺寸时的兜底页面尺寸（比例接近实体漫画单页）。
const int kFallbackPageWidth = 1000;
const int kFallbackPageHeight = 1500;

/// 单页图片（含加载中/失败/重试）。
///
/// 翻页时**第一帧**必须已经有像素，否则用户看到的就是"闪一下黑"。
/// 字节取 provider 的值或仓库同步缓存；但字节就绪不保证 Image.memory 已解码。
/// 卷页交接时借用同一页的 decodedImage，在普通图片首帧返回前继续画现有像素。
///
/// 缓存里没有的页就**老老实实转圈**：这是"还没加载好"，不是内容本身。
/// 曾经试过"先继续画上一页"，反馈是"页码变了图没变，像 bug"——所以不要
/// 拿旧画面顶替，黑底 + 转圈反而是更准确的表达。
class ReaderPage extends ConsumerWidget {
  const ReaderPage({
    required this.bookId,
    required this.pageIndex,
    required this.palette,
    this.decodedImage,
    this.trimBorders = false,
    super.key,
  });

  final String bookId;

  /// 0 基页索引。
  final int pageIndex;

  final ReaderPalette palette;

  /// 是否按检测到的边框裁剪页图（UI-P3-10）。
  final bool trimBorders;

  /// 同一页已经解好的卷页位图，由 CurlSheets 持有；这里只借用，不释放。
  /// 字节缓存命中不等于 MemoryImage 的首帧已解码，交接时用它填补解码空窗。
  final ui.Image? decodedImage;

  Widget _decoded(ui.Image image) => RawImage(
    image: image,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = pageIndex + 1;
    final request = (bookId: bookId, page: page);
    final repo = ref.watch(readerRepositoryProvider);
    final async = ref.watch(readerPageImageProvider(request));

    // 同步问一句"这页的字节现在在不在内存里"：在就直接画第一帧。
    // 只等 provider 的话，autoDispose 的 provider 每换一页都会先给一次
    // AsyncLoading，那一帧就是用户看到的闪烁。
    final bytes = async.value ?? repo.cachedPageImage(bookId, page);
    final error = async.error;

    // 低精度缩略图优先占位：原图未就绪时先用 300px 缩略图快速显像，
    // 原图到达后在 `frameBuilder` 中无缝衔接直到首帧解码完成，不闪黑。
    final Uint8List? thumbBytes = bytes == null && decodedImage == null
        ? (repo.cachedPageThumbnail(bookId, page) ??
              ref.watch(readerPageThumbnailProvider(request)).value)
        : repo.cachedPageThumbnail(bookId, page);

    if (bytes != null) {
      final crop = trimBorders
          ? ref.watch(pageBorderCropProvider(request)).value
          : null;
      if (crop != null && !crop.isEmpty) {
        return _CroppedPage(
          key: Key('reader-image-$pageIndex'),
          bytes: bytes,
          crop: crop,
        );
      }
      return Image.memory(
        bytes,
        key: Key('reader-image-$pageIndex'),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        frameBuilder: (context, child, frame, synchronous) {
          if (frame != null) return child;
          final image = decodedImage;
          if (image != null) return _decoded(image);
          if (thumbBytes != null) {
            return Image.memory(
              thumbBytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
            );
          }
          return child;
        },
      );
    }
    final image = decodedImage;
    if (image != null) {
      return KeyedSubtree(
        key: Key('reader-image-$pageIndex'),
        child: _decoded(image),
      );
    }
    if (thumbBytes != null && error == null) {
      return Image.memory(
        thumbBytes,
        key: Key('reader-thumb-preview-$pageIndex'),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
      );
    }
    if (error != null) {
      return Center(
        child: PageError(
          error: error,
          palette: palette,
          onRetry: () => ref.invalidate(readerPageImageProvider(request)),
        ),
      );
    }
    return Center(
      child: CircularProgressIndicator(
        key: Key('reader-page-loading-$pageIndex'),
        color: palette.onBackgroundMuted,
      ),
    );
  }
}

/// 按检测到的边框只画页图的中间区域（UI-P3-10）。
///
/// 用 `MemoryImage` 的 ImageStream 拿到已解码位图，再 `drawImageRect`：
/// 这样既能精确裁源矩形，又复用 Flutter 的图片缓存，不需要自己解一遍。
class _CroppedPage extends StatefulWidget {
  const _CroppedPage({required this.bytes, required this.crop, super.key});

  final Uint8List bytes;
  final BorderCrop crop;

  @override
  State<_CroppedPage> createState() => _CroppedPageState();
}

class _CroppedPageState extends State<_CroppedPage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _image;
  bool _resolved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolved) return;
    _resolved = true;
    _stream = MemoryImage(widget.bytes)
        .resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener((ImageInfo info, bool _) {
      if (!mounted) return;
      setState(() => _image = info.image);
    });
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return Image.memory(widget.bytes, fit: BoxFit.contain);
    }
    return SizedBox.expand(
      child: CustomPaint(
        painter: _CropPainter(image: image, crop: widget.crop),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  const _CropPainter({required this.image, required this.crop});

  final ui.Image image;
  final BorderCrop crop;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTRB(
      image.width * crop.left,
      image.height * crop.top,
      image.width * (1 - crop.right),
      image.height * (1 - crop.bottom),
    );
    if (src.isEmpty || size.isEmpty) return;
    final fitted = applyBoxFit(BoxFit.contain, src.size, size);
    final dst = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.crop != crop;
}
