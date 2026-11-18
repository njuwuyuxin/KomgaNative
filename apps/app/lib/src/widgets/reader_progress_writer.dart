import 'dart:async';

/// 阅读器的进度回写节流：连续翻页时只写最后停下的那一页。
///
/// 从 `ReaderScreen` 拆出来，只负责"何时写、写没写过"；
/// "怎么写"（先落盘再提交，见 ADR 0002）由调用方注入。
class ReaderProgressWriter {
  ReaderProgressWriter({required this.write, this.delay = defaultDelay});

  /// 翻页后多久回写进度。
  static const Duration defaultDelay = Duration(milliseconds: 600);

  /// 真正的写入：落盘 + 排队提交。抛错表示这一页没写成，下次会再试。
  final Future<void> Function(int page) write;

  final Duration delay;

  int _lastSaved = 0;
  Timer? _timer;

  /// 防抖写入第 [page] 页。
  void schedule(int page) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(flush(page)));
  }

  /// 立即写入（切后台/锁屏）：只靠防抖会丢掉"看完就退出"的那一页。
  Future<void> flush(int page) async {
    _timer?.cancel();
    if (page == _lastSaved) return;
    try {
      await write(page);
      _lastSaved = page;
    } on Object {
      // 本地库打不开（磁盘满/库损坏/测试环境没有 path_provider 通道）也
      // 不能把阅读打断：这一页只是没落盘，下一次翻页会再试。
      // 只吞不报是因为进度回写是后台行为，用户此刻只想看书。
    }
  }

  void dispose() => _timer?.cancel();
}
