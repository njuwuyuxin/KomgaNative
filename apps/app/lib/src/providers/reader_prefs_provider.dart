import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/data/reader_prefs_store.dart';
import 'package:yomu_platform/yomu_platform.dart';
import 'package:yomu_reader/yomu_reader.dart'
    show ReaderImageFilter, TapZonePreset, WidePageSplitMode;

/// 阅读偏好：模式 / 亮度 / 常亮 / 预设 / 系列覆盖。
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

  String _requireServerKey(String? serverKey) {
    if (serverKey == null || serverKey.isEmpty) {
      throw ArgumentError.value(
        serverKey,
        'serverKey',
        '系列或书籍级阅读偏好必须显式传入非空 serverKey',
      );
    }
    return serverKey;
  }

  Future<void> _restore() async {
    try {
      final saved = await _store.load();
      if (!ref.mounted || saved == null || _touched) return;
      state = saved;
    } on Exception catch (error) {
      // 读不出偏好就用默认值：不能让设置存储读失败挡住阅读。
      debugPrint('ReaderPrefsController: load prefs failed: $error');
    }
  }

  void setMode(ReaderModeChoice mode, {String? seriesId, String? serverKey}) =>
      _updateConfig(
        seriesId,
        (ReaderConfig c) => c.copyWith(mode: mode),
        serverKey: serverKey,
      );

  void setBrightness(
    double brightness, {
    String? seriesId,
    String? serverKey,
  }) => _updateConfig(
    seriesId,
    (ReaderConfig c) => c.copyWith(brightness: brightness),
    serverKey: serverKey,
  );

  void setKeepAwake(bool enabled, {String? seriesId, String? serverKey}) =>
      _updateConfig(
        seriesId,
        (ReaderConfig c) => c.copyWith(keepAwake: enabled),
        serverKey: serverKey,
      );

  void setFit(ReaderFitChoice fit, {String? seriesId, String? serverKey}) =>
      _updateConfig(
        seriesId,
        (ReaderConfig c) => c.copyWith(fit: fit),
        serverKey: serverKey,
      );

  void setDirection(
    ReaderDirectionChoice direction, {
    String? seriesId,
    String? serverKey,
  }) => _updateConfig(
    seriesId,
    (ReaderConfig c) => c.copyWith(direction: direction),
    serverKey: serverKey,
  );

  void setBackground(
    ReaderBackgroundChoice background, {
    String? seriesId,
    String? serverKey,
  }) => _updateConfig(
    seriesId,
    (ReaderConfig c) => c.copyWith(background: background),
    serverKey: serverKey,
  );

  void setImageFilter(
    ReaderImageFilter filter, {
    String? seriesId,
    String? serverKey,
  }) => _updateConfig(
    seriesId,
    (ReaderConfig c) => c.copyWith(imageFilter: filter),
    serverKey: serverKey,
  );

  void setLockZoom(bool enabled, {String? seriesId, String? serverKey}) =>
      _updateConfig(
        seriesId,
        (ReaderConfig c) => c.copyWith(lockZoom: enabled),
        serverKey: serverKey,
      );

  void setTrimBorders(bool enabled, {String? seriesId, String? serverKey}) =>
      _updateConfig(
        seriesId,
        (ReaderConfig c) => c.copyWith(trimBorders: enabled),
        serverKey: serverKey,
      );

  void setSplitWidePages(
    WidePageSplitMode mode, {
    String? seriesId,
    String? serverKey,
  }) => _updateConfig(
    seriesId,
    (ReaderConfig c) => c.copyWith(splitWidePages: mode),
    serverKey: serverKey,
  );

  void setPageTurn(
    ReaderPageTurnChoice choice, {
    String? seriesId,
    String? serverKey,
  }) => _updateConfig(
    seriesId,
    (ReaderConfig c) => c.copyWith(pageTurn: choice),
    serverKey: serverKey,
  );

  /// 点击区预设 / 反转 / 双击缩放（RDR-07）：都随 [ReaderConfig] 支持按系列覆盖。
  void setTapZone(
    TapZonePreset preset, {
    String? seriesId,
    String? serverKey,
  }) => _updateConfig(
    seriesId,
    (ReaderConfig c) => c.copyWith(tapZone: preset),
    serverKey: serverKey,
  );

  void setInvertTapZones(bool enabled, {String? seriesId, String? serverKey}) =>
      _updateConfig(
        seriesId,
        (ReaderConfig c) => c.copyWith(invertTapZones: enabled),
        serverKey: serverKey,
      );

  void setDoubleTapZoom(bool enabled, {String? seriesId, String? serverKey}) =>
      _updateConfig(
        seriesId,
        (ReaderConfig c) => c.copyWith(doubleTapZoom: enabled),
        serverKey: serverKey,
      );

  /// 自动滚动速度 1–10（RDR-08）：随 [ReaderConfig] 走。
  void setAutoScrollSpeed(int speed, {String? seriesId, String? serverKey}) =>
      _updateConfig(
        seriesId,
        (ReaderConfig c) => c.copyWith(autoScrollSpeed: speed.clamp(1, 10)),
        serverKey: serverKey,
      );

  /// 平板默认排版（PLT-02）：全局设置，不进系列覆盖。
  void setTabletLayout(TabletLayoutChoice choice) =>
      _update(state.copyWith(tabletLayout: choice));

  /// chrome 是否显示本次阅读时长（HIS-04）：随 [ReaderConfig] 走。
  void setShowSessionTime(
    bool enabled, {
    String? seriesId,
    String? serverKey,
  }) => _updateConfig(
    seriesId,
    (ReaderConfig c) => c.copyWith(showSessionTime: enabled),
    serverKey: serverKey,
  );

  /// 记住/清除某本书的双页分组起点（RDR-06 / ARC-07）；[index] 为 null 表示恢复自动。
  void setSpreadFrom(String bookId, int? index, {required String serverKey}) =>
      _update(
        state.withSpreadFrom(
          bookId,
          index,
          serverKey: _requireServerKey(serverKey),
        ),
      );

  /// 把某一组设置恢复默认（RDR-04）：只动这一组，其它组不受影响。
  void resetGroup(
    ReaderSettingsGroup group, {
    String? seriesId,
    String? serverKey,
  }) => _updateConfig(
    seriesId,
    (ReaderConfig c) => c.resetGroup(group),
    serverKey: serverKey,
  );

  /// 打开/关闭"按系列记住"（UI-P3-2 / ARC-07 按服务器分区）。
  void setSeriesOverride(
    String seriesId,
    bool enabled, {
    required String serverKey,
  }) {
    final resolvedKey = _requireServerKey(serverKey);
    if (!enabled) {
      if (!state.hasSeriesOverride(seriesId, serverKey: resolvedKey)) return;
      _update(state.withSeriesOverride(seriesId, null, serverKey: resolvedKey));
      return;
    }
    _update(
      state.withSeriesOverride(
        seriesId,
        state.forSeries(seriesId, serverKey: resolvedKey),
        serverKey: resolvedKey,
      ),
    );
  }

  /// 把当前配置存成一个命名预设（UI-P3-1）。
  void savePreset(String name, {String? seriesId, String? serverKey}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final config = seriesId == null
        ? state.global
        : state.forSeries(seriesId, serverKey: _requireServerKey(serverKey));
    final preset = ReaderPreset(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: trimmed,
      config: config,
    );
    _update(state.copyWith(presets: <ReaderPreset>[...state.presets, preset]));
  }

  /// 应用一个预设：直接替换全局 [ReaderConfig] 或指定系列的覆盖。
  void applyPreset(String id, {String? seriesId, String? serverKey}) {
    for (final preset in state.presets) {
      if (preset.id != id) continue;
      if (seriesId != null) {
        _update(
          state.withSeriesOverride(
            seriesId,
            preset.config,
            serverKey: _requireServerKey(serverKey),
          ),
        );
      } else {
        _update(state.copyWith(global: preset.config));
      }
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

  /// 有 seriesId 时只改目标内容源下这个系列的覆盖；没有时改全局 [ReaderConfig]。
  void _updateConfig(
    String? seriesId,
    ReaderConfig Function(ReaderConfig current) change, {
    String? serverKey,
  }) {
    if (seriesId == null) {
      _update(state.copyWith(global: change(state.global)));
      return;
    }
    final resolvedKey = _requireServerKey(serverKey);
    _update(
      state.withSeriesOverride(
        seriesId,
        change(state.forSeries(seriesId, serverKey: resolvedKey)),
        serverKey: resolvedKey,
      ),
    );
  }

  /// 整份替换（SET-02 导入备份）：先落盘再更新 state，导入失败时不留半截。
  Future<void> replaceAll(ReaderPrefs next) async {
    _touched = true;
    await _store.save(next);
    state = next;
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
