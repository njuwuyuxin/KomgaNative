import 'package:komga_design_system/komga_design_system.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读器的配色。
///
/// 为什么不用 `Theme.of(context)`：阅读区要看的是**内容**，不是导航 chrome。
/// 普通设备上黑底白字最不抢画面；墨水屏上黑底会触发整屏全刷（还费电），
/// 必须反过来用白底黑字。这套值只有两套，显式列出来比从主题推导更可预期。
class ReaderPalette {
  const ReaderPalette({
    required this.background,
    required this.foreground,
    required this.muted,
    required this.outline,
  });

  /// 普通设备：黑底。
  static const ReaderPalette dark = ReaderPalette(
    background: Color(0xFF000000),
    foreground: Color(0xFFFFFFFF),
    muted: Color(0xB3FFFFFF),
    outline: Color(0x33FFFFFF),
  );

  /// 墨水屏：白底黑字（与 `AppTheme.eink` 的纸色一致）。
  static const ReaderPalette eink = ReaderPalette(
    background: AppTheme.einkPaper,
    foreground: AppTheme.einkInk,
    muted: AppTheme.einkMuted,
    outline: Color(0x33000000),
  );

  final Color background;
  final Color foreground;
  final Color muted;
  final Color outline;

  static ReaderPalette of({required bool isEink}) => isEink ? eink : dark;

  bool get isLight => background.computeLuminance() > 0.5;
}
