import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/widgets/reader_paged_view.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:material_ui/material_ui.dart';

/// 纵向连续（webtoon / 条漫）绘制层。
///
/// 用 `ListView.builder` 按"算好的每页高度"铺开，天然只构建可见的几页；
/// 滚动位置 → 页码 用引擎的 `pageAtViewportCenter` 换算（纯函数、有单测），
/// 不再靠"第几个 item 被 build 了"去猜——那个信号在快速滚动时完全不可靠。
class ReaderVerticalView extends StatefulWidget {
  const ReaderVerticalView({
    required this.bookId,
    required this.pages,
    required this.initialPage,
    required this.palette,
    required this.onPageChanged,
    required this.onToggleChrome,
    this.jumpToken = 0,
    this.jumpPage = 1,
    super.key,
  });

  final String bookId;
  final List<PageInfo> pages;

  /// 打开时先滚到这一页（1 基）：模式切换/恢复进度都走这里。
  final int initialPage;

  final ReaderPalette palette;

  /// 可见页变化（1 基）。只在真的换页时回调，避免每帧都 setState。
  final ValueChanged<int> onPageChanged;

  final VoidCallback onToggleChrome;

  /// 外部"跳页"请求：token 变化时滚到 [jumpPage]。
  ///
  /// 不能拿 `initialPage` 兼做这个：滚动本身也会改页码，
  /// 那样会变成"滚动 → 通知 → 再跳回去"的死循环。
  final int jumpToken;
  final int jumpPage;

  @override
  State<ReaderVerticalView> createState() => _ReaderVerticalViewState();
}

class _ReaderVerticalViewState extends State<ReaderVerticalView> {
  final ScrollController _controller = ScrollController();

  VerticalLayout? _layout;
  double _viewportHeight = 0;
  bool _jumped = false;
  int _reported = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    final layout = _layout;
    if (layout == null || _viewportHeight <= 0) return;
    final page =
        pageAtViewportCenter(
          layout,
          scrollOffset: _controller.offset,
          viewportHeight: _viewportHeight,
        ) +
        1;
    if (page == _reported) return;
    _reported = page;
    widget.onPageChanged(page);
  }

  void _jumpToInitialPage() {
    final layout = _layout;
    if (_jumped || layout == null || layout.isEmpty) return;
    _jumped = true;
    _jumpTo(widget.initialPage);
  }

  void _jumpTo(int page) {
    final layout = _layout;
    if (layout == null || layout.isEmpty) return;
    final offset = scrollOffsetForPage(layout, page - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpTo(
        offset.clamp(0.0, _controller.position.maxScrollExtent),
      );
    });
  }

  @override
  void didUpdateWidget(ReaderVerticalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.jumpToken != oldWidget.jumpToken) {
      _jumpTo(widget.jumpPage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final layout = computeVerticalLayout(
          pageCount: widget.pages.length,
          viewportWidth: constraints.maxWidth,
          aspectAt: (int index) {
            final info = widget.pages[index];
            return PageAspect(
              width: info.width?.toDouble(),
              height: info.height?.toDouble(),
            );
          },
        );
        _layout = layout;
        _viewportHeight = constraints.maxHeight;
        // 首次拿到宽度后才能算偏移，因此跳转放在帧后。
        _jumpToInitialPage();

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggleChrome,
          child: ListView.builder(
            key: const Key('reader-vertical-list'),
            controller: _controller,
            itemCount: widget.pages.length,
            // 预取上下两屏，快速滚动时不会看到一片空白。
            scrollCacheExtent: const ScrollCacheExtent.viewport(2),
            itemBuilder: (BuildContext context, int index) => SizedBox(
              height: layout.pageHeights[index],
              width: double.infinity,
              child: ReaderPage(
                bookId: widget.bookId,
                pageIndex: index,
                palette: widget.palette,
              ),
            ),
          ),
        );
      },
    );
  }
}
