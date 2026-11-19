/// 点击区预设（RDR-07）。
///
/// 五种预设对应不同阅读习惯：有人喜欢"左右三分之一翻页"，有人习惯 Kindle 那种
/// 大半屏都算翻页，还有人只怕误触、只要最外侧一条边。
enum TapZonePreset {
  /// 自动：竖屏用左-右，横屏/宽屏用 L 形（单手更容易够到右下角）。
  automatic,

  /// 左-右：左 1/3 上一页、右 1/3 下一页、中间切 chrome。
  leftRight,

  /// L 形：左列上一页、右下角区域下一页（拇指自然落点）。
  lShaped,

  /// Kindle：左 40% / 右 40% 翻页，中间 20% 留给 chrome。
  kindle,

  /// 边缘：只有最外侧各 15% 翻页，其余全部是 chrome。
  edge,
}

/// 一次点击应该做什么。
enum TapZoneAction { previous, next, toggleChrome }

/// 解析点击落在哪个区（纯函数，单测直接钉住）。
///
/// [dx]/[dy] 是相对视口的坐标；[rightToLeft] 与 [inverted] 都只**交换前后页**，
/// 不改变"哪块区域是翻页区"——否则反转会连 chrome 区一起挪走，很难解释。
TapZoneAction resolveTapZone({
  required TapZonePreset preset,
  required double dx,
  required double dy,
  required double width,
  required double height,
  bool rightToLeft = false,
  bool inverted = false,
}) {
  if (width <= 0 || height <= 0) return TapZoneAction.toggleChrome;
  final x = (dx / width).clamp(0.0, 1.0);
  final y = (dy / height).clamp(0.0, 1.0);

  // 自动：竖屏（高 ≥ 宽）按左-右，横屏按 L 形。
  final effective = preset == TapZonePreset.automatic
      ? (height >= width ? TapZonePreset.leftRight : TapZonePreset.lShaped)
      : preset;

  TapZoneAction? turned;
  switch (effective) {
    case TapZonePreset.leftRight:
      if (x < 0.33) turned = TapZoneAction.previous;
      if (x > 0.67) turned = TapZoneAction.next;
    case TapZonePreset.lShaped:
      if (x < 0.3) {
        turned = TapZoneAction.previous;
      } else if (x >= 0.6 && y >= 0.5) {
        turned = TapZoneAction.next;
      }
    case TapZonePreset.kindle:
      if (x < 0.4) turned = TapZoneAction.previous;
      if (x > 0.6) turned = TapZoneAction.next;
    case TapZonePreset.edge:
      if (x < 0.15) turned = TapZoneAction.previous;
      if (x > 0.85) turned = TapZoneAction.next;
    case TapZonePreset.automatic:
      // 上面已经折算过，走不到这里。
      break;
  }

  if (turned == null) return TapZoneAction.toggleChrome;
  // 日漫从右往左：左右语义整体镜像；`inverted` 再在用户层面翻一次。
  final mirrored = rightToLeft != inverted;
  if (!mirrored) return turned;
  return turned == TapZoneAction.next
      ? TapZoneAction.previous
      : TapZoneAction.next;
}
