part of 'reader_paged_view.dart';

/// 一屏（1–2 页）的绘制矩形与页序。
class _SpreadFrame {
  const _SpreadFrame({
    required this.order,
    required this.sizes,
    required this.layout,
    required this.content,
    required this.slots,
  });

  final List<int> order;
  final Map<int, int> sizes;
  final PagedLayout layout;
  final Rect content;

  /// 每一页在画布上的矩形（按宽度比例切分 [content]）。
  final Map<int, Rect> slots;
}

/// 一次卷页要画什么：被卷的纸、纸背、垫在下面的页，以及手指运动。
///
/// 把"翻之前的屏 A"和"翻之后的屏 B"统一起来看（往前翻 A = 当前、B = 下一屏；
/// 往回翻 A = 上一屏、B = 当前，路径倒放）：
///
/// - 单页：卷的是 A 那页，下面垫 B 那页；纸背是白纸。
/// - 双页：卷的是 A 掀起那一侧的半页（RTL 左半、LTR 右半），铰接在书脊上，
///   翻过去平落在另一半；纸背就是 B 同侧落地的那页。下面垫 B 掀起侧 + A 落地侧。
class _CurlPlan {
  const _CurlPlan({
    required this.sheetPage,
    required this.sheetRect,
    required this.backPage,
    required this.backRect,
    required this.spineX,
    required this.motion,
    required this.under,
  });

  final int sheetPage;
  final Rect sheetRect;

  /// 纸背那页（双页），单页为 null（白纸）。
  final int? backPage;
  final Rect backRect;

  /// 书脊 x（画布坐标）：纸背沿它镜像。
  final double spineX;

  final CurlMotion motion;

  /// 垫在卷页下面的页与它们的矩形。
  final List<(int, Rect)> under;

  /// 露出的底层也必须有像素，不能只保证纸面和纸背已解码。
  Set<int> get pages => <int>{
    sheetPage,
    ?backPage,
    for (final (page, _) in under) page,
  };

  /// 从屏 [before] 翻到屏 [after] 的卷页计划；页数不配对时为 null。
  ///
  /// 卷页的镜像：往前翻和往回翻是同一张纸的正放/倒放，用同一个角——
  /// RTL（日漫，书脊在右）从左下角掀；LTR（书脊在左）从右下角掀。
  static _CurlPlan? between({
    required _SpreadFrame before,
    required _SpreadFrame after,
    required bool forward,
    required bool rightToLeft,
    required double viewportWidth,
  }) {
    final mirrored = !rightToLeft;
    final a = before;
    final b = after;
    if (a.order.length == 1 && b.order.length == 1) {
      final page = a.order.first;
      final rect = a.slots[page]!;
      if (rect.isEmpty) return null;
      // 卷筒要滑出**屏幕**另一侧，而不是只滑出纸面。
      final exitX = mirrored ? rect.right : viewportWidth - rect.left;
      return _CurlPlan(
        sheetPage: page,
        sheetRect: rect,
        backPage: null,
        backRect: rect,
        spineX: mirrored ? rect.left : rect.right,
        motion: CurlMotion(
          forward: forward,
          width: rect.width,
          height: rect.height,
          exitX: exitX,
        ),
        under: <(int, Rect)>[(b.order.first, b.slots[b.order.first]!)],
      );
    }
    if (a.order.length != 2 || b.order.length != 2) return null;

    // 视觉顺序里掀起的那一侧：RTL 是左边（下标 0），LTR 是右边。
    final lift = rightToLeft ? 0 : 1;
    final sheet = a.order[lift];
    final stay = a.order[1 - lift];
    final back = b.order[1 - lift];
    final reveal = b.order[lift];
    final rect = a.slots[sheet]!;
    if (rect.isEmpty) return null;
    return _CurlPlan(
      sheetPage: sheet,
      sheetRect: rect,
      backPage: back,
      backRect: b.slots[back]!,
      spineX: mirrored ? rect.left : rect.right,
      motion: CurlMotion(
        forward: forward,
        width: rect.width,
        height: rect.height,
        exitX: rect.width,
        hinged: true,
      ),
      under: <(int, Rect)>[(reveal, b.slots[reveal]!), (stay, a.slots[stay]!)],
    );
  }
}

/// 规划与预加载和翻页控制器分离：当前屏和底层共用卷页像素。
extension _TurnImages on _PageTurn {
  /// 某个方向的卷页计划；不适合卷页（单页↔双页、尚未布局）时为 null。
  _CurlPlan? _planFor(bool forward) {
    if (widget.style.effect != PageTurnEffect.curl) return null;
    if (_viewport.isEmpty) return null;
    final before = forward ? widget.spread : widget.previousSpread;
    final after = forward ? widget.nextSpread : widget.spread;
    if (before == null || after == null) return null;
    return _CurlPlan.between(
      before: _frameFor(before, _viewport, applyZoom: false),
      after: _frameFor(after, _viewport, applyZoom: false),
      forward: forward,
      rightToLeft: widget.rightToLeft,
      viewportWidth: _viewport.width,
    );
  }

  /// 空闲时把两个方向卷页要用的位图解码好，开始拖的那一刻就有图可用。
  ///
  /// 解码失败就不做卷页，自动退化成平移，不打断阅读。
  void _scheduleSheets() {
    if (widget.style.effect != PageTurnEffect.curl) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _phase != _TurnPhase.idle) return;
      final spread = widget.spread;
      final pages = <int>{
        ...spread,
        ...?_planFor(true)?.pages,
        ...?_planFor(false)?.pages,
      };
      unawaited(
        _sheets.ensure(
          pages: pages,
          decode: _decodePage,
          stillWanted: () =>
              mounted &&
              ReaderPagedViewState._sameSpread(widget.spread, spread),
        ),
      );
    });
  }

  Future<ui.Image?> _decodePage(int pageIndex) async {
    final repository = ref.read(readerRepositoryProvider);
    final page = pageIndex + 1;
    Uint8List? bytes = repository.cachedPageImage(widget.bookId, page);
    try {
      bytes ??= await repository.pageImage(widget.bookId, page);
    } on ShelfFailure {
      return null;
    }
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }
}
