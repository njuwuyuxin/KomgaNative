import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_native/src/providers/reader_prefs_provider.dart';
import 'package:komga_platform/komga_platform.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读器在前台期间接管音量键：进来 `setActive(true)` 并订阅，退出交还系统。
///
/// 从 `ReaderScreen` 拆出来：订阅/取消/交还三个时机由同一个地方负责，
/// 页面只关心"按了哪个键"。
class VolumeKeyScope extends ConsumerStatefulWidget {
  const VolumeKeyScope({required this.onKey, required this.child, super.key});

  final void Function(PageTurnKey key) onKey;
  final Widget child;

  @override
  ConsumerState<VolumeKeyScope> createState() => _VolumeKeyScopeState();
}

class _VolumeKeyScopeState extends ConsumerState<VolumeKeyScope> {
  /// dispose 里不能再碰 `ref`（widget 已卸载），所以 initState 先存一份。
  late final HardwareKeys _keys = ref.read(hardwareKeysProvider);
  StreamSubscription<PageTurnKey>? _subscription;

  @override
  void initState() {
    super.initState();
    // 只有阅读器在前台时，原生侧才消费音量键；退出时立刻交还系统。
    unawaited(_keys.setActive(true));
    _subscription = _keys.volumeKeys.listen((PageTurnKey key) {
      if (mounted) widget.onKey(key);
    });
  }

  @override
  void dispose() {
    unawaited(_keys.setActive(false));
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
