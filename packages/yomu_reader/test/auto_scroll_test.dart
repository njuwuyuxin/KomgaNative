import 'package:yomu_reader/yomu_reader.dart';
import 'package:test/test.dart';

/// RDR-08：自动滚动速度映射。
void main() {
  test('档位映射到 px/s，并夹在 1–10', () {
    expect(autoScrollPixelsPerSecond(1), 60);
    expect(autoScrollPixelsPerSecond(5), 140);
    expect(autoScrollPixelsPerSecond(10), 240);

    // 越界档位按边界算，不会出现 0 或负数——那等于"按了没反应"。
    expect(autoScrollPixelsPerSecond(0), autoScrollPixelsPerSecond(1));
    expect(autoScrollPixelsPerSecond(99), autoScrollPixelsPerSecond(10));
    expect(autoScrollPixelsPerSecond(-3), autoScrollPixelsPerSecond(1));
  });

  test('每帧位移按真实帧间隔算（与帧率无关）', () {
    const frame60 = Duration(microseconds: 16667); // ≈60fps
    const frame120 = Duration(microseconds: 8333); // ≈120fps

    // 同样一秒：60 帧 × delta ≈ 120 帧 × delta。
    final oneSecondAt60 = autoScrollDeltaForFrame(5, frame60) * 60;
    final oneSecondAt120 = autoScrollDeltaForFrame(5, frame120) * 120;
    expect(oneSecondAt60, closeTo(autoScrollPixelsPerSecond(5), 2));
    expect(oneSecondAt120, closeTo(autoScrollPixelsPerSecond(5), 2));

    // 单帧位移很小，滚动才是平滑的（不是一跳一跳）。
    expect(autoScrollDeltaForFrame(5, frame60), lessThan(10));
  });

  test('零间隔不产生位移', () {
    expect(autoScrollDeltaForFrame(10, Duration.zero), 0);
  });
}
