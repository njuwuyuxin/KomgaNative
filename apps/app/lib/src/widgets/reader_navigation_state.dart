import 'package:flutter/services.dart' show KeyEvent;
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/widgets/reader_content_viewport.dart';
import 'package:yomu/src/widgets/reader_layout.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_reader/yomu_reader.dart';

/// 翻页指令的执行结果（供外层编排决定更新页码还是切换下一本）。
sealed class ReaderTurnOutcome {
  const ReaderTurnOutcome();
}

final class ReaderTurnNone extends ReaderTurnOutcome {
  const ReaderTurnNone();
}

final class ReaderTurnMoved extends ReaderTurnOutcome {
  const ReaderTurnMoved({required this.page, this.half});

  final int page;
  final PageHalf? half;
}

final class ReaderTurnOpenNextBook extends ReaderTurnOutcome {
  const ReaderTurnOpenNextBook();
}

/// 阅读器页码、视口形态、方向、宽页切分半幅、临时合页与 Chrome 可见性的内聚状态机（P3-1）。
///
/// 纯状态对象（无 `BuildContext` / `Widget` 依赖），便于直接单元测试翻页、模式推导与键盘映射。
class ReaderNavigationState {
  /// 1 基当前页；0 表示尚未主动翻页，此时使用已保存的阅读进度恢复位置。
  int page = 0;

  /// 宽页自动切分时的当前半幅；null 表示进入该物理页的首个阅读半幅。
  PageHalf? pageHalf;

  /// 用户点击「合页查看」后临时合并展示整张宽图的 0 基物理页索引；翻离该页自动清空。
  int? mergedWidePageIndex;

  bool chromeVisible = true;
  bool landscape = false;
  bool tablet = false;
  ReadingDirection direction = ReadingDirection.unknown;
  int jumpToken = 0;
  int jumpPage = 1;

  /// 结合当前横竖屏、设备形态与阅读方向解析实际阅读模式。
  ReadingMode resolveMode({
    required ReaderPrefs prefs,
    required ReaderConfig config,
  }) => resolveReaderMode(
    mode: config.mode,
    tabletLayout: prefs.tabletLayout,
    direction: direction,
    landscape: landscape,
    tablet: tablet,
  );

  /// 计算当前有效 1 基页码。
  int resolvePage({required int total, required int? resumedPage}) {
    if (total <= 0) return 1;
    if (page > 0) return page.clamp(1, total);
    return (resumedPage ?? 1).clamp(1, total);
  }

  /// 基于当前导航状态构造这一屏的 [ReaderLayout]。
  ReaderLayout buildLayout({
    required List<PageInfo> pages,
    required TabletLayoutChoice tabletLayout,
    required ReaderConfig config,
    required int? resumedPage,
    required int? groupFrom,
  }) {
    final mode = resolveReaderMode(
      mode: config.mode,
      tabletLayout: tabletLayout,
      direction: direction,
      landscape: landscape,
      tablet: tablet,
    );
    return ReaderLayout(
      pages: pages,
      mode: mode,
      page: resolvePage(total: pages.length, resumedPage: resumedPage),
      groupFrom: groupFrom,
      splitWidePages: config.splitWidePages.isActive(
        mode: mode,
        landscape: landscape,
      ),
      rightToLeft: config.direction.resolveRightToLeft(direction),
      currentHalf: pageHalf,
      mergedWidePageIndex: mergedWidePageIndex,
    );
  }

  /// 将键盘事件按当前阅读方向映射为语义动作。
  ReaderKeyAction? resolveKeyEvent(KeyEvent event, ReaderConfig config) =>
      resolveReaderKeyAction(
        event,
        rightToLeft: config.direction.resolveRightToLeft(direction),
      );

  /// 切换当前页码与半幅；返回是否真正发生变化。
  bool setPage(int nextPage, {PageHalf? half}) {
    if (nextPage == page && half == pageHalf) return false;
    if (nextPage != page && mergedWidePageIndex != nextPage - 1) {
      mergedWidePageIndex = null;
    }
    page = nextPage;
    pageHalf = half;
    return true;
  }

  /// 跳到指定页（同步递增纵向滚动用的 [jumpToken]），返回钳制后的 1 基目标页码。
  int jumpTo(int targetPage, int total) {
    final target = targetPage.clamp(1, total);
    page = target;
    pageHalf = null;
    mergedWidePageIndex = null;
    jumpPage = target;
    jumpToken++;
    return target;
  }

  /// 切换指定物理页（0 基）的临时合页状态。
  void toggleTempMerge(int pageIndex) {
    mergedWidePageIndex = mergedWidePageIndex == pageIndex ? null : pageIndex;
    pageHalf = null;
  }

  /// 切换上下工具栏显示/隐藏。
  void toggleChrome() {
    chromeVisible = !chromeVisible;
  }

  /// 计算单页/双页/宽页切分模式下翻页 [delta] 后的结果并就地更新导航状态。
  ReaderTurnOutcome handlePagedTurn({
    required ReaderLayout layout,
    required int delta,
    required bool hasNextBook,
  }) {
    if (layout.isWideSplitActive) {
      final split = layout.turnSplitTarget(delta);
      if (split != null) {
        final changed = setPage(split.pageNumber, half: split.half);
        return changed
            ? ReaderTurnMoved(page: split.pageNumber, half: split.half)
            : const ReaderTurnNone();
      }
      return delta > 0 && hasNextBook
          ? const ReaderTurnOpenNextBook()
          : const ReaderTurnNone();
    }
    final target = layout.turnTarget(delta);
    if (target != null) {
      final changed = setPage(target);
      return changed ? ReaderTurnMoved(page: target) : const ReaderTurnNone();
    }
    return delta > 0 && hasNextBook
        ? const ReaderTurnOpenNextBook()
        : const ReaderTurnNone();
  }
}
