part of 'reader_paged_view.dart';

/// 双页展开时半边书页的几何与源图矩形（宽页跨页图时 `clip` 为半页、`image` 为整张宽页）。
typedef _HalfSheet = ({int page, Rect clip, Rect image});

/// 一屏（1–2 页）的绘制矩形与页序。
class _SpreadFrame {
  const _SpreadFrame({
    required this.order,
    required this.sizes,
    required this.layout,
    required this.content,
    required this.slots,
    this.wideSolo = false,
    this.half = PageHalf.full,
  });

  final List<int> order;
  final Map<int, int> sizes;
  final PagedLayout layout;
  final Rect content;

  /// 每一页在画布上的矩形（按宽度比例切分 [content]）。
  final Map<int, Rect> slots;

  /// 双页模式下单独占满整屏的一张宽页跨页图：翻页时按书脊对半铰接卷曲，不退化为平移。
  final bool wideSolo;

  /// 单页宽图自动切分时的当前半幅。
  final PageHalf half;

  /// 若这一屏对应摊开的双页书本（两张单页，或双页模式下的一张宽页跨页图），
  /// 返回（左半页, 右半页）；单独居中页（如封面）返回 null。
  (_HalfSheet, _HalfSheet)? get openBookHalves {
    if (order.length == 2) {
      final left = order[0];
      final right = order[1];
      final leftRect = slots[left]!;
      final rightRect = slots[right]!;
      if (leftRect.isEmpty || rightRect.isEmpty) return null;
      return (
        (page: left, clip: leftRect, image: leftRect),
        (page: right, clip: rightRect, image: rightRect),
      );
    }
    if (wideSolo && order.length == 1) {
      final page = order.first;
      final full = slots[page]!;
      if (full.isEmpty) return null;
      final midX = full.center.dx;
      return (
        (
          page: page,
          clip: Rect.fromLTRB(full.left, full.top, midX, full.bottom),
          image: full,
        ),
        (
          page: page,
          clip: Rect.fromLTRB(midX, full.top, full.right, full.bottom),
          image: full,
        ),
      );
    }
    return null;
  }
}

/// 一次卷页要画什么：被卷的纸、纸背、垫在下面的页，以及手指运动。
///
/// 把"翻之前的屏 A"和"翻之后的屏 B"统一起来看（往前翻 A = 当前、B = 下一屏；
/// 往回翻 A = 上一屏、B = 当前，路径倒放）：
///
/// - 单页：卷的是 A 那页，下面垫 B 那页；纸背是纸底色 + 透印。
/// - 双页（含双页与宽页跨页图互翻）：卷的是 A 掀起那一侧的半页（RTL 左半、LTR 右半），
///   铰接在书脊上，翻过去平落在另一半；纸背就是 B 同侧落地的那半页。下面垫 B 掀起侧 + A 落地侧。
class _CurlPlan {
  const _CurlPlan({
    required this.sheetPage,
    required this.sheetRect,
    required this.sheetUvRect,
    required this.backPage,
    required this.backRect,
    required this.backUvRect,
    required this.spineX,
    required this.motion,
    required this.under,
  });

  final int sheetPage;
  final Rect sheetRect;
  final Rect sheetUvRect;

  /// 纸背那页（双页），单页为 null。
  final int? backPage;
  final Rect backRect;
  final Rect backUvRect;

  /// 书脊 x（画布坐标）：纸背沿它镜像。
  final double spineX;

  final CurlMotion motion;

  /// 垫在卷页下面的页与它们的裁剪/纹理矩形。
  final List<_HalfSheet> under;

  /// 涉及到的全部页：纸面 + 纸背 + 露出的底层。
  Set<int> get pages => <int>{
    sheetPage,
    ?backPage,
    for (final slot in under) slot.page,
  };

  /// 起手判定"这次能不能卷"至少要有的位图：只要求当前屏幕上被掀起的那一页/半页就绪。
  Set<int> get requiredPages {
    final back = backPage;
    if (back == null) return <int>{sheetPage};
    return <int>{motion.forward ? sheetPage : back};
  }

  /// 从屏 [before] 翻到屏 [after] 的卷页计划；封面等单双页宽度变化边界返回 null。
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

    // 摊开双页（两页并排或宽页跨页图）之间一律按书脊铰接卷页。
    final aHalves = a.openBookHalves;
    final bHalves = b.openBookHalves;
    if (aHalves != null && bHalves != null) {
      final (aLeft, aRight) = aHalves;
      final (bLeft, bRight) = bHalves;
      final lift = rightToLeft ? aLeft : aRight;
      final stay = rightToLeft ? aRight : aLeft;
      final reveal = rightToLeft ? bLeft : bRight;
      final back = rightToLeft ? bRight : bLeft;
      if (lift.clip.isEmpty) return null;
      return _CurlPlan(
        sheetPage: lift.page,
        sheetRect: lift.clip,
        sheetUvRect: lift.image,
        backPage: back.page,
        backRect: back.clip,
        backUvRect: back.image,
        spineX: mirrored ? lift.clip.left : lift.clip.right,
        motion: CurlMotion(
          forward: forward,
          width: lift.clip.width,
          height: lift.clip.height,
          exitX: lift.clip.width,
          hinged: true,
        ),
        under: <_HalfSheet>[reveal, stay],
      );
    }

