import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/widgets/reader_page.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:flutter/scheduler.dart' show Ticker;
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
    this.trimBorders = false,
    this.autoScrollSpeed = 5,
    this.autoScrollAllowed = true,
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

  /// 自动裁掉页图白边（UI-P3-10）。
  final bool trimBorders;

  /// 自动滚动速度档位 1–10（RDR-08）。
  final int autoScrollSpeed;

  /// 是否允许自动滚动：墨水屏一律关掉（每次滚动都是整屏刷新，体验很差）。
  final bool autoScrollAllowed;

  @override
  State<ReaderVerticalView> createState() => _ReaderVerticalViewState();
}

class _ReaderVerticalViewState extends State<ReaderVerticalView>
    with SingleTickerProviderStateMixin {
  final ScrollController _controller = ScrollController();

  /// 自动滚动（RDR-08）：用 ticker 而不是 `animateTo(maxScrollExtent, duration)`，
  /// 后者在用户中途暂停/恢复时没法平滑接上，且长条漫画的时长会算成几分钟。
  late final Ticker _autoScroll = createTicker(_onAutoTick);
  Duration _lastTick = Duration.zero;
  bool _autoPlaying = false;

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
    _autoScroll.dispose();
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  /// 一帧滚一点：按真实帧间隔算，速度和帧率无关。
  void _onAutoTick(Duration elapsed) {
    final delta = elapsed - _lastTick;
    _lastTick = elapsed;
    if (!_controller.hasClients || delta <= Duration.zero) return;
    final step = autoScrollDeltaForFrame(widget.autoScrollSpeed, delta);
    final max = _controller.position.maxScrollExtent;
    final next = (_controller.offset + step).clamp(0.0, max);
    if (next >= max) {
      // 到底了：自动停，别让用户以为还在滚。
      _setAutoPlaying(false);
      _controller.jumpTo(max);
      return;
    }
    _controller.jumpTo(next);
  }

  void _setAutoPlaying(bool playing) {
    if (playing == _autoPlaying) return;
    setState(() => _autoPlaying = playing);
    if (playing) {
      _lastTick = Duration.zero;
      _autoScroll.start();
    } else {
      _autoScroll.stop();
    }
  }

  /// 触摸即暂停：手一碰就开始自己滚，很容易失去控制。
  void _pauseOnTouch() {
    if (_autoPlaying) _setAutoPlaying(false);
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

        return Stack(
          children: <Widget>[
            Listener(
              // 触摸即暂停（RDR-08）。
              onPointerDown: (PointerDownEvent _) => _pauseOnTouch(),
              child: GestureDetector(
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
                      trimBorders: widget.trimBorders,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.autoScrollAllowed)
              // 放在右上角：底部被页码滑条/缩略图栏占着，按钮放下面会被 chrome 盖住。
              Positioned(
                right: AppSpacing.md,
                top: AppSpacing.xxl,
                child: _AutoScrollButton(
                  playing: _autoPlaying,
                  palette: widget.palette,
                  onPressed: () => _setAutoPlaying(!_autoPlaying),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 自动滚动的播放/暂停按钮（RDR-08）。
///
/// 图标用 `palette` 上色，跟着阅读背景走（白底黑图、黑底白图都能看清）。
class _AutoScrollButton extends StatelessWidget {
  const _AutoScrollButton({
    required this.playing,
    required this.palette,
    required this.onPressed,
  });

  final bool playing;
  final ReaderPalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: playing ? l10n.autoScrollPause : l10n.autoScrollStart,
      child: IconButton.filledTonal(
        key: const Key('reader-auto-scroll-toggle'),
        tooltip: playing ? l10n.autoScrollPause : l10n.autoScrollStart,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: palette.background.withValues(alpha: 0.72),
          foregroundColor: palette.onBackground,
        ),
        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
      ),
    );
  }
}
