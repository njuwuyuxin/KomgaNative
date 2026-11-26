/// 翻页前的页图预取计划。
///
/// 为什么不直接 `page + 1`：双页模式一屏是**两页**，翻一屏要换两张图。
/// 按页码加减去预热会一直漏掉每屏的第二页（`page + 1` 拿到的是本屏正在看的
/// 那一页），表现就是"有时闪、有时不闪"——很难查，所以计划必须按"屏"算。
library;

import 'spreads.dart';

/// 默认往前预取几屏。
const int kDefaultPreloadAhead = 2;

/// 默认往后预取几屏（翻回去也常见，但优先级低于往前）。
const int kDefaultPreloadBehind = 1;

/// 第 [pageIndex] 页所在屏的前后若干屏，包含哪些 **0 基**页索引。
///
/// [spreads] 是双页模式的 `buildSpreads` 结果；单页/纵向模式传空，
/// 此时每页各自成一屏。
///
/// 返回顺序 = 预取优先级：越近的屏越靠前。调用方按顺序发请求，
/// 忙不过来时丢掉的是"更远的那几页"，保证最该先到的那一页先出发。
List<int> preloadPlan({
  required int pageIndex,
  required int pageCount,
  List<List<int>> spreads = const <List<int>>[],
  int ahead = kDefaultPreloadAhead,
  int behind = kDefaultPreloadBehind,
}) {
  if (pageCount <= 0 || pageIndex < 0 || pageIndex >= pageCount) {
    return const <int>[];
  }
  final screens = spreads.isEmpty
      ? <List<int>>[
          for (var i = 0; i < pageCount; i++) <int>[i],
        ]
      : spreads;
  final current = spreadIndexOf(screens, pageIndex);
  if (current < 0) return const <int>[];

  final plan = <int>[];
  void add(List<int> screen) {
    for (final page in screen) {
      if (page < 0 || page >= pageCount || plan.contains(page)) continue;
      plan.add(page);
    }
  }

  for (var step = 1; step <= ahead; step++) {
    final index = current + step;
    if (index < screens.length) add(screens[index]);
  }
  for (var step = 1; step <= behind; step++) {
    final index = current - step;
    if (index >= 0) add(screens[index]);
  }
  return List<int>.unmodifiable(plan);
}
