part of 'reader_paged_view.dart';

/// 卷页纸面/纸背迟到加载时的平滑淡入控制器，避免纯白背面落地瞬间突变成图片。
final class _CurlFaceFade {
  _CurlFaceFade({required TickerProvider vsync, required this.onTick}) {
    _controller = AnimationController(vsync: vsync, duration: _kDuration)
      ..addListener(_handleTick)
      ..addStatusListener(_handleStatus);
  }

  static const Duration _kDuration = Duration(milliseconds: 160);

  final VoidCallback onTick;
  late final AnimationController _controller;

  double sheetMix = 1;
  double backMix = 1;
  bool _fadingSheet = false;
  bool _fadingBack = false;

  void begin({
    required bool sheetReady,
    required bool hasBack,
    required bool backReady,
  }) {
    stop();
    sheetMix = sheetReady ? 1 : 0;
    backMix = hasBack && backReady ? 1 : 0;
  }

  void resetOpaque() {
    stop();
    sheetMix = 1;
    backMix = 1;
  }

  void checkLate({
    required bool Function() hasSheetImage,
    required bool hasBackPage,
    required bool Function() hasBackImage,
  }) {
    var shouldAnimate = false;
    if (sheetMix == 0 && !_fadingSheet && hasSheetImage()) {
      _fadingSheet = true;
      shouldAnimate = true;
    }
    if (hasBackPage && backMix == 0 && !_fadingBack && hasBackImage()) {
      _fadingBack = true;
      shouldAnimate = true;
    }
    if (shouldAnimate && !_controller.isAnimating) {
      unawaited(_controller.forward(from: 0));
    }
  }

  void stop() {
    _controller.stop();
    _fadingSheet = false;
    _fadingBack = false;
  }

  void dispose() => _controller.dispose();

  void _handleTick() {
    final v = Curves.easeOut.transform(_controller.value);
    if (_fadingSheet) sheetMix = v;
    if (_fadingBack) backMix = v;
    onTick();
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_fadingSheet) {
      sheetMix = 1;
      _fadingSheet = false;
    }
    if (_fadingBack) {
      backMix = 1;
      _fadingBack = false;
    }
  }
}
