import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_platform/komga_platform.dart';

void main() {
  group('formFactorFor', () {
    test('手机竖屏 / 横屏都算 phone（按短边判断）', () {
      expect(formFactorFor(const Size(390, 844)), FormFactor.phone);
      expect(formFactorFor(const Size(844, 390)), FormFactor.phone);
    });

    test('平板横竖屏都算 tablet（含 1024×768 这类阅读设备）', () {
      expect(formFactorFor(const Size(1024, 768)), FormFactor.tablet);
      expect(formFactorFor(const Size(768, 1024)), FormFactor.tablet);
      expect(formFactorFor(const Size(834, 1112)), FormFactor.tablet);
    });

    test('大屏进入 desktopLike', () {
      expect(formFactorFor(const Size(1440, 900)), FormFactor.desktopLike);
      expect(formFactorFor(const Size(1280, 800)), FormFactor.desktopLike);
    });

    test('墨水屏常见尺寸（758×1024）落在 tablet', () {
      expect(formFactorFor(const Size(758, 1024)), FormFactor.tablet);
    });
  });

  group('DeviceProfile', () {
    test('未探测到墨水屏时不影响布局判断', () {
      const profile = DeviceProfile(logicalSize: Size(390, 844));
      expect(profile.formFactor, FormFactor.phone);
      expect(profile.isEink, isFalse);
    });

    test('copyWith 只替换指定字段', () {
      const profile = DeviceProfile(logicalSize: Size(390, 844));
      final next = profile.copyWith(
        eink: const EinkInfo(isEink: true, vendor: 'onyx'),
      );
      expect(next.logicalSize, const Size(390, 844));
      expect(next.isEink, isTrue);
      expect(next.eink.vendor, 'onyx');
    });
  });

  group('EinkProbe', () {
    test('无原生实现时返回 unknown 而不抛异常', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final info = await EinkProbe().detect();
      expect(info.isEink, isFalse);
    });
  });
}