    if (a.order.length == 1 && b.order.length == 1) {
      final page = a.order.first;
      final rect = a.slots[page]!;
      if (rect.isEmpty) return null;
      final nextPage = b.order.first;
      final nextRect = b.slots[nextPage]!;
      final sheetUv = _uvRectForHalf(rect, a.half);
      final nextUv = _uvRectForHalf(nextRect, b.half);
      final exitX = mirrored ? rect.right : viewportWidth - rect.left;
      return _CurlPlan(
        sheetPage: page,
        sheetRect: rect,
        sheetUvRect: sheetUv,
        backPage: null,
        backRect: rect,
        backUvRect: sheetUv,
        spineX: mirrored ? rect.left : rect.right,
        motion: CurlMotion(
          forward: forward,
          width: rect.width,
          height: rect.height,
          exitX: exitX,
        ),
        under: <_HalfSheet>[(page: nextPage, clip: nextRect, image: nextUv)],
      );
    }
    return null;
  }

  static Rect _uvRectForHalf(Rect rect, PageHalf half) => switch (half) {
    PageHalf.full => rect,
    PageHalf.left => Rect.fromLTWH(
      rect.left,
      rect.top,
      rect.width * 2,
      rect.height,
    ),
    PageHalf.right => Rect.fromLTWH(
      rect.left - rect.width,
      rect.top,
      rect.width * 2,
      rect.height,
    ),
  };
}

/// 规划、与 `ImageCache` 同步桥接及后台预解码。
extension _TurnImages on _PageTurn {
  /// 某个方向的卷页计划；不适合卷页（封面单页↔双页、尚未布局）时为 null。
  _CurlPlan? _planFor(bool forward) {
    if (widget.style.effect != PageTurnEffect.curl) return null;
    if (_viewport.isEmpty) return null;
    final before = forward ? widget.spread : widget.previousSpread;
    final after = forward ? widget.nextSpread : widget.spread;
    if (before == null || after == null) return null;
    final beforeHalf = forward ? widget.pageHalf : widget.previousPageHalf;
    final afterHalf = forward ? widget.nextPageHalf : widget.pageHalf;
    return _CurlPlan.between(
      before: _frameFor(before, _viewport, applyZoom: false, half: beforeHalf),
      after: _frameFor(after, _viewport, applyZoom: false, half: afterHalf),
      forward: forward,
      rightToLeft: widget.rightToLeft,
      viewportWidth: _viewport.width,
    );
  }

  /// 先查卷页缓存，未命中时**同步**从 Flutter `ImageCache` 借出已解码位图。
  ///
  /// 只要页面已在屏幕上渲染好或已被 `ReaderPreloader` 预解码，这里就能在同一帧内
  /// 0 延迟拿到 `ui.Image`，彻底消除"底图已显示却退化成平移 / 背面纯白"的双缓存脱节。
  ui.Image? _imageOrAdoptSync(int pageIndex) {
    final existing = _sheets.imageFor(pageIndex);
    if (existing != null) return existing;
    final sourceKey =
        ScopedSourceScope.readOf(context) ??
        ref.read(activeSourceProvider).sourceKey;
    final bytes = ref
        .read(readerRepositoryForSourceProvider(sourceKey))
        .cachedPageImage(widget.bookId, pageIndex + 1);
    if (bytes == null) return null;
    final adopted = trySyncImageFromCache(bytes);
    if (adopted != null) _sheets.putSync(pageIndex, adopted);
    return _sheets.imageFor(pageIndex);
  }

  /// 并发预解码当前屏、前后相邻屏及进行中翻页涉及的位图。
  ///
  /// **翻动期间不中断**：通过 `pinned` 保护当前卷页图层不被淘汰，让尚未下载完的纸背
  /// 能在卷动途中继续解码并平滑渐显，避免落地瞬间才从空白突变成图片。
  void _scheduleSheets() {
    if (widget.style.effect != PageTurnEffect.curl) return;
    if (_sheetsScheduled) return;
    _sheetsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sheetsScheduled = false;
      if (!mounted || widget.style.effect != PageTurnEffect.curl) return;
      final bookId = widget.bookId;
      final pinned = _plan?.pages ?? const <int>{};
      final pages = <int>{
        ...widget.spread,
        ...?widget.nextSpread,
        ...?widget.previousSpread,
        ...pinned,
      };
      unawaited(
        _sheets.ensure(
          pages: pages,
          pinned: pinned,
          decode: _decodePage,
          stillWanted: () =>
              mounted &&
              widget.bookId == bookId &&
              widget.style.effect == PageTurnEffect.curl,
        ),
      );
    });
  }

  Future<ui.Image?> _decodePage(int pageIndex) async {
    final bookId = widget.bookId;
    final sourceKey =
        ScopedSourceScope.readOf(context) ??
        ref.read(activeSourceProvider).sourceKey;
    final repository = ref.read(readerRepositoryForSourceProvider(sourceKey));
    final page = pageIndex + 1;
    final cached = repository.cachedPageImage(bookId, page);
    final Uint8List resolvedBytes;
    if (cached != null) {
      final sync = trySyncImageFromCache(cached);
      if (sync != null) return sync;
      resolvedBytes = cached;
    } else {
      try {
        resolvedBytes = await ref.read(
          readerPageImageProvider((
            sourceKey: sourceKey,
            bookId: bookId,
            page: page,
          )).future,
        );
      } on ShelfFailure {
        return null;
      }
    }
    if (!mounted || widget.bookId != bookId) return null;
    return decodeThroughImageCache(
      resolvedBytes,
      onRegisterCancel: (VoidCallback cancel) =>
          _sheets.registerCancel(pageIndex, cancel),
    );
  }
}
