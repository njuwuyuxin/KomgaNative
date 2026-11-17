import 'dart:io';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 黄金图工具。
///
/// 设计要点：
/// 1. **尺寸与 DPR 显式指定**，不依赖测试默认值（默认 800×600 会掩盖平板问题）；
/// 2. **加载真实字体**（Roboto + MaterialIcons），否则文字/图标全是方块，Agent 看不出问题；
/// 3. 基线平台固定为 Windows（与 CI 的 `windows-latest` 一致），见 docs/environment-setup.md。
const double kGoldenDevicePixelRatio = 3.0;

/// 常用画布尺寸。
abstract final class GoldenSizes {
  static const Size phone = Size(390, 844);
  static const Size phoneLandscape = Size(844, 390);
  static const Size tablet = Size(1024, 768);
  static const Size eink = Size(758, 1024);
}

/// 加载应用字体与 Material 图标字体。
///
/// `FLUTTER_ROOT` 由 `flutter test` 注入，因此在 CI 上也成立。
Future<void> loadAppFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    var loaded = false;
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final bytes = Uint8List.fromList(file.readAsBytesSync());
      loader.addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
      loaded = true;
    }
    if (loaded) await loader.load();
  }

  await load('Roboto', <String>[
    'assets/fonts/Roboto-Regular.ttf',
    'assets/fonts/Roboto-Medium.ttf',
  ]);

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    await load('MaterialIcons', <String>[
      '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ]);
  }
}

/// 给主题套上测试字体（仅测试用，不污染设计系统）。
ThemeData withTestFont(ThemeData base) => base.copyWith(
  textTheme: base.textTheme.apply(
    fontFamily: 'Roboto',
    bodyColor: base.textTheme.bodyMedium?.color,
  ),
  primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Roboto'),
);

/// 以指定画布尺寸渲染一个页面。
///
/// [overrides] 用于把会话/网络等依赖替换成内存实现，避免黄金图被平台通道错误污染。
/// [settle] 设为 false 适用于含无限动画的页面（如带 spinner 的 splash）。
/// [precacheImages] 用于需要真实封面的页面：测试的假时钟不会推进图片解码，
/// 必须先在真实事件循环里把字节解成 `ui.Image` 塞进 ImageCache，
/// 否则截图里只有占位块（实测过，别指望 pumpAndSettle 能等出来）。
Future<void> pumpGoldenScreen(
  WidgetTester tester, {
  required Widget screen,
  required Size size,
  required ThemeData theme,
  double textScale = 1.0,
  List<Override> overrides = const <Override>[],
  bool settle = true,
  List<Uint8List> precacheImages = const <Uint8List>[],
}) async {
  tester.view.physicalSize = Size(
    size.width * kGoldenDevicePixelRatio,
    size.height * kGoldenDevicePixelRatio,
  );
  tester.view.devicePixelRatio = kGoldenDevicePixelRatio;
  addTearDown(tester.view.reset);

  if (precacheImages.isNotEmpty) {
    await tester.runAsync(() async {
      for (final bytes in precacheImages) {
        final image = await decodeImageFromList(bytes);
        PaintingBinding.instance.imageCache.putIfAbsent(
          MemoryImage(bytes),
          () => OneFrameImageStreamCompleter(
            SynchronousFuture<ImageInfo>(ImageInfo(image: image)),
          ),
        );
      }
    });
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: withTestFont(theme),
        home: screen,
        builder: (BuildContext context, Widget? child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(textScaler: TextScaler.linear(textScale)),
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 与基线比对。基线在 `test/golden/goldens/` 下，命名约定：
/// `<页面>@<形态>_<主题>[_<文本缩放>].png`。
Future<void> expectGolden(WidgetTester tester, String name) {
  return expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}
