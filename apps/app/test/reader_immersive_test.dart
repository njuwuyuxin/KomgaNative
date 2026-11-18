import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// UI-P1-1：chrome 显隐动画 + 沉浸式系统栏。
///
/// 断言的是**调用顺序**而不是"调用了"：用户看到的是"栏先淡出、系统栏跟着走"，
/// 顺序错了就是"系统栏先没、浮层还在"。
void main() {
  /// 记录平台通道上的系统 UI 模式（`SystemUiMode` 的字符串形式）。
  List<String> recordSystemUi(WidgetTester tester) {
    final calls = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (
      MethodCall call,
    ) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
        calls.add('${call.arguments}');
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    return calls;
  }

  testWidgets('隐藏 chrome 进沉浸式，再显示时恢复系统栏', (WidgetTester tester) async {
    final calls = recordSystemUi(tester);
    await pumpReader(tester, book: demoReaderBook());
    expect(calls, isEmpty, reason: '打开阅读器本身不该改系统 UI 模式');

    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    expect(calls, <String>['SystemUiMode.immersiveSticky']);

    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    expect(calls.last, 'SystemUiMode.edgeToEdge');
  });

  testWidgets('退出阅读器一定恢复系统栏', (WidgetTester tester) async {
    final calls = recordSystemUi(tester);
    await pumpReader(tester, book: demoReaderBook());

    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    expect(calls, <String>['SystemUiMode.immersiveSticky']);

    // 换掉整棵树 = 离开阅读器。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(calls.last, 'SystemUiMode.edgeToEdge');
  });

  testWidgets('阅读区尺寸不随 chrome 显隐变化（图不能跳一下）', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());
    final before = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    final imageBefore = tester.getRect(find.byKey(const Key('reader-image-0')));

    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(const Key('reader-tap-layer'))),
      before,
      reason: '阅读区固定按全屏布局，chrome 显隐不改变它的尺寸',
    );
    expect(
      tester.getRect(find.byKey(const Key('reader-image-0'))),
      imageBefore,
      reason: '页面图不应该因为 chrome 收起而变大',
    );
  });

  testWidgets('普通设备是淡出：第一帧 chrome 还在（不是瞬切）', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());

    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    await tester.tapAt(rect.center);
    // 只推进一帧：淡出刚开始，chrome 仍在树上。
    await tester.pump();
    expect(find.byTooltip('Close'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byTooltip('Close'), findsNothing);
  });

  testWidgets('墨水屏瞬切：隐藏后第一帧就没有 chrome', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook(), forceEink: true);

    final rect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
    await tester.tapAt(rect.center);
    await tester.pump();

    expect(find.byTooltip('Close'), findsNothing);
  });
}
