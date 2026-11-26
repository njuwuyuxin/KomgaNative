import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu_reader/yomu_reader.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读器的配色。
///
/// 为什么不用 `Theme.of(context)`：阅读区要看的是**内容**，不是导航 chrome。
/// 普通设备上黑底白字最不抢画面；墨水屏上黑底会触发整屏全刷（还费电），
/// 必须反过来用白底黑字。
///
/// 两个颜色域要分清（UI-P1-5 之后背景可以是白/动态色）：
/// - [foreground] / [muted] / [outline]：**chrome**（顶栏、底栏、面板）上的颜色。
///   普通设备的 chrome 永远是深色毛玻璃，所以这里永远是白色；
/// - [onBackground] / [onBackgroundMuted]：直接画在阅读区底色上的文字
///   （错误页、加载态）。它跟着 [background] 的亮度走，白底上就是黑字。
class ReaderPalette {
  const ReaderPalette({
    required this.background,
    required this.foreground,
    required this.muted,
    required this.outline,
    required this.isEink,
    this.gradient,
  });

  /// 普通设备：黑底。
  static const ReaderPalette dark = ReaderPalette(
    background: Color(0xFF000000),
    foreground: Color(0xFFFFFFFF),
    muted: Color(0xB3FFFFFF),
    outline: Color(0x33FFFFFF),
    isEink: false,
  );

  /// 墨水屏：白底黑字（与 `AppTheme.eink` 的纸色一致）。
  static const ReaderPalette eink = ReaderPalette(
    background: AppTheme.einkPaper,
    foreground: AppTheme.einkInk,
    muted: AppTheme.einkMuted,
    outline: Color(0x33000000),
    isEink: true,
  );

  /// 普通设备的白底（"白色"背景选项）。
  ///
  /// 注意 [foreground] 还是白色：chrome 压在深色毛玻璃上，白底只是**阅读区**的底色。
  static const ReaderPalette white = ReaderPalette(
    background: Color(0xFFFFFFFF),
    foreground: Color(0xFFFFFFFF),
    muted: Color(0xB3FFFFFF),
    outline: Color(0x33FFFFFF),
    isEink: false,
  );

  final Color background;
  final Color foreground;
  final Color muted;
  final Color outline;

  /// 沉浸式背景的渐变（UI-P3-7）；null 时用 [background] 纯色。
  final List<Color>? gradient;

  /// 是否走墨水屏配色。**不读主题**：阅读器的深浅由设置项的"强制墨水屏"决定，
  /// 与本机主题可以不一致。
  final bool isEink;

  static ReaderPalette of({required bool isEink}) => isEink ? eink : dark;

  /// 按设置解析配色。
  ///
  /// 墨水屏固定纸色（黑底会触发整屏全刷）；[RgbColor] 还没算出来时退回黑色，
  /// 等算完再由下一帧换成动态色——不会先闪一帧奇怪的颜色。
  static ReaderPalette resolve({
    required bool isEink,
    required ReaderBackgroundChoice choice,
    RgbColor? dynamic,
    List<RgbColor>? immersive,
  }) {
    if (isEink) return eink;
    return switch (choice) {
      ReaderBackgroundChoice.black => dark,
      ReaderBackgroundChoice.white => white,
      ReaderBackgroundChoice.dynamic =>
        dynamic == null
            ? dark
            : ReaderPalette._withBackground(
                Color.fromARGB(255, dynamic.r, dynamic.g, dynamic.b),
              ),
      ReaderBackgroundChoice.immersive =>
        immersive == null || immersive.isEmpty
            ? dark
            : ReaderPalette._withGradient(immersive),
    };
  }

  /// 只换底色：chrome 颜色保持普通设备的白字。
  const ReaderPalette._withBackground(this.background)
    : foreground = const Color(0xFFFFFFFF),
      muted = const Color(0xB3FFFFFF),
      outline = const Color(0x33FFFFFF),
      isEink = false,
      gradient = null;

  /// 沉浸式：底色取左右色的平均，渐变用两侧原色（起点左上、终点右下）。
  factory ReaderPalette._withGradient(List<RgbColor> colors) {
    final rgb = colors
        .map((RgbColor c) => Color.fromARGB(255, c.r, c.g, c.b))
        .toList(growable: false);
    final avg = averageColors(colors);
    return ReaderPalette(
      background: avg == null
          ? const Color(0xFF000000)
          : Color.fromARGB(255, avg.r, avg.g, avg.b),
      foreground: const Color(0xFFFFFFFF),
      muted: const Color(0xB3FFFFFF),
      outline: const Color(0x33FFFFFF),
      isEink: false,
      gradient: rgb.length >= 2 ? rgb : <Color>[rgb.first, rgb.first],
    );
  }

  bool get isLight => background.computeLuminance() > 0.5;

  /// 直接画在 [background] 上的文字色（错误页、加载态）。
  Color get onBackground =>
      isLight ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);

  Color get onBackgroundMuted => onBackground.withValues(alpha: 0.7);

  /// 阅读器 chrome（顶栏 / 底栏 / 书末卡片）的材质。
  ///
  /// 普通设备永远用深色毛玻璃：chrome 压在漫画画面上，与系统深浅色无关
  /// （iOS 相册、图书都是这么做的）。墨水屏退化成不透明纸色 + 墨色描边。
  AppMaterial get chromeMaterial =>
      AppMaterial.resolve(AppMaterialKind.chrome, eink: isEink, dark: true);
}
