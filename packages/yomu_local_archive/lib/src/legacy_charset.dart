import 'dart:convert';
import 'dart:typed_data';

import 'package:yomu_local_archive/src/legacy_charset_tables.dart';

/// 可选的外部字符集解码钩子（例如平台原生 Charset 解码器）。
typedef LegacyCharsetDecoder = String? Function(Uint8List bytes);

/// 统一解码归档（ZIP / TAR）条目的原始文件名（LMB-06）。
///
/// 解码顺序：
/// 1. 显式 UTF-8 标志位或合法 UTF-8 字节流直接按 UTF-8 解码；
/// 2. 否则自动在 Shift-JIS（日文老压缩包）与 GBK（中文老压缩包）间择优真转码；
/// 3. 仍无法识别的单字节安全回退 Latin-1，永不因文件名乱码中断整包解析。
String decodeArchiveEntryName(
  Uint8List bytes, {
  required bool isUtf8,
  LegacyCharsetDecoder? fallbackDecoder,
}) {
  if (bytes.isEmpty) return '';
  if (isUtf8) {
    return utf8.decode(bytes, allowMalformed: true);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // 非 UTF-8 老压缩包进入 Shift-JIS / GBK 启发式真转码。
  }

  if (fallbackDecoder != null) {
    final external = fallbackDecoder(bytes);
    if (external != null && external.isNotEmpty) return external;
  }

  final sjis = _decodeShiftJis(bytes);
  final gbk = _decodeGbk(bytes);

  if (sjis.recognized == 0 && gbk.recognized == 0) {
    return latin1.decode(bytes);
  }
  return sjis.score >= gbk.score ? sjis.text : gbk.text;
}

/// 显式按 Shift-JIS（CP932 子集 + 假名全集 + 常见漫画汉字）解码。
String decodeShiftJisBytes(Uint8List bytes) => _decodeShiftJis(bytes).text;

/// 显式按 GBK（全角标点 + 常见漫画中文汉字）解码。
String decodeGbkBytes(Uint8List bytes) => _decodeGbk(bytes).text;

/// 将字符串编码为 GBK 字节（供中文密码双编码尝试，LMB-13）；若含未映射字符返回 `null`。
Uint8List? encodeGbkBytes(String input) {
  final out = <int>[];
  for (final rune in input.runes) {
    if (rune < 0x80) {
      out.add(rune);
      continue;
    }
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      out.add(0xA3);
      out.add(0xA1 + (rune - 0xFF01));
      continue;
    }
    final code = _gbkReverseTable[rune];
    if (code == null) return null;
    out.add((code >> 8) & 0xFF);
    out.add(code & 0xFF);
  }
  return Uint8List.fromList(out);
}

/// 将字符串编码为 Shift-JIS 字节（供日文密码双编码尝试，LMB-13）；若含未映射字符返回 `null`。
Uint8List? encodeShiftJisBytes(String input) {
  final out = <int>[];
  for (final rune in input.runes) {
    if (rune < 0x80) {
      out.add(rune);
      continue;
    }
    if (rune >= 0xFF61 && rune <= 0xFF9F) {
      out.add(0xA1 + (rune - 0xFF61));
      continue;
    }
    if (rune >= 0x3041 && rune <= 0x3093) {
      final code = 0x829F + (rune - 0x3041);
      out.add((code >> 8) & 0xFF);
      out.add(code & 0xFF);
      continue;
    }
    if (rune >= 0x30A1 && rune <= 0x30F6) {
      final delta = rune - 0x30A1;
      final code = delta < 0x3F ? (0x8340 + delta) : (0x8341 + delta);
      out.add((code >> 8) & 0xFF);
      out.add(code & 0xFF);
      continue;
    }
    final code = _sjisReverseTable[rune];
    if (code == null) return null;
    out.add((code >> 8) & 0xFF);
    out.add(code & 0xFF);
  }
  return Uint8List.fromList(out);
}

final Map<int, int> _gbkReverseTable = <int, int>{
  for (final e in gbkCommonTable.entries) e.value: e.key,
};

final Map<int, int> _sjisReverseTable = <int, int>{
  for (final e in sjisCommonTable.entries) e.value: e.key,
};

