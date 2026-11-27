/// 轻量级 Dart 词法剥离与声明/指令扫描器（P2-5 门禁加固）。
///
/// 精确跳过单行注释、嵌套块注释、原始与普通单行/多行字符串字面量，
/// 保持原始换行符 1:1 对齐，避免字符串里的 `{` / `}` 污染大括号计数，
/// 同时完整支持多行 `class` / `mixin` / `extension` / `extension type` 声明与 `import` / `export` 指令。
library;

final class DartTypeBlock {
  const DartTypeBlock({
    required this.kind,
    required this.name,
    required this.startLine,
    required this.endLine,
  });

  final String kind;
  final String name;
  final int startLine;
  final int endLine;

  int get lineCount => endLine - startLine + 1;
}

final class DartDirective {
  const DartDirective({
    required this.keyword,
    required this.uri,
    required this.line,
  });

  final String keyword;
  final String uri;
  final int line;
}

/// 将注释与字符串字面量内容替换为空格，严格保留换行符与真实代码字符。
///
/// 注意：字符串插值 `${...}` 内的代码大括号仍配对跳过，不会泄漏成未闭合的 `{` / `}`。
String stripDartCommentsAndStrings(String source) {
  final out = StringBuffer();
  final n = source.length;
  var i = 0;

  void writeSpaceOrNewline(int ch) {
    out.writeCharCode(ch == 0x0A ? 0x0A : 0x20);
  }

  while (i < n) {
    final ch = source.codeUnitAt(i);

    // 单行注释 // ...
    if (ch == 0x2F && i + 1 < n && source.codeUnitAt(i + 1) == 0x2F) {
      out.write('  ');
      i += 2;
      while (i < n && source.codeUnitAt(i) != 0x0A) {
        out.write(' ');
        i++;
      }
      continue;
    }

    // 可嵌套块注释 /* ... */
    if (ch == 0x2F && i + 1 < n && source.codeUnitAt(i + 1) == 0x2A) {
      out.write('  ');
      i += 2;
      var depth = 1;
      while (i < n && depth > 0) {
        final cur = source.codeUnitAt(i);
        if (cur == 0x2F && i + 1 < n && source.codeUnitAt(i + 1) == 0x2A) {
          out.write('  ');
          depth++;
          i += 2;
        } else if (cur == 0x2A &&
            i + 1 < n &&
            source.codeUnitAt(i + 1) == 0x2F) {
          out.write('  ');
          depth--;
          i += 2;
        } else {
          writeSpaceOrNewline(cur);
          i++;
        }
      }
      continue;
    }

    // 原始字符串 r'...' / r"..." / r'''...''' / r"""..."""
    final isRaw =
        ch == 0x72 &&
        i + 1 < n &&
        (source.codeUnitAt(i + 1) == 0x27 || source.codeUnitAt(i + 1) == 0x22);
    if (isRaw || ch == 0x27 || ch == 0x22) {
      if (isRaw) {
        out.write(' ');
        i++;
      }
      final quote = source.codeUnitAt(i);
      final isTriple =
          i + 2 < n &&
          source.codeUnitAt(i + 1) == quote &&
          source.codeUnitAt(i + 2) == quote;
      final delimLen = isTriple ? 3 : 1;
      for (var k = 0; k < delimLen; k++) {
        out.write(' ');
      }
      i += delimLen;
      i = _skipStringBody(
        source,
        i,
        quote: quote,
        isTriple: isTriple,
        isRaw: isRaw,
        out: out,
      );
      continue;
    }

    out.writeCharCode(ch);
    i++;
  }
  return out.toString();
}

int _skipStringBody(
  String source,
  int start, {
  required int quote,
  required bool isTriple,
  required bool isRaw,
  required StringBuffer out,
}) {
  final n = source.length;
  var i = start;
  while (i < n) {
    final cur = source.codeUnitAt(i);
    if (!isRaw && cur == 0x5C && i + 1 < n) {
      // 转义字符 \x
      out.write(' ');
      out.writeCharCode(source.codeUnitAt(i + 1) == 0x0A ? 0x0A : 0x20);
      i += 2;
      continue;
    }
    if (!isRaw &&
        cur == 0x24 &&
        i + 1 < n &&
        source.codeUnitAt(i + 1) == 0x7B) {
      // 字符串插值 ${ ... }：内部表达式可能含嵌套字符串/大括号，递归配对消耗完。
      out.write('  ');
      i += 2;
      i = _skipInterpolation(source, i, out);
      continue;
    }
    if (cur == quote) {
      if (!isTriple) {
        out.write(' ');
        return i + 1;
      }
      if (i + 2 < n &&
          source.codeUnitAt(i + 1) == quote &&
          source.codeUnitAt(i + 2) == quote) {
        out.write('   ');
        return i + 3;
      }
    }
    out.writeCharCode(cur == 0x0A ? 0x0A : 0x20);
    i++;
  }
  return i;
}

