import 'dart:async';

import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读器底部的页码滑杆（RDR-01）。
///
/// 为什么值得单独做：几百页的书里，"第 12 / 214 页"只是一个数字，用户没法
/// 快速跳到一个大致位置；滑杆既能一眼看出"读了多少"，也能拖到任意处。
///
/// 两个细节：
/// - **RTL 时方向要反过来**：日漫从右往左读，滑杆的左端才是"书末"，
///   否则拖动方向和阅读方向相反，很别扭；
/// - 拖动时用本地 `_drag` 值，不依赖父级回传：父级每次跳页都会重建，
///   直接用 `widget.page` 会让滑块在手指下抖。
class ReaderPageSlider extends StatefulWidget {
  const ReaderPageSlider({
    required this.page,
    required this.total,
    required this.palette,
    required this.rightToLeft,
    required this.onJump,
    super.key,
  });

  /// 1 基当前页。
  final int page;
  final int total;
  final ReaderPalette palette;
  final bool rightToLeft;
  final ValueChanged<int> onJump;

  @override
  State<ReaderPageSlider> createState() => _ReaderPageSliderState();
}

class _ReaderPageSliderState extends State<ReaderPageSlider> {
  /// 拖动中的值；松手清空，回到"跟着当前页走"。
  double? _drag;
  int? _lastSent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final total = widget.total;
    if (total <= 1) return const SizedBox.shrink();
    final page = widget.page.clamp(1, total);
    final value = (_drag ?? page.toDouble())
        .clamp(1, total.toDouble())
        .toDouble();

    return Semantics(
      key: const Key('reader-page-slider-semantics'),
      label: l10n.readerSliderLabel(page, total),
      child: Directionality(
        // RTL 漫画：把最小值放到右边，拖动方向与阅读方向一致。
        textDirection: widget.rightToLeft
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: Slider(
          key: const Key('reader-page-slider'),
          value: value,
          min: 1,
          max: total.toDouble(),
          activeColor: widget.palette.foreground,
          inactiveColor: widget.palette.outline,
          onChanged: (double next) {
            final target = next.round();
            setState(() => _drag = next);
            // 只在跨到另一页时跳 + 震一下：逐像素回调会让进度写入和触感都爆炸。
            if (target == _lastSent) return;
            _lastSent = target;
            unawaited(AppHaptics.selection());
            widget.onJump(target);
          },
          onChangeEnd: (_) {
            _lastSent = null;
            setState(() => _drag = null);
          },
        ),
      ),
    );
  }
}