({String text, int score, int recognized}) _decodeShiftJis(Uint8List bytes) {
  final out = StringBuffer();
  var i = 0;
  var score = 0;
  var recognized = 0;

  while (i < bytes.length) {
    final b1 = bytes[i];
    if (b1 < 0x80) {
      out.writeCharCode(b1);
      i++;
      continue;
    }
    // Shift-JIS 半角片假名 0xA1..0xDF -> U+FF61..U+FF9F
    if (b1 >= 0xA1 && b1 <= 0xDF) {
      out.writeCharCode(0xFF61 + (b1 - 0xA1));
      score += 4;
      recognized++;
      i++;
      continue;
    }
    final isLead = (b1 >= 0x81 && b1 <= 0x9F) || (b1 >= 0xE0 && b1 <= 0xFC);
    if (isLead && i + 1 < bytes.length) {
      final b2 = bytes[i + 1];
      final isTrail = (b2 >= 0x40 && b2 <= 0x7E) || (b2 >= 0x80 && b2 <= 0xFC);
      if (isTrail) {
        final code = (b1 << 8) | b2;
        final mapped = _mapShiftJisDoubleByte(code);
        if (mapped != null) {
          out.writeCharCode(mapped);
          // 假名或低位尾字节 (0x40..0x7E) 是极强的 Shift-JIS 特征
          score += (b1 == 0x82 || b1 == 0x83 || b2 <= 0x7E) ? 10 : 6;
          recognized++;
        } else {
          out.writeCharCode(b1);
          out.writeCharCode(b2);
          score -= 2;
        }
        i += 2;
        continue;
      }
    }
    out.writeCharCode(b1);
    score -= 4;
    i++;
  }
  return (text: out.toString(), score: score, recognized: recognized);
}

({String text, int score, int recognized}) _decodeGbk(Uint8List bytes) {
  final out = StringBuffer();
  var i = 0;
  var score = 0;
  var recognized = 0;

  while (i < bytes.length) {
    final b1 = bytes[i];
    if (b1 < 0x80) {
      out.writeCharCode(b1);
      i++;
      continue;
    }
    if (b1 >= 0x81 && b1 <= 0xFE && i + 1 < bytes.length) {
      final b2 = bytes[i + 1];
      if (b2 >= 0x40 && b2 <= 0xFE && b2 != 0x7F) {
        final code = (b1 << 8) | b2;
        final mapped = _mapGbkDoubleByte(code);
        if (mapped != null) {
          out.writeCharCode(mapped);
          score += (b1 >= 0xB0 && b2 >= 0xA1) ? 8 : 6;
          recognized++;
        } else {
          out.writeCharCode(b1);
          out.writeCharCode(b2);
          score -= 2;
        }
        i += 2;
        continue;
      }
    }
    out.writeCharCode(b1);
    score -= 4;
    i++;
  }
  return (text: out.toString(), score: score, recognized: recognized);
}

int? _mapShiftJisDoubleByte(int code) {
  // 全角数字 0-9: 0x824F..0x8258 -> U+FF10..U+FF19
  if (code >= 0x824F && code <= 0x8258) return 0xFF10 + (code - 0x824F);
  // 全角大写字母 A-Z: 0x8260..0x8279 -> U+FF21..U+FF3A
  if (code >= 0x8260 && code <= 0x8279) return 0xFF21 + (code - 0x8260);
  // 全角小写字母 a-z: 0x8281..0x829A -> U+FF41..U+FF5A
  if (code >= 0x8281 && code <= 0x829A) return 0xFF41 + (code - 0x8281);
  // 平假名 ぁ..ん: 0x829F..0x82F1 -> U+3041..U+3093
  if (code >= 0x829F && code <= 0x82F1) return 0x3041 + (code - 0x829F);
  // 片假名 ァ..ヶ: 0x8340..0x8396（跳过 0x837F）-> U+30A1..U+30F6
  if (code >= 0x8340 && code <= 0x837E) return 0x30A1 + (code - 0x8340);
  if (code >= 0x8380 && code <= 0x8396) return 0x30A1 + (code - 0x8341);
  return sjisCommonTable[code];
}

int? _mapGbkDoubleByte(int code) {
  // GBK 全角 ASCII 0xA3A1..0xA3FE -> U+FF01..U+FF5E
  if (code >= 0xA3A1 && code <= 0xA3FE) return 0xFF01 + (code - 0xA3A1);
  return gbkCommonTable[code];
}
