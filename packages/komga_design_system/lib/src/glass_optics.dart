import 'package:material_ui/material_ui.dart';

/// 液态玻璃的光学参数（iOS 26 Liquid Glass 的合成近似）。
///
/// 一块液态玻璃由五层叠成，这里每层一个参数：
/// 1. **饱和**（[saturation]）：背后的模糊结果提饱和，颜色"透出来"而不是发灰；
/// 2. **边缘折射**（[refraction] / [refractionBand]）：靠外缘的一圈环带把
///    玻璃**外面**的内容拉进来（像透过厚玻璃侧面看），中间区域不动；
/// 3. **内缘聚光**（[rimLight] / [rimWidth]）：厚玻璃边缘把光聚在内侧的一圈柔光；
/// 4. **镜面高光边**（[specular] / [specularWidth]）：沿外轮廓一条细亮线，亮度随
///    方向变化——光从左上来：左上最亮，右下有一道反射，另外两侧暗；
/// 5. **轮廓**（[contour]）：浅色背景上靠它和阴影把玻璃"托"出来。
///
/// 只属于彩色主题的玻璃档（`AppMaterialKind.bar`）；墨水屏永远是 null。
@immutable
class GlassOptics {
  const GlassOptics({
    required this.saturation,
    required this.refraction,
    required this.refractionBand,
    required this.rimLight,
    required this.rimWidth,
    required this.specular,
    required this.specularWidth,
    required this.selectionFill,
    required this.shader,
    this.contour,
  });

  /// 着色器版（Impeller 真机）的参数；合成版不用。
  final LiquidShaderParams shader;

  /// 玻璃里"选中项"那块嵌入胶囊的底色（中性灰/白，不染主色——
  /// iOS 26 的 tab bar 选中项是玻璃里再嵌一块亮玻璃，不是一块彩色塑料）。
  final Color selectionFill;

  /// 背后模糊结果的饱和度倍数；1 = 不变。
  final double saturation;

  /// 外缘处"拉进来"的距离（逻辑像素）：外缘那一像素显示的是玻璃外这么远的内容。
  /// 0 = 不折射。
  final double refraction;

  /// 折射环带的宽度（逻辑像素）：环带以内的内容不动。
  final double refractionBand;

  /// 内缘聚光的颜色（带透明度）。
  final Color rimLight;

  /// 内缘聚光向内渗透的距离（逻辑像素）。
  final double rimWidth;

  /// 镜面高光边沿方向的颜色：从正右（0°）开始**顺时针**每 45° 一个，
  /// 共 [specularStops] 个，首尾相同（闭环）。
  final List<Color> specular;

  /// 镜面高光边的线宽（逻辑像素）。
  final double specularWidth;

  /// 外轮廓线颜色；null = 不画。
  final Color? contour;

  /// [specular] 的长度：8 个方向 + 回到起点。
  static const int specularStops = 9;

  bool get refracts => refraction > 0 && refractionBand > 0;

  /// 浅色：背景多是白/浅色，高光要亮、轮廓要有一丝暗线才托得住。
  static const GlassOptics light = GlassOptics(
    saturation: 1.8,
    refraction: 10,
    refractionBand: 14,
    rimLight: Color(0x66FFFFFF),
    rimWidth: 6,
    specular: <Color>[
      Color(0x40FFFFFF), // 右
      Color(0x8CFFFFFF), // 右下：反射
      Color(0x1FFFFFFF), // 下
      Color(0x0FFFFFFF), // 左下
      Color(0x59FFFFFF), // 左
      Color(0xE6FFFFFF), // 左上：主光
      Color(0x80FFFFFF), // 上
      Color(0x26FFFFFF), // 右上
      Color(0x40FFFFFF), // 回到右
    ],
    specularWidth: 1.2,
    selectionFill: Color(0x14000000),
    shader: LiquidShaderParams.light,
    contour: Color(0x14000000),
  );

