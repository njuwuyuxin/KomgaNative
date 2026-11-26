import 'package:yomu_reader/yomu_reader.dart';
import 'package:test/test.dart';

/// RDR-07：点击区预设解析。
void main() {
  TapZoneAction tap(
    TapZonePreset preset,
    double x, {
    double y = 0.5,
    bool rtl = false,
    bool inverted = false,
  }) => resolveTapZone(
    preset: preset,
    dx: x * 1000,
    dy: y * 1000,
    width: 1000,
    height: 1000,
    rightToLeft: rtl,
    inverted: inverted,
  );

  group('leftRight', () {
    test('左三分之一上一页、右三分之一下一页、中间切 chrome', () {
      expect(tap(TapZonePreset.leftRight, 0.1), TapZoneAction.previous);
      expect(tap(TapZonePreset.leftRight, 0.5), TapZoneAction.toggleChrome);
      expect(tap(TapZonePreset.leftRight, 0.9), TapZoneAction.next);
    });

    test('RTL 镜像', () {
      expect(tap(TapZonePreset.leftRight, 0.1, rtl: true), TapZoneAction.next);
      expect(
        tap(TapZonePreset.leftRight, 0.9, rtl: true),
        TapZoneAction.previous,
      );
    });

    test('invert 与 RTL 叠加等于镜像回去', () {
      expect(
        tap(TapZonePreset.leftRight, 0.1, rtl: true, inverted: true),
        TapZoneAction.previous,
      );
    });

    test('invert 不改 chrome 区', () {
      expect(
        tap(TapZonePreset.leftRight, 0.5, inverted: true),
        TapZoneAction.toggleChrome,
      );
    });
  });

  group('lShaped', () {
    test('左列上一页、右下角下一页、左上角不翻页', () {
      expect(tap(TapZonePreset.lShaped, 0.1, y: 0.1), TapZoneAction.previous);
      expect(tap(TapZonePreset.lShaped, 0.9, y: 0.9), TapZoneAction.next);
      expect(
        tap(TapZonePreset.lShaped, 0.9, y: 0.1),
        TapZoneAction.toggleChrome,
      );
    });
  });

  group('kindle', () {
    test('左 40% / 右 40%，中间 20% 是 chrome', () {
      expect(tap(TapZonePreset.kindle, 0.2), TapZoneAction.previous);
      expect(tap(TapZonePreset.kindle, 0.5), TapZoneAction.toggleChrome);
      expect(tap(TapZonePreset.kindle, 0.8), TapZoneAction.next);
    });
  });

  group('edge', () {
    test('只有最外侧 15% 翻页', () {
      expect(tap(TapZonePreset.edge, 0.1), TapZoneAction.previous);
      expect(tap(TapZonePreset.edge, 0.4), TapZoneAction.toggleChrome);
      expect(tap(TapZonePreset.edge, 0.9), TapZoneAction.next);
    });
  });

  group('automatic', () {
    test('竖屏按左-右，横屏按 L 形', () {
      final portrait = resolveTapZone(
        preset: TapZonePreset.automatic,
        dx: 100,
        dy: 900,
        width: 400,
        height: 800,
      );
      expect(portrait, TapZoneAction.previous, reason: '竖屏左侧 = 上一页');

      // 横屏下左侧也是上一页，但右下角才翻页（L 形），右上角不翻。
      final landscapeBottomRight = resolveTapZone(
        preset: TapZonePreset.automatic,
        dx: 900,
        dy: 700,
        width: 1000,
        height: 600,
      );
      expect(landscapeBottomRight, TapZoneAction.next);
      final landscapeTopRight = resolveTapZone(
        preset: TapZonePreset.automatic,
        dx: 900,
        dy: 100,
        width: 1000,
        height: 600,
      );
      expect(landscapeTopRight, TapZoneAction.toggleChrome);
    });
  });

  test('零尺寸视口安全返回 chrome', () {
    expect(
      resolveTapZone(
        preset: TapZonePreset.leftRight,
        dx: 0,
        dy: 0,
        width: 0,
        height: 0,
      ),
      TapZoneAction.toggleChrome,
    );
  });
}
