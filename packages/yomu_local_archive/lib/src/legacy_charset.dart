import 'dart:convert';
import 'dart:typed_data';

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
  return _sjisCommonTable[code];
}

int? _mapGbkDoubleByte(int code) {
  // GBK 全角 ASCII 0xA3A1..0xA3FE -> U+FF01..U+FF5E
  if (code >= 0xA3A1 && code <= 0xA3FE) return 0xFF01 + (code - 0xA3A1);
  return _gbkCommonTable[code];
}

/// 高频漫画/同人志/分卷命名 Shift-JIS 符号与汉字映射表。
const Map<int, int> _sjisCommonTable = <int, int>{
  0x8140: 0x3000, //
  0x8141: 0x3001, // 、
  0x8142: 0x3002, // 。
  0x8145: 0x30FB, // ・
  0x815B: 0x30FC, // ー
  0x8169: 0xFF08, // （
  0x816A: 0xFF09, // ）
  0x816D: 0xFF3B, // ［
  0x816E: 0xFF3D, // ］
  0x8175: 0x300C, // 「
  0x8176: 0x300D, // 」
  0x8177: 0x300E, // 『
  0x8178: 0x300F, // 』
  0x8179: 0x3010, // 【
  0x817A: 0x3011, // 】
  0x91E6: 0x7B2C, // 第
  0x8AAA: 0x5DFB, // 巻
  0x9862: 0x8A71, // 話
  0x8FCD: 0x7AE0, // 章
  0x8F57: 0x96C6, // 集
  0x8DFB: 0x518A, // 冊
  0x89F1: 0x56DE, // 回
  0x9594: 0x90E8, // 部
  0x95D2: 0x7BC7, // 篇
  0x95D4: 0x7DE8, // 編
  0x94D4: 0x756A, // 番
  0x8A4F: 0x5916, // 外
  0x93C1: 0x7279, // 特
  0x9354: 0x5178, // 典
  0x95CA: 0x5225, // 別
  0x8AAE: 0x5B8C, // 完
  0x8C8B: 0x7D50, // 結
  0x9153: 0x5168, // 全
  0x8FE3: 0x4E0A, // 上
  0x9286: 0x4E2D, // 中
  0x89BA: 0x4E0B, // 下
  0x914F: 0x524D, // 前
  0x8CE3: 0x5F8C, // 後
  0x9056: 0x65B0, // 新
  0x94C5: 0x7248, // 版
  0x969F: 0x6F2B, // 漫
  0x89E6: 0x753B, // 画
  0x967B: 0x672C, // 本
  0x955C: 0x8868, // 表
  0x8E86: 0x7D19, // 紙
  0x97A0: 0x88CF, // 裏
  0x8DC4: 0x5F69, // 彩
  0x9046: 0x8272, // 色
  0x95C5: 0x9801, // 頁
  0x96DA: 0x76EE, // 目
  0x8E9F: 0x6B21, // 次
  0x8F98: 0x5E8F, // 序
  0x8F49: 0x7D42, // 終
  0x93AF: 0x540C, // 同
  0x906C: 0x4EBA, // 人
  0x8E8F: 0x8A8C, // 誌
  0x93FA: 0x65E5, // 日
  0x8CEA: 0x8A9E, // 語
  0x95B6: 0x6587, // 文
  0x964C: 0x540D, // 名
  0x8DD0: 0x4F5C, // 作
  0x8DC0: 0x54C1, // 品
  0x95D0: 0x9762, // 面
  0x8D82: 0x9AD8, // 高
  0x8EC1: 0x8CEA, // 質
  0x8DF4: 0x5408, // 合
  0x91E5: 0x5927, // 大
  0x8FAC: 0x5C0F, // 小
  0x8F43: 0x4FEE, // 修
  0x90B3: 0x6B63, // 正
  0x96B3: 0x7121, // 無
  0x8A43: 0x6F22, // 漢
  0x89BB: 0x5316, // 化
  0x8F89: 0x5973, // 女
  0x926A: 0x7537, // 男
  0x8E71: 0x5B50, // 子
  0x95F6: 0x7269, // 物
  0x90A3: 0x4E16, // 世
  0x8A45: 0x754C, // 界
  0x958E: 0x4ED8, // 付
  0x985E: 0x9332, // 録
  0x8D58: 0x5358, // 単
  0x8D73: 0x884C, // 行
};

