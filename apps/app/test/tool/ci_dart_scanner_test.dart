import 'package:flutter_test/flutter_test.dart';

import '../../../../tool/ci_dart_scanner.dart';

void main() {
  group('P2-5 ci_dart_scanner', () {
    test('detects multiline class/mixin/extension/extension type headers', () {
      const source = '''
class MultilineClass
    extends BaseClass
    with MixinA, MixinB {
  int a = 1;
  int b = 2;
}

mixin MultilineMixin
    on State<Foo>,
        TickerProviderStateMixin<Foo> {
  void tick() {}
}

extension MultilineExt
    on String {
  bool get isBlank => trim().isEmpty;
}

extension type const UserId(String value)
    implements Object {
  bool get isValid => value.isNotEmpty;
}
''';
      final blocks = scanDartTypeBlocks(source);
      expect(blocks.map((b) => '${b.kind}:${b.name}'), <String>[
        'class:MultilineClass',
        'mixin:MultilineMixin',
        'extension:MultilineExt',
        'extension type:UserId',
      ]);
      expect(blocks[0].startLine, 1);
      expect(blocks[0].lineCount, 6);
      expect(blocks[1].startLine, 8);
      expect(blocks[1].lineCount, 5);
      expect(blocks[2].startLine, 14);
      expect(blocks[2].lineCount, 4);
      expect(blocks[3].startLine, 19);
      expect(blocks[3].lineCount, 4);
    });

    test('ignores braces inside strings, raw strings, and comments', () {
      const source = '''
class BraceHeavy {
  // } fake close in line comment
  /* } /* nested } */ still comment */
  final s1 = '}}} not closing';
  final s2 = r"}}} raw string";
  final s3 = \'\'\'
    }}}
  \'\'\';
  final s4 = 'interp \${1 + 2} still string }';
  int tail = 42;
}
''';
      final blocks = scanDartTypeBlocks(source);
      expect(blocks, hasLength(1));
      expect(blocks.single.name, 'BraceHeavy');
      expect(blocks.single.lineCount, 11);
    });

    test(
      'skips semicolon mixin applications without bleeding into next class',
      () {
        const source = '''
class Combined = Base with MixinA, MixinB;

class RealClass {
  final int x = 0;
}
''';
        final blocks = scanDartTypeBlocks(source);
        expect(blocks.map((b) => b.name), <String>['RealClass']);
        expect(blocks.single.lineCount, 3);
      },
    );

    test('scans both import and export directives including multiline', () {
      const source = '''
import 'package:komga_api/komga_api.dart';
export 'package:komga_api/src/errors.dart'
    show KomgaError;
// export 'package:komga_api/commented.dart';
final s = "export 'package:komga_api/in_string.dart';";
''';
      final directives = scanDartDirectives(source);
      expect(directives, hasLength(2));
      expect(directives[0].keyword, 'import');
      expect(directives[0].uri, 'package:komga_api/komga_api.dart');
      expect(directives[0].line, 1);
      expect(directives[1].keyword, 'export');
      expect(directives[1].uri, 'package:komga_api/src/errors.dart');
      expect(directives[1].line, 2);
    });
  });
}
