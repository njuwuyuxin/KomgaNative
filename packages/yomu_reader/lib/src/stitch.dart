import 'geometry.dart';
import 'layout.dart';
import 'spreads.dart';

/// 拼接大图的最大边长上限（移动 GPU 纹理安全上界）。
const int kDefaultMaxStitchDimension = 8192;

/// 从图片文件头识别出的扩展名与 MIME 类型。
class ImageFileFormat {
  const ImageFileFormat({required this.extension, required this.mimeType});

  static const ImageFileFormat png = ImageFileFormat(
    extension: 'png',
    mimeType: 'image/png',
  );
  static const ImageFileFormat jpeg = ImageFileFormat(
    extension: 'jpg',
    mimeType: 'image/jpeg',
  );
  static const ImageFileFormat webp = ImageFileFormat(
    extension: 'webp',
    mimeType: 'image/webp',
  );
  static const ImageFileFormat gif = ImageFileFormat(
    extension: 'gif',
    mimeType: 'image/gif',
  );
  static const ImageFileFormat avif = ImageFileFormat(
    extension: 'avif',
    mimeType: 'image/avif',
  );

  final String extension;
  final String mimeType;

  @override
  bool operator ==(Object other) =>
      other is ImageFileFormat &&
      other.extension == extension &&
      other.mimeType == mimeType;

  @override
  int get hashCode => Object.hash(extension, mimeType);
}

/// 按魔数嗅探单页图片的真实编码格式；无法识别时兜底为 PNG。
ImageFileFormat sniffImageFormat(List<int> bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return ImageFileFormat.png;
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return ImageFileFormat.jpeg;
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38) {
    return ImageFileFormat.gif;
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return ImageFileFormat.webp;
  }
  if (bytes.length >= 12 &&
      bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70 &&
      bytes[8] == 0x61 &&
      bytes[9] == 0x76 &&
      bytes[10] == 0x69 &&
      (bytes[11] == 0x66 || bytes[11] == 0x73)) {
    return ImageFileFormat.avif;
  }
  return ImageFileFormat.png;
}

/// 双页横向拼接的目标画布尺寸与左右页落位矩形。
class StitchLayout {
  const StitchLayout({
    required this.width,
    required this.height,
    required this.left,
    required this.right,
  });

  static const StitchLayout empty = StitchLayout(
    width: 0,
    height: 0,
    left: RectD(0, 0, 0, 0),
    right: RectD(0, 0, 0, 0),
  );

  final int width;
  final int height;
  final RectD left;
  final RectD right;

  bool get isEmpty => width <= 0 || height <= 0;
}

/// 计算左右两幅图无缝横向拼接的目标几何：
/// - 等高时保持 1:1 原始像素尺寸；
/// - 不等高时按较高一侧等比对齐高度，消除上下黑边且不损失高分图细节；
/// - 超出 [maxDimension] 时整体等比收拢到安全纹理上限内。
StitchLayout computeStitchLayout({
  required int leftWidth,
  required int leftHeight,
  required int rightWidth,
  required int rightHeight,
  int maxDimension = kDefaultMaxStitchDimension,
}) {
  if (leftWidth <= 0 ||
      leftHeight <= 0 ||
      rightWidth <= 0 ||
      rightHeight <= 0 ||
      maxDimension < 2) {
    return StitchLayout.empty;
  }

  final baseHeight = leftHeight > rightHeight ? leftHeight : rightHeight;
  final scaledLeftW = leftWidth * (baseHeight / leftHeight);
  final scaledRightW = rightWidth * (baseHeight / rightHeight);
  final totalWidth = scaledLeftW + scaledRightW;

  final limit = maxDimension.toDouble();
  final scaleX = totalWidth > limit ? limit / totalWidth : 1.0;
  final scaleY = baseHeight > limit ? limit / baseHeight : 1.0;
  final clampScale = scaleX < scaleY ? scaleX : scaleY;

  final height = (baseHeight * clampScale).round().clamp(1, maxDimension);
  var wLeft = (scaledLeftW * clampScale).round();
  var wRight = (scaledRightW * clampScale).round();
  if (wLeft < 1) wLeft = 1;
  if (wRight < 1) wRight = 1;
  while (wLeft + wRight > maxDimension && (wLeft > 1 || wRight > 1)) {
    if (wLeft >= wRight && wLeft > 1) {
      wLeft -= 1;
    } else if (wRight > 1) {
      wRight -= 1;
    }
  }

  return StitchLayout(
    width: wLeft + wRight,
    height: height,
    left: RectD(0, 0, wLeft.toDouble(), height.toDouble()),
    right: RectD(wLeft.toDouble(), 0, wRight.toDouble(), height.toDouble()),
  );
}

/// 解析点击"保存图片"时应当导出的 **1 基**页码序列（按屏幕从左到右视觉顺序排列）。
///
/// - 单页 / 纵向滚动：只返回 `[currentPage]`；
/// - 双页模式但当前跨页只有 1 页（单独封面、跨页宽图、末尾单页）：返回该单页；
/// - 双页模式且当前跨页有 2 页：按 [rightToLeft] 的 `visualOrder` 返回 `[左页, 右页]`
///   （LTR 为 `[p, p+1]`，RTL 日漫为 `[p+1, p]`，与屏幕上左右画面严格一致）。
List<int> resolveSavePages({
  required ReadingMode mode,
  required int currentPage,
  required List<int> spread,
  required bool rightToLeft,
}) {
  if (mode == ReadingMode.doublePage && spread.isNotEmpty) {
    final ordered = visualOrder(spread, rightToLeft: rightToLeft);
    return List<int>.unmodifiable(<int>[
      for (final index in ordered) index + 1,
    ]);
  }
  return List<int>.unmodifiable(<int>[currentPage]);
}

/// 生成安全且带页码范围的保存文件名。
String formatSavedPageFileName({
  required String bookId,
  required List<int> pages,
  required String extension,
}) {
  final sanitizedBook = bookId
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final safeBook = sanitizedBook.isEmpty ? 'book' : sanitizedBook;
  final ext = extension.trim().replaceAll('.', '');
  final safeExt = ext.isEmpty ? 'png' : ext;
  if (pages.length >= 2) {
    final a = pages[0];
    final b = pages[1];
    final low = a < b ? a : b;
    final high = a < b ? b : a;
    return 'yomu-$safeBook-pages-$low-$high.$safeExt';
  }
  final page = pages.isEmpty ? 1 : pages.first;
  return 'yomu-$safeBook-page-$page.$safeExt';
}
