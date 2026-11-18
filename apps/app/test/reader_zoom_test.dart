import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_reader.dart';
import 'support/reader_harness.dart';

/// 双指缩放的基准点。
///
/// 以前只改 `zoomFactor`、不动平移，内容永远从左上角开始放大：手指在右下角
/// 捏合，放大后看到的却是页面左上角。这里钉住"焦点下的画面停在原地"。
void main() {
  testWidgets('以两指中点为基准放大，而不是左上角', (WidgetTester tester) async {
    await pumpReader(tester, book: demoReaderBook());

    final layer = find.byKey(const Key('reader-tap-layer'));
    final rect = tester.getRect(layer);
    // 焦点放在视口左侧 1/4 处。若仍以左上角为基准，放大后 left 会停在 0。
    final focal = Offset(rect.left + rect.width * 0.25, rect.center.dy);

    final first = await tester.startGesture(
      focal - const Offset(40, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      focal + const Offset(40, 0),
      pointer: 2,
    );
    await tester.pump();
    // 两指各向外移 40：跨度 80 → 160，放大一倍。
    await first.moveTo(focal - const Offset(80, 0));
    await second.moveTo(focal + const Offset(80, 0));
    await tester.pump();

    final image = tester.getRect(find.byKey(const Key('reader-image-0')));
    expect(image.width, greaterThan(rect.width * 1.5), reason: '确实放大了');
    expect(
      image.left,
      lessThan(rect.left - 20),
      reason: '焦点在左侧 1/4：内容左边缘应被推出屏幕（左上角基准会停在 0）',
    );
    expect(find.text('1 / 3'), findsOneWidget, reason: '缩放不应被当成翻页点击');

    await first.up();
    await second.up();
    await tester.pumpAndSettle();
  });
}
