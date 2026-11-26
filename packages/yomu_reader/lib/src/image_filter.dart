/// 漫画图像增强滤镜（对比度 / 去底灰漂白 / 去黄 / 灰阶）与 4×5 颜色矩阵计算（LMB-03）。
///
/// 针对老扫描漫画纸底发黄发灰、以及电子墨水屏浅灰背景触发抖动噪点的问题，
/// 通过线性黑白场拉伸与可选 BT.709 灰阶合成 GPU `ColorFilter.matrix` 20 元素矩阵，
/// 运行时零 CPU 重编码开销。
library;

/// 画面增强预设档位。
enum ReaderImageFilterPreset {
  /// 原图无增强。
  none,

  /// 墨水屏清晰增强：高对比 + 去底灰漂白 + 纯黑白灰阶，消除墨水屏灰底噪点。
  einkCrisp,

  /// 老漫去黄增黑：保留彩页色彩，同时漂白发黄纸底并加深墨线。
  vintageDeYellow,

  /// 彩漫转黑白：纯灰阶 + 轻度提亮纸白。
  grayscale,

  /// 自定义对比度、白场漂白阈值与灰阶开关。
  custom,
}

/// 不可变图像增强滤镜配置值对象。
final class ReaderImageFilter {
  const ReaderImageFilter({
    this.preset = ReaderImageFilterPreset.none,
    this.contrast = 1.0,
    this.whiteThreshold = 255,
    this.grayscale = false,
  });

  static const ReaderImageFilter none = ReaderImageFilter();

  static const ReaderImageFilter einkCrisp = ReaderImageFilter(
    preset: ReaderImageFilterPreset.einkCrisp,
    contrast: 1.35,
    whiteThreshold: 222,
    grayscale: true,
  );

  static const ReaderImageFilter vintageDeYellow = ReaderImageFilter(
    preset: ReaderImageFilterPreset.vintageDeYellow,
    contrast: 1.25,
    whiteThreshold: 226,
    grayscale: false,
  );

  static const ReaderImageFilter grayscaleOnly = ReaderImageFilter(
    preset: ReaderImageFilterPreset.grayscale,
    contrast: 1.08,
    whiteThreshold: 245,
    grayscale: true,
  );

  static const double minContrast = 1.0;
  static const double maxContrast = 2.0;
  static const int minWhiteThreshold = 180;
  static const int maxWhiteThreshold = 255;

  final ReaderImageFilterPreset preset;

  /// 对比度系数（1.0–2.0），越大黑线越沉实。
  final double contrast;

  /// 白场漂白阈值（180–255），亮度高于此值的灰/黄纸底直接漂白为纯白 255。
  final int whiteThreshold;

  /// 是否转为 BT.709 灰阶。
  final bool grayscale;

  bool get isIdentity => preset == ReaderImageFilterPreset.none;

  /// 根据预设返回实际生效的参数集合。
  ReaderImageFilter resolved() => switch (preset) {
    ReaderImageFilterPreset.none => none,
    ReaderImageFilterPreset.einkCrisp => einkCrisp,
    ReaderImageFilterPreset.vintageDeYellow => vintageDeYellow,
    ReaderImageFilterPreset.grayscale => grayscaleOnly,
    ReaderImageFilterPreset.custom => ReaderImageFilter(
      preset: ReaderImageFilterPreset.custom,
      contrast: contrast.clamp(minContrast, maxContrast),
      whiteThreshold: whiteThreshold.clamp(
        minWhiteThreshold,
        maxWhiteThreshold,
      ),
      grayscale: grayscale,
    ),
  };

  ReaderImageFilter copyWith({
    ReaderImageFilterPreset? preset,
    double? contrast,
    int? whiteThreshold,
    bool? grayscale,
  }) => ReaderImageFilter(
    preset: preset ?? this.preset,
    contrast: (contrast ?? this.contrast).clamp(minContrast, maxContrast),
    whiteThreshold: (whiteThreshold ?? this.whiteThreshold).clamp(
      minWhiteThreshold,
      maxWhiteThreshold,
    ),
    grayscale: grayscale ?? this.grayscale,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'preset': preset.name,
    'contrast': contrast,
    'whiteThreshold': whiteThreshold,
    'grayscale': grayscale,
  };

