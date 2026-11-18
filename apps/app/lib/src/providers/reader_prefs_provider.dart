import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/data/reader_prefs_store.dart';
import 'package:komga_platform/komga_platform.dart';

/// 阅读偏好：模式 / 亮度 / 常亮。
///
/// 改动即落盘（用户改设置的频率很低，不必攒批）。
/// 恢复期间如果用户已经动过设置，不能被"旧存档"覆盖回去。
class ReaderPrefsController extends Notifier<ReaderPrefs> {
  bool _touched = false;

  @override
  ReaderPrefs build() {
    unawaited(_restore());
    return const ReaderPrefs();
  }

  ReaderPrefsStore get _store => ref.read(readerPrefsStoreProvider);

  Future<void> _restore() async {
    try {
      final saved = await _store.load();
      if (saved == null || _touched) return;
      state = saved;
    } on Object {
      // 读不出偏好就用默认值：不能让设置存储读失败挡住阅读。
    }
  }

  void setMode(ReaderModeChoice mode) => _update(state.copyWith(mode: mode));

  void setBrightness(double brightness) =>
      _update(state.copyWith(brightness: brightness));

  void setKeepAwake(bool enabled) =>
      _update(state.copyWith(keepAwake: enabled));

  void setFit(ReaderFitChoice fit) => _update(state.copyWith(fit: fit));

  void setDirection(ReaderDirectionChoice direction) =>
      _update(state.copyWith(direction: direction));

  void setBackground(ReaderBackgroundChoice background) =>
      _update(state.copyWith(background: background));

  void _update(ReaderPrefs next) {
    if (next == state) return;
    _touched = true;
    state = next;
    unawaited(_store.save(next));
  }
}

final Provider<ReaderPrefsStore> readerPrefsStoreProvider =
    Provider<ReaderPrefsStore>((Ref ref) => SecureReaderPrefsStore());

final NotifierProvider<ReaderPrefsController, ReaderPrefs> readerPrefsProvider =
    NotifierProvider<ReaderPrefsController, ReaderPrefs>(
      ReaderPrefsController.new,
    );

/// 屏幕常亮。单独成 provider 是为了测试能换成假实现（断言"进阅读器置真、退出置假"）。
final Provider<WakeLock> wakeLockProvider = Provider<WakeLock>(
  (Ref ref) => ChannelWakeLock(),
);

/// 音量键翻页。单独成 provider 是为了测试能注入假事件流。
final Provider<HardwareKeys> hardwareKeysProvider = Provider<HardwareKeys>((
  Ref ref,
) {
  final keys = ChannelHardwareKeys();
  ref.onDispose(keys.dispose);
  return keys;
});