  /// 深色：高光收着点（暗底上白线很抢眼），轮廓用更深的黑线压边。
  static const GlassOptics dark = GlassOptics(
    saturation: 1.6,
    refraction: 10,
    refractionBand: 14,
    rimLight: Color(0x1FFFFFFF),
    rimWidth: 6,
    specular: <Color>[
      Color(0x1FFFFFFF),
      Color(0x59FFFFFF),
      Color(0x0FFFFFFF),
      Color(0x08FFFFFF),
      Color(0x33FFFFFF),
      Color(0x99FFFFFF),
      Color(0x4DFFFFFF),
      Color(0x14FFFFFF),
      Color(0x1FFFFFFF),
    ],
    specularWidth: 1.2,
    selectionFill: Color(0x24FFFFFF),
    shader: LiquidShaderParams.dark,
    contour: Color(0x52000000),
  );

  /// 饱和度色彩矩阵（`ColorFilter.matrix` 的 4×5 行主序）。
  ///
  /// 亮度权重取 Rec.709（与 sRGB 一致）：s = 1 是单位矩阵，s = 0 是灰度。
  static List<double> saturationMatrix(double s) {
    const lr = 0.2126;
    const lg = 0.7152;
    const lb = 0.0722;
    final inv = 1 - s;
    return <double>[
      lr * inv + s, lg * inv, lb * inv, 0, 0, //
      lr * inv, lg * inv + s, lb * inv, 0, 0, //
      lr * inv, lg * inv, lb * inv + s, 0, 0, //
      0, 0, 0, 1, 0,
    ];
  }
}

/// 着色器版液态玻璃（`shaders/liquid_glass.frag`）的参数，长度单位是逻辑像素。
///
/// 与合成版最大的区别：iOS 的液态玻璃**几乎不模糊**——背后的内容清晰可辨，
/// "玻璃感"来自外缘斜面把背景弯折（[refraction] / [bezel]）、边缘的彩色色散
/// （[chromaticAberration]）和沿轮廓随光向变化的高光（[specular]）。
@immutable
class LiquidShaderParams {
  const LiquidShaderParams({
    required this.blurSigma,
    required this.bezel,
    required this.refraction,
    required this.chromaticAberration,
    required this.saturation,
    required this.brightness,
    required this.tint,
    required this.specular,
    required this.rimWidth,
    required this.glow,
  });

  /// 着色器里的轻模糊半径（iOS 的 regular glass 只糊一点，让文字不跟背景打架）。
  final double blurSigma;

  /// 斜面宽度：折射只发生在外缘这一圈，中间是平的、不变形。
  final double bezel;

  /// 外缘处最大的折射位移。
  final double refraction;

  /// RGB 色散：红/蓝通道相对位移多走 / 少走的比例。
  final double chromaticAberration;

  final double saturation;

  /// 整体提亮（加到 0..1 的颜色上）。
  final double brightness;

  /// 底色：rgb + 混合比例（alpha）。
  final Color tint;

  /// 镜面高光强度（0..1）。
  final double specular;

  /// 镜面高光线宽。
  final double rimWidth;

  /// 斜面柔光强度（0..1）。
  final double glow;

  static const LiquidShaderParams light = LiquidShaderParams(
    blurSigma: 4,
    bezel: 18,
    refraction: 22,
    chromaticAberration: 0.12,
    saturation: 1.5,
    brightness: 0.04,
    tint: Color(0x85F7F7FA),
    specular: 0.85,
    rimWidth: 1.6,
    glow: 0.22,
  );

  static const LiquidShaderParams dark = LiquidShaderParams(
    blurSigma: 4,
    bezel: 18,
    refraction: 22,
    chromaticAberration: 0.12,
    saturation: 1.4,
    brightness: -0.02,
    tint: Color(0x6B141416),
    specular: 0.55,
    rimWidth: 1.6,
    glow: 0.12,
  );
}
