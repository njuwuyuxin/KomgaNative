import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_native/src/providers/reader_prefs_provider.dart';
import 'package:komga_platform/komga_platform.dart';
import 'package:material_ui/material_ui.dart';

/// 把"屏幕常亮"和阅读器的生命周期绑在一起：进来置真、退出置假。
///
/// 单独成 widget 而不是在 State 里手写，是为了"进入/退出/切换"三个时机
/// 都由同一个地方负责，测试里替换 [wakeLockProvider] 就能断言。
class WakeLockScope extends ConsumerStatefulWidget {
  const WakeLockScope({required this.enabled, required this.child, super.key});

  final bool enabled;
  final Widget child;

  @override
  ConsumerState<WakeLockScope> createState() => _WakeLockScopeState();
}

class _WakeLockScopeState extends ConsumerState<WakeLockScope> {
  late final WakeLock _wakeLock = ref.read(wakeLockProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_wakeLock.setEnabled(widget.enabled));
  }

  @override
  void didUpdateWidget(WakeLockScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      unawaited(_wakeLock.setEnabled(widget.enabled));
    }
  }

  @override
  void dispose() {
    // 离开阅读器一定放开：否则用户切到书架后屏幕永远不睡。
    unawaited(_wakeLock.setEnabled(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
