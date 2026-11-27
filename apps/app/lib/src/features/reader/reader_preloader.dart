import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu_reader/yomu_reader.dart';

/// 阅读器的页图预取调度（单页 / 双页）。
///
/// 从 `ReaderScreen` 里拆出来：这里只管"按屏算计划 → 排队 → 限流发请求"，
/// 不碰 widget 树；"抓字节"和"预解码"由调用方注入，测试和页面共用一套逻辑。
class ReaderPreloader {
  ReaderPreloader({
    required this.fetch,
    required this.decode,
    required this.isActive,
  });

  /// 往前预取几屏（双页模式一屏两页）。
  ///
  /// 4 屏 ≈ 单页 4 页 / 双页 8 页：一页看 1 秒的人也有 4 秒以上缓冲，
  /// 不会翻两下就撞上"还没加载好"的转圈。再多就开始抢当前页的带宽了。
  static const int aheadScreens = 4;

  /// 往后预取几屏：回翻也常见，但优先级低于往前。
  static const int behindScreens = 2;

  /// 往前预解码几屏。
  ///
  /// 解码结果占的是 `ImageCache` 的 100 MB 预算（一张 1500×2200 约 13 MB），
  /// 所以比"抓字节"浅一档：只保证最近要看的这几屏翻过去首帧就有像素。
  static const int decodeAheadScreens = 2;

  /// 往后预解码几屏：保证连续回翻时 `ImageCache` 与卷页同步桥接始终热命中。
  static const int decodeBehindScreens = 2;

  /// 预取时最多同时飞几张页图。
  ///
  /// 一起发太多会把"真正要显示的那一页"挤到队尾，弱网下反而更慢；
  /// 排队的其余页会在前面的回来之后接着发（[_pump]），不会丢。
  static const int concurrency = 4;

  /// 抓第 n 页（1 基）的字节；失败抛 [ShelfFailure]。
  final Future<Uint8List> Function(int page) fetch;

  /// 把字节解码进 `ImageCache`（只对 [decodeAheadScreens] 内的页调用）。
  final void Function(Uint8List bytes) decode;

  /// 宿主是否还活着（页面卸载后不再解码、不再补发）。
  final bool Function() isActive;

  /// 正在预取的页（1 基），用来限流和去重。
  final Set<int> _inFlight = <int>{};

  /// 还没轮到发的预取任务，按优先级（越近越前）。
  final List<({int page, bool decode})> _queue = <({int page, bool decode})>[];

  /// 已经排过预取的锚点（如 `第几页:模式`）。模式变了分屏就变了，必须重排。
  String? _anchor;

  /// 已经排进下一帧、还没执行的预取。
  bool _scheduled = false;

  /// 锚点变了才在**下一帧**排一次预取；[plan] 届时再取最新状态并调用 [planAround]。
  ///
  /// 不在 `build` 里直接发请求：build 只该读状态；而且晚一帧再发也保证
  /// 当前页自己的请求先出去——弱网下出场顺序就是优先级。
  void scheduleFor(String anchor, void Function() plan) {
    if (_anchor == anchor) return;
    _anchor = anchor;
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (isActive()) plan();
    });
  }

  /// 预取当前页前后几屏。
  ///
  /// 双页模式下"一屏"是两页，所以计划按分屏算（`preloadPlan`），
  /// 而不是 `page ± 1`——那样会一直漏掉每屏的第二页。
  /// [spreads] 为空表示每页各自一屏。
  void planAround({
    required int page,
    required int total,
    required List<List<int>> spreads,
  }) {
    if (total <= 0) return;
    // 字节：往前 4 屏、往后 2 屏。阅读快的人也不会翻两下就撞上转圈。
    final bytesPlan = preloadPlan(
      pageIndex: page - 1,
      pageCount: total,
      spreads: spreads,
      ahead: aheadScreens,
      behind: behindScreens,
    );
    // 位图：前后各预解码 2 屏，往前翻和连续往回翻都能在首帧同步命中 `ImageCache`。
    final decodePlan = preloadPlan(
      pageIndex: page - 1,
      pageCount: total,
      spreads: spreads,
      ahead: decodeAheadScreens,
      behind: decodeBehindScreens,
    ).toSet();

    // 整份计划重新排队：还没发的旧计划作废（分屏/位置可能已经变了），
    // 已经在飞的不受影响。
    _queue
      ..clear()
      ..addAll(<({int page, bool decode})>[
        for (final index in bytesPlan)
          (page: index + 1, decode: decodePlan.contains(index)),
      ]);
    _pump();
  }

  /// 按并发上限从队列里发预取。
  ///
  /// 之前是"超上限的直接丢"，结果是阅读快时计划尾部永远轮不到；
  /// 改成排队后，前一个回来就补下一个，最多慢一点但不会漏。
  void _pump() {
    while (_inFlight.length < concurrency && _queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      if (_inFlight.contains(next.page)) continue;
      unawaited(_preload(next.page, decode: next.decode));
    }
  }

  /// 预取一页：抓字节暖仓库 LRU；[decode] 为真时顺手把位图解码进 ImageCache。
  ///
  /// 只暖字节是不够的——`Image` 要等解码完才有像素，那段空档就是用户看到的
  /// "翻页时闪一下黑"。解码过之后翻过去的第一帧就有图。
  ///
  /// 失败静默：真翻到那一页时会重新请求，走正常的错误/重试路径。
  Future<void> _preload(int page, {required bool decode}) async {
    if (!_inFlight.add(page)) return;
    try {
      final bytes = await fetch(page);
      if (decode && isActive()) this.decode(bytes);
    } on ShelfFailure {
      // 预取失败不影响阅读。
    } finally {
      _inFlight.remove(page);
      if (isActive()) _pump();
    }
  }
}
