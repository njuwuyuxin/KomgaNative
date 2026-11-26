/// 自然文件名排序与漫画图片条目过滤。
library;

const Map<String, String> _imageExtensionsToMime = <String, String>{
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
  '.bmp': 'image/bmp',
  '.avif': 'image/avif',
  '.heic': 'image/heic',
  '.heif': 'image/heif',
};

/// 判断归档条目或相对路径是否为有效的漫画页图（自动剔除 macOS/Windows 垃圾文件）。
bool isSupportedComicImagePath(String rawPath) {
  final normalized = rawPath.replaceAll(r'\', '/').trim();
  if (normalized.isEmpty || normalized.endsWith('/')) return false;

  final segments = normalized.split('/');
  for (final seg in segments) {
    if (seg.isEmpty) continue;
    if (seg == '__MACOSX') return false;
    // 过滤 `.DS_Store`、`._001.jpg` AppleDouble 资源分支、`.nomedia` 等隐藏项。
    if (seg.startsWith('.')) return false;
  }

  final fileName = segments.last.toLowerCase();
  if (fileName == 'thumbs.db' || fileName == 'desktop.ini') return false;
  return mediaTypeForPath(fileName) != null;
}

/// 根据路径后缀推导标准 MIME 类型；不支持的图片扩展名返回 `null`。
String? mediaTypeForPath(String path) {
  final lower = path.toLowerCase();
  final dot = lower.lastIndexOf('.');
  if (dot < 0) return null;
  return _imageExtensionsToMime[lower.substring(dot)];
}

/// 跨平台确定性的路径自然排序：
/// 1. 先按 `/` 分段逐级比较目录与文件名（确保 `ch2/01.jpg < ch10/01.jpg`）；
/// 2. 同一段内连续数字按数值大小比较（`2 < 10 < 100`），前导零较短或较长做稳定决胜；
/// 3. 文本段先忽略大小写比较，相等时再按原始码点决胜以保证全序确定性。
int naturalCompare(String a, String b) {
  if (a == b) return 0;
  final segA = a.replaceAll(r'\', '/').split('/');
  final segB = b.replaceAll(r'\', '/').split('/');
  final minSegs = segA.length < segB.length ? segA.length : segB.length;
  for (var i = 0; i < minSegs; i++) {
    final cmp = _compareSegment(segA[i], segB[i]);
    if (cmp != 0) return cmp;
  }
  return segA.length.compareTo(segB.length);
}

int _compareSegment(String a, String b) {
  if (a == b) return 0;
  var ia = 0;
  var ib = 0;
  while (ia < a.length && ib < b.length) {
    final ca = a.codeUnitAt(ia);
    final cb = b.codeUnitAt(ib);
    final da = _isAsciiDigit(ca);
    final db = _isAsciiDigit(cb);

    if (da && db) {
      final endA = _scanDigits(a, ia);
      final endB = _scanDigits(b, ib);
      final numCmp = _compareDigitSlices(a, ia, endA, b, ib, endB);
      if (numCmp != 0) return numCmp;
      ia = endA;
      ib = endB;
      continue;
    }

    final lowerA = _toAsciiLower(ca);
    final lowerB = _toAsciiLower(cb);
    if (lowerA != lowerB) return lowerA.compareTo(lowerB);
    ia++;
    ib++;
  }
  if (ia != a.length || ib != b.length) {
    return (a.length - ia).compareTo(b.length - ib);
  }
  // 忽略大小写完全一致时，用原始字符串做确定性决胜。
  return a.compareTo(b);
}

bool _isAsciiDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

int _toAsciiLower(int codeUnit) =>
    (codeUnit >= 0x41 && codeUnit <= 0x5A) ? (codeUnit + 32) : codeUnit;

int _scanDigits(String s, int start) {
  var i = start;
  while (i < s.length && _isAsciiDigit(s.codeUnitAt(i))) {
    i++;
  }
  return i;
}

int _compareDigitSlices(
  String a,
  int startA,
  int endA,
  String b,
  int startB,
  int endB,
) {
  var nzA = startA;
  while (nzA < endA && a.codeUnitAt(nzA) == 0x30) {
    nzA++;
  }
  var nzB = startB;
  while (nzB < endB && b.codeUnitAt(nzB) == 0x30) {
    nzB++;
  }

  final sigLenA = endA - nzA;
  final sigLenB = endB - nzB;
  if (sigLenA != sigLenB) return sigLenA.compareTo(sigLenB);

  for (var i = 0; i < sigLenA; i++) {
    final diff = a.codeUnitAt(nzA + i).compareTo(b.codeUnitAt(nzB + i));
    if (diff != 0) return diff;
  }

  // 数值完全相同（如 `02` 与 `2`）：总位数不同时按原始长度稳定排序。
  return (endA - startA).compareTo(endB - startB);
}
