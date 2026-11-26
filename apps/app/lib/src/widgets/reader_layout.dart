import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu_reader/yomu_reader.dart';

/// 阅读器"这一屏"的派生状态：分屏、相邻屏、能否翻页、是否读完、页码文案。
///
/// 从 `ReaderScreen` 拆出来的纯计算（只依赖页列表、模式和当前页），
/// 编排层每次 build 现算一份，不持有任何可变状态。
class ReaderLayout {
  factory ReaderLayout({
    required List<PageInfo> pages,
    required ReadingMode mode,
    required int page,
    int? groupFrom,
  }) {
    final spreads = spreadsFor(pages, mode, groupFrom: groupFrom);
    final spreadIndex = spreads.isEmpty ? -1 : spreadIndexOf(spreads, page - 1);
    return ReaderLayout._(
      mode: mode,
      page: page,
      total: pages.length,
      spreads: spreads,
      spreadIndex: spreadIndex,
    );
  }

  const ReaderLayout._({
    required this.mode,
    required this.page,
    required this.total,
    required this.spreads,
    required this.spreadIndex,
  });

  final ReadingMode mode;

  /// 1 基当前页。
  final int page;
  final int total;

  /// 双页模式的分屏；其他模式为空（每页各自一屏）。
  final List<List<int>> spreads;

  /// 当前屏在 [spreads] 里的下标；非双页模式为 -1。
  final int spreadIndex;

  /// 双页模式按"封面单独、宽页单独、其余两两"分组；其他模式返回空。
  /// [groupFrom] 是手动修正的起点（0 基，UI-P3-5）。
  static List<List<int>> spreadsFor(
    List<PageInfo> pages,
    ReadingMode mode, {
    int? groupFrom,
  }) {
    if (mode != ReadingMode.doublePage) {
      return const <List<int>>[];
    }
    return buildSpreads(
      pageCount: pages.length,
      groupFrom: groupFrom,
      aspectAt: (int index) {
        final info = pages[index];
        return PageAspect(
          width: info.width?.toDouble(),
          height: info.height?.toDouble(),
        );
      },
    );
  }

  /// 当前屏包含的 0 基页索引。
  List<int> get spread => screenAt(screenIndex);

  /// 一共多少"屏"：双页模式按跨页数，其他模式按页数。
  ///
  /// 缩略图滑条（UI-P1-2）按屏分组显示，所以这里把两种模式统一成同一组接口，
  /// 调用方不必再判断模式。
  int get screenCount => spreads.isEmpty ? total : spreads.length;

  /// 第 [index] 屏包含的 0 基页索引。
  List<int> screenAt(int index) {
    if (spreads.isEmpty) return <int>[index];
    return spreads[index.clamp(0, spreads.length - 1)];
  }

  /// 当前屏在 [screenCount] 里的下标。
  int get screenIndex {
    if (total <= 0) return 0;
    if (spreads.isEmpty) return (page - 1).clamp(0, total - 1);
    return spreadIndex < 0 ? 0 : spreadIndex;
  }

  bool get canGoBack => switch (mode) {
    ReadingMode.paged => page > 1,
    ReadingMode.doublePage => spreadIndex > 0,
    ReadingMode.verticalScroll => false,
  };

  bool get canGoForward => switch (mode) {
    ReadingMode.paged => page < total,
    ReadingMode.doublePage =>
      spreadIndex >= 0 && spreadIndex < spreads.length - 1,
    ReadingMode.verticalScroll => false,
  };

  /// 是否已经读到结尾。
  ///
  /// 双页模式下"最后一屏"可能包含倒数两页，此时 `page` 到不了 `total`，
  /// 只看页码会漏掉 `completed`，进度条永远差一页。
  bool get completed => isCompletedAt(page);

  bool isCompletedAt(int target) {
    if (target >= total) return true;
    if (mode != ReadingMode.doublePage || spreads.isEmpty) return false;
    final index = spreadIndexOf(spreads, target - 1);
    return index >= 0 && spreads[index].contains(total - 1);
  }

  /// 相邻那一屏的页索引；到书头/书尾返回 null。
  ///
  /// 翻页动画需要它：拖动时先把相邻那一屏画在下面，翻过去才真正换页。
  List<int>? neighbour(int delta) {
    if (mode == ReadingMode.doublePage && spreads.isNotEmpty) {
      final index = spreadIndex + delta;
      if (index < 0 || index >= spreads.length) return null;
      return spreads[index];
    }
    final target = page + delta;
    if (target < 1 || target > total) return null;
    return <int>[target - 1];
  }

  /// 翻 [delta] 屏之后的 1 基页码；翻不动时返回 null。
  ///
  /// 双页模式下翻页的粒度是"一跨页"，单页是"一页"；纵向模式不走这里。
  int? turnTarget(int delta) {
    if (mode == ReadingMode.verticalScroll) return null;
    if (mode == ReadingMode.doublePage && spreads.isNotEmpty) {
      final next = (spreadIndex + delta).clamp(0, spreads.length - 1);
      if (next == spreadIndex) return null;
      return spreads[next].first + 1;
    }
    final next = (page + delta).clamp(1, total);
    return next == page ? null : next;
  }

  /// 顶栏页码：单页 `3 / 12`，双页 `3–4 / 12`。
  String pageLabel(AppLocalizations l10n) {
    final current = spread;
    if (mode == ReadingMode.doublePage && current.length > 1) {
      return l10n.readerSpreadOf(current.first + 1, current.last + 1, total);
    }
    return l10n.readerPageOf(page, total);
  }

  /// 底栏的页码：只报"当前在第几页"。
  ///
  /// 以前这里显示总页数（`{count} pages`），翻页时永远不变，看起来像页码坏了；
  /// 总数已经在顶栏的 `3 / 12` 里，底栏再说一遍只会让人误以为页码没跟上。
  String positionLabel(AppLocalizations l10n) {
    final current = spread;
    if (mode == ReadingMode.doublePage && current.length > 1) {
      return l10n.currentSpread(current.first + 1, current.last + 1);
    }
    return l10n.currentPage(page);
  }

  /// 当前这一屏之后还剩多少页（双页跨页按跨页的最后一页算）。
  ///
  /// 底栏滑杆旁边用它报"还剩多少"——比"第几页"更能回答"还要读多久"（RDR-01）。
  int get remaining {
    final current = spread;
    final lastOnScreen = current.isEmpty ? page : current.last + 1;
    return (total - lastOnScreen).clamp(0, total);
  }
}
