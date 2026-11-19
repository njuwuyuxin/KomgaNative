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

  void setMode(ReaderModeChoice mode, {String? seriesId}) =>
      _updateConfig(seriesId, (ReaderPrefs p) => p.copyWith(mode: mode));

  void setBrightness(double brightness, {String? seriesId}) => _updateConfig(
    seriesId,
    (ReaderPrefs p) => p.copyWith(brightness: brightness),
  );

  void setKeepAwake(bool enabled, {String? seriesId}) => _updateConfig(
    seriesId,
    (ReaderPrefs p) => p.copyWith(keepAwake: enabled),
  );

  void setFit(ReaderFitChoice fit, {String? seriesId}) =>
      _updateConfig(seriesId, (ReaderPrefs p) => p.copyWith(fit: fit));

  void setDirection(ReaderDirectionChoice direction, {String? seriesId}) =>
      _updateConfig(
        seriesId,
        (ReaderPrefs p) => p.copyWith(direction: direction),
      );

  void setBackground(ReaderBackgroundChoice background, {String? seriesId}) =>
      _updateConfig(
        seriesId,
        (ReaderPrefs p) => p.copyWith(background: background),
      );

  void setLockZoom(bool enabled, {String? seriesId}) =>
      _updateConfig(seriesId, (ReaderPrefs p) => p.copyWith(lockZoom: enabled));

  void setTrimBorders(bool enabled, {String? seriesId}) => _updateConfig(
    seriesId,
    (ReaderPrefs p) => p.copyWith(trimBorders: enabled),
  );

  /// 打开/关闭"按系列记住"（UI-P3-2）。
  ///
  /// 打开时把**当前生效值**快照成这个系列的覆盖；关闭时删掉覆盖、回到全局。
  void setSeriesOverride(String seriesId, bool enabled) {
    if (!enabled) {
      if (!state.seriesOverrides.containsKey(seriesId)) return;
      _update(state.withSeriesOverride(seriesId, null));
      return;
    }
    _update(state.withSeriesOverride(seriesId, state.forSeries(seriesId)));
  }

  /// 把当前设置存成一个命名预设（UI-P3-1）。
  ///
  /// 空名字/只有空格忽略。ID 用微秒时间戳：本地单用户、不需要全局唯一，
  /// 也避免引入 uuid 依赖；同一微秒内连点两次的概率可以忽略。
  void savePreset(String name, {String? seriesId}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final preset = ReaderPreset(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: trimmed,
      prefs: state.forSeries(seriesId).configOnly(),
    );
    _update(state.copyWith(presets: <ReaderPreset>[...state.presets, preset]));
  }

  /// 应用一个预设：整体覆盖配置，但保留预设列表本身。
  void applyPreset(String id, {String? seriesId}) {
    for (final preset in state.presets) {
      if (preset.id != id) continue;
      final config = preset.prefs;
      if (seriesId != null) {
        _update(state.withSeriesOverride(seriesId, config));
        return;
      }
      _update(
        state.copyWith(
          mode: config.mode,
          brightness: config.brightness,
          keepAwake: config.keepAwake,
          fit: config.fit,
          direction: config.direction,
          background: config.background,
        ),
      );
      return;
    }
  }

  void deletePreset(String id) {
    final next = <ReaderPreset>[
      for (final preset in state.presets)
        if (preset.id != id) preset,
    ];
    if (next.length == state.presets.length) return;
    _update(state.copyWith(presets: next));
  }

  /// 有 seriesId 时只改这个系列的覆盖；没有时改全局。
  void _updateConfig(
    String? seriesId,
    ReaderPrefs Function(ReaderPrefs current) change,
  ) {
    if (seriesId == null) {
      _update(change(state));
      return;
    }
    _update(
      state.withSeriesOverride(seriesId, change(state.forSeries(seriesId))),
    );
  }

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