  static ReaderImageFilter fromJson(Object? raw) {
    if (raw is! Map) return none;
    final presetName = raw['preset'];
    var preset = ReaderImageFilterPreset.none;
    if (presetName is String) {
      for (final candidate in ReaderImageFilterPreset.values) {
        if (candidate.name == presetName) {
          preset = candidate;
          break;
        }
      }
    }
    final rawContrast = raw['contrast'];
    final contrast = rawContrast is num
        ? rawContrast.toDouble().clamp(minContrast, maxContrast)
        : 1.0;
    final rawWhite = raw['whiteThreshold'];
    final whiteThreshold = rawWhite is num
        ? rawWhite.round().clamp(minWhiteThreshold, maxWhiteThreshold)
        : maxWhiteThreshold;
    return ReaderImageFilter(
      preset: preset,
      contrast: contrast,
      whiteThreshold: whiteThreshold,
      grayscale: raw['grayscale'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReaderImageFilter &&
          other.preset == preset &&
          (other.contrast - contrast).abs() < 1e-6 &&
          other.whiteThreshold == whiteThreshold &&
          other.grayscale == grayscale);

  @override
  int get hashCode =>
      Object.hash(preset, (contrast * 1000).round(), whiteThreshold, grayscale);

  @override
  String toString() =>
      'ReaderImageFilter(${preset.name}, c=$contrast, w=$whiteThreshold, gray=$grayscale)';
}

/// 生成 Flutter `ColorFilter.matrix` 所需的 20 元素 4×5 颜色矩阵；
/// 无增强（`preset == none`）返回单位矩阵。
List<double> buildImageFilterMatrix(ReaderImageFilter filter) {
  if (filter.isIdentity) return _identityMatrix;
  final eff = filter.resolved();

  // 黑场锚点随对比度略微上提（压实深灰墨线），白场锚点由 whiteThreshold 决定（漂白浅灰纸底）。
  final blackPoint = ((eff.contrast - 1.0) * 55.0).clamp(0.0, 80.0);
  final whitePoint = eff.whiteThreshold
      .clamp(
        ReaderImageFilter.minWhiteThreshold,
        ReaderImageFilter.maxWhiteThreshold,
      )
      .toDouble();
  final span = (whitePoint - blackPoint).clamp(32.0, 255.0);
  final scale = 255.0 / span;
  final offset = -blackPoint * scale;

  if (eff.grayscale) {
    const wr = 0.2126;
    const wg = 0.7152;
    const wb = 0.0722;
    final r = wr * scale;
    final g = wg * scale;
    final b = wb * scale;
    return <double>[
      r, g, b, 0, offset, //
      r, g, b, 0, offset, //
      r, g, b, 0, offset, //
      0, 0, 0, 1, 0, //
    ];
  }

  // 老漫去黄模式额外把蓝色通道白场略微下调，精准中和偏黄纸底（如 RGB 240,234,212 → 255,255,255）。
  final blueWhite = eff.preset == ReaderImageFilterPreset.vintageDeYellow
      ? (whitePoint - 14.0).clamp(160.0, 255.0)
      : whitePoint;
  final blueSpan = (blueWhite - blackPoint).clamp(32.0, 255.0);
  final blueScale = 255.0 / blueSpan;
  final blueOffset = -blackPoint * blueScale;

  return <double>[
    scale, 0, 0, 0, offset, //
    0, scale, 0, 0, offset, //
    0, 0, blueScale, 0, blueOffset, //
    0, 0, 0, 1, 0, //
  ];
}

/// 纯函数：将 4×5 颜色矩阵作用到单个 8-bit RGB 像素并夹紧到 `[0, 255]`（供单测验证）。
({int r, int g, int b}) applyColorMatrixToRgb(
  List<double> matrix,
  int r,
  int g,
  int b,
) {
  int eval(int row) {
    final base = row * 5;
    final v =
        matrix[base] * r +
        matrix[base + 1] * g +
        matrix[base + 2] * b +
        matrix[base + 3] * 255.0 +
        matrix[base + 4];
    return v.round().clamp(0, 255);
  }

  return (r: eval(0), g: eval(1), b: eval(2));
}

const List<double> _identityMatrix = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0, //
];
