/// 双页（跨页）分组。
///
/// 规则来自真实漫画的排版习惯：
/// - 宽页（`w/h > wideThreshold`）单独成页，避免和相邻页挤在一起；
/// - 封面可配置为单独一页（`coverSolo`）；
/// - 输出为"每屏包含哪些 0 基页索引"，由 Widget 层按阅读方向决定左右顺序。
library;

/// 默认宽页阈值：横长超过 1.2 视为跨页大图。
const double kDefaultWideAspectThreshold = 1.2;

/// 页尺寸未知时（服务端未返回 width/height）按"普通页"处理。
class PageAspect {
  const PageAspect({this.width, this.height});

  const PageAspect.unknown() : width = null, height = null;

  final double? width;
  final double? height;

  double? get ratio {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  bool isWide([double threshold = kDefaultWideAspectThreshold]) {
    final r = ratio;
    return r != null && r > threshold;
  }
}

/// 把连续的页序切成"每屏一组"。
///
/// [pageCount] 为总页数（不含索引），[aspectAt] 返回第 i 页的尺寸（可未知）。
List<List<int>> buildSpreads({
  required int pageCount,
  required PageAspect Function(int index) aspectAt,
  bool coverSolo = true,
}) {
  if (pageCount <= 0) return const [];
  final result = <List<int>>[];
  var i = 0;

  if (coverSolo) {
    result.add([0]);
    i = 1;
  }

  while (i < pageCount) {
    final current = aspectAt(i);
    if (current.isWide()) {
      result.add([i]);
      i += 1;
      continue;
    }
    if (i + 1 < pageCount) {
      final next = aspectAt(i + 1);
      if (!next.isWide()) {
        result.add([i, i + 1]);
        i += 2;
        continue;
      }
    }
    result.add([i]);
    i += 1;
  }
  return result;
}

/// 某个跨页在给定阅读方向下的视觉顺序（横向从左到右）。
///
/// RTL（日漫）时右起，因此先显示后一页；但封面单独页不反转。
List<int> visualOrder(List<int> spread, {required bool rightToLeft}) {
  if (!rightToLeft || spread.length < 2) return List<int>.unmodifiable(spread);
  return List<int>.unmodifiable(spread.reversed);
}

/// 逻辑页索引 → 所在跨页索引；越界返回 -1。
int spreadIndexOf(List<List<int>> spreads, int pageIndex) {
  for (var i = 0; i < spreads.length; i++) {
    if (spreads[i].contains(pageIndex)) return i;
  }
  return -1;
}