/// 高频漫画/汉化组/分卷命名 GBK 符号与中文汉字映射表。
const Map<int, int> _gbkCommonTable = <int, int>{
  0xA1A1: 0x3000, //
  0xA1A2: 0x3001, // 、
  0xA1A3: 0x3002, // 。
  0xA1A4: 0x00B7, // ·
  0xA1B6: 0x300A, // 《
  0xA1B7: 0x300B, // 》
  0xA1B8: 0x300C, // 「
  0xA1B9: 0x300D, // 」
  0xA1BA: 0x300E, // 『
  0xA1BB: 0x300F, // 』
  0xA1BE: 0x3010, // 【
  0xA1BF: 0x3011, // 】
  0xB5DA: 0x7B2C, // 第
  0xBEED: 0x5377, // 卷
  0xBBB0: 0x8BDD, // 话
  0xD5C2: 0x7AE0, // 章
  0xBCCA: 0x96C6, // 集
  0xB2E1: 0x518C, // 册
  0xBBD8: 0x56DE, // 回
  0xB2BF: 0x90E8, // 部
  0xC6AA: 0x7BC7, // 篇
  0xB1E0: 0x7F16, // 编
  0xB7AC: 0x756A, // 番
  0xCDE2: 0x5916, // 外
  0xCCD8: 0x7279, // 特
  0xB5E4: 0x5178, // 典
  0xB1F0: 0x522B, // 别
  0xCDEA: 0x5B8C, // 完
  0xBDE1: 0x7ED3, // 结
  0xC8AB: 0x5168, // 全
  0xC9CF: 0x4E0A, // 上
  0xD6D0: 0x4E2D, // 中
  0xCFC2: 0x4E0B, // 下
  0xC7B0: 0x524D, // 前
  0xBAF3: 0x540E, // 后
  0xD0C2: 0x65B0, // 新
  0xB0E6: 0x7248, // 版
  0xC2FE: 0x6F2B, // 漫
  0xBBAD: 0x753B, // 画
  0xB1BE: 0x672C, // 本
  0xB7E2: 0x5C01, // 封
  0xC3E6: 0x9762, // 面
  0xB2CA: 0x5F69, // 彩
  0xC9AB: 0x8272, // 色
  0xD2B3: 0x9875, // 页
  0xC4BF: 0x76EE, // 目
  0xC2BC: 0x5F55, // 录
  0xD0F2: 0x5E8F, // 序
  0xD6D5: 0x7EC8, // 终
  0xB8BD: 0x9644, // 附
  0xBACB: 0x6C49, // 汉
  0xBBAF: 0x5316, // 化
  0xD7E9: 0x7EC4, // 组
  0xB7AD: 0x7FFB, // 翻
  0xD2EB: 0x8BD1, // 译
  0xC9A8: 0x626B, // 扫
  0xC3E8: 0x63CF, // 描
  0xB8DF: 0x9AD8, // 高
  0xC7E5: 0x6E05, // 清
  0xBACF: 0x5408, // 合
  0xB5A5: 0x5355, // 单
  0xD0D0: 0x884C, // 行
  0xCDAC: 0x540C, // 同
  0xC8CB: 0x4EBA, // 人
  0xD6BE: 0x5FD7, // 志
  0xCEDE: 0x65E0, // 无
  0xD0DE: 0x4FEE, // 修
  0xD5FD: 0x6B63, // 正
  0xCEC4: 0x6587, // 文
  0xD7D6: 0x5B57, // 字
  0xCDBC: 0x56FE, // 图
  0xC6AC: 0x7247, // 片
  0xD7F7: 0x4F5C, // 作
  0xC6B7: 0x54C1, // 品
  0xB4F3: 0x5927, // 大
  0xD0A1: 0x5C0F, // 小
  0xC3D4: 0x8FF7, // 迷
  0xB9AC: 0x5BAB, // 宫
  0xB7B9: 0x996D, // 饭
};
