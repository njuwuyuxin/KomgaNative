import 'dart:async';

import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:material_ui/material_ui.dart';

/// 把"阅读器 chrome 是否可见"同步到系统栏（UI-P1-1）。
///
/// 规则：
/// - chrome 隐藏 → `immersiveSticky`（沉浸式，滑动边缘才临时露出系统栏）；
/// - chrome 显示 → 恢复 `edgeToEdge`（Flutter 在 Android 上的默认模式）；
/// - **退出阅读器时一定恢复**，否则会把"没有系统栏的边到边"留给书架页；
/// - 只在状态真的变化时才发平台调用，进入阅读器时不会平白覆盖 App 的默认模式。
///
/// 动画与系统栏是两件事：本组件只管系统栏，显隐动画在 `ReaderFrame` 里，
/// 两者由同一个 `chromeVisible` 驱动，所以不会出现"栏淡出了系统栏还在"。
class ReaderSystemUi extends StatefulWidget {
  const ReaderSystemUi({
    required this.immersive,
    required this.child,
    super.key,
  });

  /// 是否进入沉浸式（= chrome 隐藏）。
  final bool immersive;

  final Widget child;

  @override
  State<ReaderSystemUi> createState() => _ReaderSystemUiState();
}

class _ReaderSystemUiState extends State<ReaderSystemUi> {
  /// 当前是否已经把系统栏藏起来了（只在 true 时才需要负责恢复）。
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ReaderSystemUi oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.immersive != widget.immersive) _sync();
  }

  @override
  void dispose() {
    if (_hidden) {
      _hidden = false;
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  void _sync() {
    final want = widget.immersive;
    if (want == _hidden) return;
    _hidden = want;
    // 等这一帧画完再切：系统栏一出现，`MediaQuery` 会跟着变，
    // 同帧内切换会让 chrome 的位置在屏幕上"跳一下"。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          want ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
