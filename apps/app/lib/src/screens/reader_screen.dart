import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/widgets/reader_chrome.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:material_ui/material_ui.dart';

/// 打开阅读器时从列表页带过来的上下文。
///
/// 阅读方向存在 `Series.metadata` 里、不在 `Book` 上，所以必须显式带过来；
/// 深链没有它时按从左到右处理（默认值）。
class ReaderArgs {
  const ReaderArgs({
    required this.book,
    this.direction = ReadingDirection.unknown,
  });

  final Book book;
  final ReadingDirection direction;
}

/// 漫画阅读器（单页模式）。
///
/// 这一版做的是"能读"：真实页图、点击翻页、双指缩放/拖动、返回时记住位置、
/// 进度回写 Komga。双页/纵向连续（webtoon）由 `reader_engine` 的分组函数支撑，
/// 在下一片接上（见 docs 的 M2 清单）。
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    required this.bookId,
    this.book,
    this.direction = ReadingDirection.unknown,
    super.key,
  });

  final String bookId;

  /// 从系列详情带过来的书；深链时为空，用 [readerBookProvider] 现取。
  final Book? book;

  final ReadingDirection direction;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  /// 翻页后多久回写进度：连续翻页时只写最后停下的那一页。
  static const Duration _saveDelay = Duration(milliseconds: 600);

  /// 预取前后几页，翻页时不用等网络。
  static const List<int> _prefetchOffsets = <int>[1, -1, 2];

  /// 指针移动超过这个距离就不算点击（拖拽/缩放）。
  static const double _tapSlop = 12;

  /// 0 表示"还没翻过页"，此时用服务端进度恢复位置。
  int _explicitPage = 0;
  int _lastSaved = 0;
  double _zoom = 1;
  Offset _pan = Offset.zero;
  Offset _startFocal = Offset.zero;
  double _startZoom = 1;
  Offset _startPan = Offset.zero;
  bool _chromeVisible = true;
  Timer? _saveTimer;

  /// 点击判定用自己的指针记账：`onTapUp` 与 `onScaleStart/Update` 在同一个
  /// gesture arena 里会互相抢，实测 tap 会被 scale 吃掉，翻页完全不响应。
  int _activePointers = 0;
  Offset? _downAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    super.dispose();
  }

  /// 切后台/锁屏时立刻落一次进度：只靠防抖会丢掉"看完就退出"的那一页。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    _saveTimer?.cancel();
    final total =
        ref.read(readerPagesProvider(widget.bookId)).value?.length ?? 0;
    if (total == 0) return;
    final page = _currentPage(total);
    unawaited(_persist(page, completed: page >= total));
  }

  int _currentPage(int total) {
    if (total <= 0) return 1;
    if (_explicitPage > 0) return _explicitPage.clamp(1, total);
    final resumed =
        (widget.book ?? ref.read(readerBookProvider(widget.bookId)).value)
            ?.readProgress
            ?.page ??
        1;
    return resumed.clamp(1, total);
  }

  Future<void> _persist(int page, {required bool completed}) async {
    if (page == _lastSaved) return;
    try {
      await ref
          .read(readerRepositoryProvider)
          .saveProgress(widget.bookId, page: page, completed: completed);
      _lastSaved = page;
    } on ShelfFailure {
      // 进度回写失败不打断阅读：下次翻页会再试，切后台时也会再 flush 一次。
    }
  }

  void _scheduleSave(int page, {required bool completed}) {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () {
      unawaited(_persist(page, completed: completed));
    });
  }

  Future<void> _warm(int page) async {
    try {
      await ref.read(
        readerPageImageProvider((bookId: widget.bookId, page: page)).future,
      );
    } on ShelfFailure {
      // 预取失败无所谓：真的翻到那一页时会重新请求并显示错误/重试。
    }
  }

  void _prefetch(int current, int total) {
    for (final offset in _prefetchOffsets) {
      final target = current + offset;
      if (target < 1 || target > total) continue;
      unawaited(_warm(target));
    }
  }

  void _turn({required int delta, required int current, required int total}) {
    final target = (current + delta).clamp(1, total);
    if (target == current) return;
    setState(() {
      _explicitPage = target;
      _zoom = 1;
      _pan = Offset.zero;
    });
    _prefetch(target, total);
    _scheduleSave(target, completed: target >= total);
  }

  void _onTap(double dx, double width, int current, int total) {
    final fraction = width <= 0 ? 0.5 : dx / width;
    final rightToLeft = widget.direction == ReadingDirection.rightToLeft;
    if (fraction < 0.33) {
      // 左侧三分之一：LTR 往回翻，RTL 往前翻（日漫）。
      _turn(delta: rightToLeft ? 1 : -1, current: current, total: total);
    } else if (fraction > 0.67) {
      _turn(delta: rightToLeft ? -1 : 1, current: current, total: total);
    } else {
      setState(() => _chromeVisible = !_chromeVisible);
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startZoom = _zoom;
    _startPan = _pan;
    _startFocal = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final nextZoom = (_startZoom * details.scale).clamp(1.0, 4.0);
    setState(() {
      _zoom = nextZoom;
      // 缩放后单指拖动就是平移；缩回 1 时自动归位。
      _pan = nextZoom <= 1.0
          ? Offset.zero
          : _startPan + (details.localFocalPoint - _startFocal);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bookAsync = ref.watch(readerBookProvider(widget.bookId));
    final book = widget.book ?? bookAsync.value;
    final pagesAsync = ref.watch(readerPagesProvider(widget.bookId));
    final pagesError = pagesAsync.error;
    final pages = pagesAsync.value;

    if (pagesError != null) {
      return ReaderFailure(
        failure: pagesError,
        onRetry: () => ref.invalidate(readerPagesProvider(widget.bookId)),
      );
    }
    if (pages == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white70)),
      );
    }
    if (pages.isEmpty) {
      return ReaderFailure(
        failure: const ProtocolFailure(),
        title: 'This book has no pages',
        onRetry: () => ref.invalidate(readerPagesProvider(widget.bookId)),
      );
    }

    final total = pages.length;
    final current = _currentPage(total);
    final info = pages[current - 1];
    final imageAsync = ref.watch(
      readerPageImageProvider((bookId: widget.bookId, page: current)),
    );
    final bytes = imageAsync.value;
    final imageError = imageAsync.error;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (_chromeVisible)
              ReaderBar(
                title: book?.name ?? 'Book',
                page: current,
                pagesCount: total,
                onClose: () => context.pop(),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final layout = computePagedLayout(
                    pageWidth: info.width ?? 1000,
                    pageHeight: info.height ?? 1500,
                    viewport: SizeD(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    ),
                    zoomFactor: _zoom,
                    panX: _pan.dx,
                    panY: _pan.dy,
                  );
                  return Listener(
                    key: const Key('reader-tap-layer'),
                    onPointerDown: (PointerDownEvent event) {
                      _activePointers++;
                      _downAt = _activePointers == 1
                          ? event.localPosition
                          : null;
                    },
                    onPointerUp: (PointerUpEvent event) {
                      if (_activePointers > 0) _activePointers--;
                      final down = _downAt;
                      _downAt = null;
                      if (down == null || _activePointers > 0) return;
                      // 移动超过阈值视为拖拽/缩放，不当作翻页点击。
                      if ((event.localPosition - down).distance > _tapSlop) {
                        return;
                      }
                      _onTap(down.dx, constraints.maxWidth, current, total);
                    },
                    onPointerCancel: (PointerCancelEvent event) {
                      _activePointers = 0;
                      _downAt = null;
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      child: Stack(
                        children: <Widget>[
                          if (bytes != null)
                            Positioned(
                              left: layout.content.left,
                              top: layout.content.top,
                              width: layout.content.width,
                              height: layout.content.height,
                              child: Image.memory(
                                bytes,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.medium,
                              ),
                            )
                          else
                            Center(
                              child: imageError == null
                                  ? const CircularProgressIndicator(
                                      color: Colors.white70,
                                    )
                                  : PageError(
                                      error: imageError,
                                      onRetry: () => ref.invalidate(
                                        readerPageImageProvider((
                                          bookId: widget.bookId,
                                          page: current,
                                        )),
                                      ),
                                    ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_chromeVisible)
              ReaderControls(
                page: current,
                pagesCount: total,
                onPrevious: current > 1
                    ? () => _turn(delta: -1, current: current, total: total)
                    : null,
                onNext: current < total
                    ? () => _turn(delta: 1, current: current, total: total)
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}