int _skipInterpolation(String source, int start, StringBuffer out) {
  final n = source.length;
  var i = start;
  var depth = 1;
  while (i < n && depth > 0) {
    final cur = source.codeUnitAt(i);
    if (cur == 0x7B) {
      depth++;
      out.write(' ');
      i++;
      continue;
    }
    if (cur == 0x7D) {
      depth--;
      out.write(' ');
      i++;
      continue;
    }
    final isRaw =
        cur == 0x72 &&
        i + 1 < n &&
        (source.codeUnitAt(i + 1) == 0x27 || source.codeUnitAt(i + 1) == 0x22);
    if (isRaw || cur == 0x27 || cur == 0x22) {
      if (isRaw) {
        out.write(' ');
        i++;
      }
      final q = source.codeUnitAt(i);
      final triple =
          i + 2 < n &&
          source.codeUnitAt(i + 1) == q &&
          source.codeUnitAt(i + 2) == q;
      final dLen = triple ? 3 : 1;
      for (var k = 0; k < dLen; k++) {
        out.write(' ');
      }
      i += dLen;
      i = _skipStringBody(
        source,
        i,
        quote: q,
        isTriple: triple,
        isRaw: isRaw,
        out: out,
      );
      continue;
    }
    out.writeCharCode(cur == 0x0A ? 0x0A : 0x20);
    i++;
  }
  return i;
}

final RegExp _typeDeclPattern = RegExp(
  r'^\s*(?:(?:abstract|sealed|final|base|interface)\s+)*'
  r'(?:(mixin\s+class|class|mixin|enum|extension\s+type|extension)\b)'
  r'(?:\s+(?:const\s+)?(\w+))?',
);

/// 扫描所有顶层 `class` / `mixin` / `enum` / `extension` / `extension type` 块及其精确起止行号。
List<DartTypeBlock> scanDartTypeBlocks(String source) {
  final stripped = stripDartCommentsAndStrings(source);
  final lines = stripped.split('\n');
  final blocks = <DartTypeBlock>[];

  var topBraceDepth = 0;
  var pendingHeader = false;
  var inBlock = false;
  var blockKind = '';
  var blockName = '';
  var blockStartLine = 0;
  var blockBraceDepth = 0;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    if (!inBlock && !pendingHeader && topBraceDepth == 0) {
      final match = _typeDeclPattern.firstMatch(line);
      if (match != null) {
        blockKind = match.group(1)!.replaceAll(RegExp(r'\s+'), ' ');
        blockName = match.group(2) ?? '<unnamed>';
        blockStartLine = i + 1;
        pendingHeader = true;
      }
    }

    for (var c = 0; c < line.length; c++) {
      final ch = line.codeUnitAt(c);
      if (pendingHeader) {
        if (ch == 0x7B) {
          // 找到声明体起始 '{'（无论是否与头部同行）
          pendingHeader = false;
          inBlock = true;
          blockBraceDepth = 1;
          topBraceDepth++;
        } else if (ch == 0x3B) {
          // 遇到 ';'（如 mixin application: class A = B with C;），无块体
          pendingHeader = false;
        }
        continue;
      }
      if (inBlock) {
        if (ch == 0x7B) {
          blockBraceDepth++;
          topBraceDepth++;
        } else if (ch == 0x7D) {
          blockBraceDepth--;
          topBraceDepth--;
          if (blockBraceDepth == 0) {
            blocks.add(
              DartTypeBlock(
                kind: blockKind,
                name: blockName,
                startLine: blockStartLine,
                endLine: i + 1,
              ),
            );
            inBlock = false;
          }
        }
        continue;
      }
      if (ch == 0x7B) {
        topBraceDepth++;
      } else if (ch == 0x7D && topBraceDepth > 0) {
        topBraceDepth--;
      }
    }
  }
  return blocks;
}

final RegExp _directiveHeadPattern = RegExp(
  r'''\b(import|export|part)\s+(?!of\b)(?:deferred\s+)?['"]([^'"]+)['"]''',
);
final RegExp _conditionalUriPattern = RegExp(
  r'''\bif\s*\([^)]*\)\s*['"]([^'"]+)['"]''',
);

/// 扫描源码中的全部 `import` / `export`（含全部 `if (...)` 条件导入 URI）与 `part` 指令
/// （自动忽略注释、字符串内部文本与多行换行格式）。
List<DartDirective> scanDartDirectives(String source) {
  final stripped = stripDartCommentsAndStrings(source);
  final out = <DartDirective>[];
  for (final match in _directiveHeadPattern.allMatches(source)) {
    final keyword = match.group(1)!;
    if (!stripped.startsWith(keyword, match.start)) continue;
    final prefix = source.substring(0, match.start);
    final line = '\n'.allMatches(prefix).length + 1;
    out.add(DartDirective(keyword: keyword, uri: match.group(2)!, line: line));

    if (keyword == 'part') continue;
    // 向后扫描到该指令的分号 `;`（基于 stripped 跳过注释与字符串中的分号），收集所有条件导入 URI。
    final semiIndex = stripped.indexOf(';', match.end);
    final endIndex = semiIndex < 0 ? source.length : semiIndex;
    final tail = source.substring(match.end, endIndex);
    final strippedTail = stripped.substring(match.end, endIndex);
    for (final cond in _conditionalUriPattern.allMatches(tail)) {
      if (!strippedTail.startsWith('if', cond.start)) continue;
      final condPrefix = source.substring(0, match.end + cond.start);
      final condLine = '\n'.allMatches(condPrefix).length + 1;
      out.add(
        DartDirective(keyword: keyword, uri: cond.group(1)!, line: condLine),
      );
    }
  }
  return out;
}
