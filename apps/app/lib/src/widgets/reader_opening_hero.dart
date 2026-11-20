import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/widgets/cover_image.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读器开场时的封面 Hero（UI-P2-2）。
///
/// 为什么不是直接把 Hero 挂在第一页上：首页图是异步解码的，路由转场开始时
/// 它往往还在转圈；把 Hero 挂在页上，用户看到的就是"封面飞过去变成一个 spinner"。
/// 这里改为**封面自己飞**：阅读器一进来就在页面槽位放一张封面 Hero，等首屏页图
/// 真的到了（或失败，或等了约 1.35s）再淡出，页面图在下面接管。这样飞行过程中
/// 始终是封面，落地后是页面。等待页图而不是固定 450ms，是设备上走查时发现的：
/// 固定时长一到就淡出，弱网/大页面上会露出一次"黑底转圈"。
///
/// 只由"继续阅读卡片"触发：`ReaderArgs.heroTag` 为空（系列详情/深链）时
/// 根本不建这个 widget。墨水屏与"减少动态效果"也不建（由调用方判断）。
class ReaderOpeningHero extends ConsumerStatefulWidget {
  const ReaderOpeningHero({
    required this.bookId,
    required this.page,
    required this.tag,
    super.key,
  });

  final String bookId;

  /// 1 基的起始页（继续阅读卡片带来的进度）；只用来等这一页的字节。
  final int page;

  final String tag;

  @override
  ConsumerState<ReaderOpeningHero> createState() => _ReaderOpeningHeroState();
}

class _ReaderOpeningHeroState extends ConsumerState<ReaderOpeningHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  Timer? _fallback;
  bool _done = false;
  bool _started = false;
  bool _fading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final motion = AppMotion.of(context);
    _controller = AnimationController(vsync: this, duration: motion.quick);
    _fade = Tween<double>(
      begin: 1,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _done = true);
      }
    });
    // 页图一直没来（弱网/失败）也要让路：不能让封面永远盖着阅读区。
    _fallback = Timer(motion.emphasized * 3, _startFade);
  }

  @override
  void dispose() {
    _fallback?.cancel();
    if (_started) _controller.dispose();
    super.dispose();
  }

  void _startFade() {
    if (!mounted || _fading) return;
    _fallback?.cancel();
    _fading = true;
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();

    final image = ref.watch(
      readerPageImageProvider((bookId: widget.bookId, page: widget.page)),
    );
    if (!_fading && (image.value != null || image.hasError)) {
      // build 里不能直接 forward（会 setState during build），下一帧再开始淡出。
      WidgetsBinding.instance.addPostFrameCallback((_) => _startFade());
    }

    final cover = ref.watch(bookCoverProvider(widget.bookId));
    final Uint8List? bytes = switch (cover) {
      AsyncData<Uint8List?>(:final value) => value,
      _ => null,
    };
    final shape = AppShapes.of(context, AppShapes.cover);

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // 目标是一个 2:3 的"页面槽位"：宽度不超过屏幕 82%、高度不超过 86%。
          final width = math.min(
            constraints.maxWidth * 0.82,
            constraints.maxHeight * 0.86 * 2 / 3,
          );
          final height = width * 3 / 2;
          return Center(
            child: FadeTransition(
              opacity: _fade,
              child: Hero(
                key: const Key('reader-opening-hero'),
                tag: widget.tag,
                child: SizedBox(
                  width: width,
                  height: height,
                  child: ClipPath(
                    clipper: ShapeBorderClipper(shape: shape),
                    child: bytes == null
                        ? ColoredBox(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                          )
                        : CoverImage(bytes: bytes),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
