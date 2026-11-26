import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/progress/progress_sync_service.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:material_ui/material_ui.dart';

/// 把"补交进度"挂到 App 生命周期上：启动时、**会话连上时**、每次回到前台。
///
/// 为什么还要"会话连上时"：启动那一刻会话还在读钥匙串（`SessionLoading`），
/// 此时 flush 必然以"未连接"失败；没有这个时机的话，积压的进度要等到
/// 用户下次翻页或切后台回来才会补交（真机实测踩到）。
class ProgressSyncScope extends ConsumerStatefulWidget {
  const ProgressSyncScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ProgressSyncScope> createState() => _ProgressSyncScopeState();
}

class _ProgressSyncScopeState extends ConsumerState<ProgressSyncScope>
    with WidgetsBindingObserver {
  late final ProgressSyncService _sync = ref.read(progressSyncProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_sync.flush());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_flushAndRefreshReadingNow());
  }

  Future<void> _flushAndRefreshReadingNow() async {
    await _sync.flush();
    if (!mounted) return;
    // 回到前台时顺带刷新"继续阅读"（多端进度对账 + 本地补交后的最新结果）；
    // 未挂载监听者时 invalidate 是零开销空操作。
    ref.invalidate(ondeckProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionProvider, (
      SessionState? previous,
      SessionState next,
    ) {
      // 冷启动恢复会话、或用户重新登录：这两条路径都会走到这里。
      if (next is SessionConnected && previous is! SessionConnected) {
        unawaited(_sync.flush());
      }
    });
    return widget.child;
  }
}
