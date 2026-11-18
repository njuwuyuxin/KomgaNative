import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/widgets/reader_chrome.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

/// 服务端没返回尺寸时的兜底页面尺寸（比例接近实体漫画单页）。
const int kFallbackPageWidth = 1000;
const int kFallbackPageHeight = 1500;

/// 单页图片（含加载中/失败/重试）。
///
/// 翻页时**第一帧**必须已经有像素，否则用户看到的就是"闪一下黑"。
/// 两条路径按优先级：
/// 1. provider 已经有值（同屏内的重绘）；
/// 2. 仓库同步缓存里有这页的字节（翻回去 / 预取过）——直接画，不进 loading。
///
/// 缓存里没有的页就**老老实实转圈**：这是"还没加载好"，不是内容本身。
/// 曾经试过"先继续画上一页"，反馈是"页码变了图没变，像 bug"——所以不要
/// 拿旧画面顶替，黑底 + 转圈反而是更准确的表达。
class ReaderPage extends ConsumerWidget {
  const ReaderPage({
    required this.bookId,
    required this.pageIndex,
    required this.palette,
    super.key,
  });

  final String bookId;

  /// 0 基页索引。
  final int pageIndex;

  final ReaderPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = pageIndex + 1;
    final request = (bookId: bookId, page: page);
    final async = ref.watch(readerPageImageProvider(request));

    // 同步问一句"这页的字节现在在不在内存里"：在就直接画第一帧。
    // 只等 provider 的话，autoDispose 的 provider 每换一页都会先给一次
    // AsyncLoading，那一帧就是用户看到的闪烁。
    final bytes =
        async.value ??
        ref.watch(readerRepositoryProvider).cachedPageImage(bookId, page);
    final error = async.error;

    if (bytes != null) {
      return Image.memory(
        bytes,
        key: Key('reader-image-$pageIndex'),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
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
    return Center(child: CircularProgressIndicator(color: palette.muted));
  }
}
