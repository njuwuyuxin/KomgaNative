import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读器的骨架：顶栏 / 阅读区 / 书末条 / 底栏 + 亮度遮罩。
///
/// 从 `ReaderScreen` 拆出来，页面只负责把各块拼进来。chrome（顶栏、书末条、
/// 底栏）的显隐集中在这一处，后续做显隐动画与沉浸式系统栏（UI-P1-1）只改这里。
class ReaderFrame extends StatelessWidget {
  const ReaderFrame({
    required this.palette,
    required this.chromeVisible,
    required this.topBar,
    required this.content,
    required this.bottomBar,
    required this.dimOpacity,
    this.finishedBar,
    super.key,
  });

  final ReaderPalette palette;
  final bool chromeVisible;
  final Widget topBar;
  final Widget content;
  final Widget bottomBar;

  /// 书末条：只有读完才有。
  final Widget? finishedBar;

  /// 亮度遮罩不透明度（0 = 不遮）。
  final double dimOpacity;

  @override
  Widget build(BuildContext context) {
    final finished = finishedBar;
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: <Widget>[
          SafeArea(
            child: Column(
              children: <Widget>[
                if (chromeVisible) topBar,
                Expanded(child: content),
                if (chromeVisible && finished != null) finished,
                if (chromeVisible) bottomBar,
              ],
            ),
          ),
          // 亮度遮罩：盖住整块阅读区（含 chrome），但不吃点击——
          // 调暗是为了少看光线，不是为了挡住操作。
          if (dimOpacity > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  key: const Key('reader-dimmer'),
                  color: Colors.black.withValues(alpha: dimOpacity),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
