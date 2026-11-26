import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/src/providers/incoming_files_provider.dart';
import 'package:yomu/src/providers/router_provider.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_platform/yomu_platform.dart';

/// 监听系统「用 Yomu 打开 / 分享到 Yomu」传入的 `.cbz`/`.zip` 文件，自动入库并打开阅读器（LMA-12）。
///
/// 冷启动时必须等待 `sessionProvider` 退出 `SessionLoading`（即 `/splash -> /reading` 重定向稳定后）
/// 再压栈 `/reader/:bookId`，既防止启动守卫冲掉阅读器路由，也保证按返回键能回到主壳首页。
class IncomingFileScope extends ConsumerStatefulWidget {
  const IncomingFileScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<IncomingFileScope> createState() => _IncomingFileScopeState();
}

class _IncomingFileScopeState extends ConsumerState<IncomingFileScope>
    with WidgetsBindingObserver {
  StreamSubscription<IncomingComicFile>? _sub;
  bool _initialConsumed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final incoming = ref.read(incomingFilesProvider);
    _sub = incoming.stream.listen((IncomingComicFile file) {
      unawaited(_importAndOpen(file));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(sessionProvider) is! SessionLoading) {
        _scheduleInitialConsume();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        ref.read(sessionProvider) is! SessionLoading) {
      unawaited(_consumeFiles());
    }
  }

  void _scheduleInitialConsume() {
    if (_initialConsumed) return;
    _initialConsumed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_consumeFiles());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _consumeFiles() async {
    final incoming = ref.read(incomingFilesProvider);
    final initial = await incoming.consumeInitialFiles();
    for (final file in initial) {
      if (!mounted) return;
      await _importAndOpen(file);
    }
    if (!mounted) return;
    final inboxBookId = await ref
        .read(incomingComicCoordinatorProvider)
        .sweepIosInboxIfPresent();
    if (inboxBookId != null && mounted) {
      _openBookInReader(inboxBookId);
    }
  }

  Future<void> _importAndOpen(IncomingComicFile file) async {
    final bookId = await ref
        .read(incomingComicCoordinatorProvider)
        .handleIncomingFile(file);
    if (bookId != null && mounted) {
      _openBookInReader(bookId);
    }
  }

  void _openBookInReader(String bookId) {
    final router = ref.read(routerProvider);
    final encodedSource = Uri.encodeComponent(kLocalSourceKey);
    final target = '/reader/$bookId?source=$encodedSource';
    if (router.routerDelegate.currentConfiguration.uri.path == '/splash') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(ref.read(routerProvider).push(target));
      });
      WidgetsBinding.instance.ensureVisualUpdate();
      return;
    }
    unawaited(router.push(target));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionProvider, (
      SessionState? prev,
      SessionState next,
    ) {
      if (prev is SessionLoading && next is! SessionLoading) {
        _scheduleInitialConsume();
      }
    });
    return widget.child;
  }
}
