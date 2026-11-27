import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/app_settings.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 当前可用于书架与收藏页分组切换的全部内容源（首项恒为本机源）。
final Provider<List<ContentSource>> availableSourcesProvider =
    Provider<List<ContentSource>>((Ref ref) {
      return ref.watch(sourceRegistryProvider).sources;
    });

/// 管理书架/收藏/搜索当前选中的内容源分组（ADR 0008 不变量 2）。
///
/// 恢复策略（与异步恢复顺序无关，完全幂等确定）：
/// 1. 若持久化了 `activeSourceKey`：为本机键则激活本机源；为远程键且服务器存在则激活该远程源，否则回退本机源；
/// 2. 若 `activeSourceKey == null`（新装或从旧版单源升级）：
///    - 存在已恢复的活动 Komga 会话（老用户升级）→ 默认激活该 Komga 服务器源；
///    - 无服务器会话（新用户首次打开）→ 默认激活 [LocalContentSource]。
class ActiveSourceController extends Notifier<ContentSource> {
  bool _manualTouched = false;
  bool _restored = false;
  String? _persistedKey;
  final ValueNotifier<bool> _restoring = ValueNotifier<bool>(false);

  /// 冷启动持久化源与会话尚未完成对账时为 `true`（N8）。
  ///
  /// 测试桩子类若覆写 [build] 且不调用 `super.build()`，默认值为 `false`（立即可用）。
  ValueListenable<bool> get restoringListenable => _restoring;

  @override
  ContentSource build() {
    ref.onDispose(_restoring.dispose);
    final initialSession = ref.read(sessionProvider);
    // 同步触发 serverListProvider 预热，使多服务器注册表尽快就绪。
    ref.read(serverListProvider);
    ref.listen<SessionState>(sessionProvider, _onSessionChanged);
    ref.listen<SourceRegistry>(sourceRegistryProvider, _onRegistryChanged);
    ref.listen<AsyncValue<Object?>>(serverListProvider, (_, _) {
      unawaited(
        Future<void>.microtask(() {
          if (ref.mounted) _reconcile();
        }),
      );
    });
    _restoring.value = initialSession is! SessionConnected;
    unawaited(_restore());
    if (initialSession is SessionConnected) {
      return remoteSourceOfServer(initialSession.server);
    }
    return const LocalContentSource();
  }

  SettingsStore get _settingsStore => ref.read(settingsStoreProvider);

  Future<void> _restore() async {
    try {
      final saved = await _settingsStore.load();
      if (!ref.mounted) return;
      _restored = true;
      if (!_manualTouched) {
        _persistedKey = saved.activeSourceKey;
      }
      _reconcile();
    } on Exception {
      _restored = true;
      if (ref.mounted) _reconcile();
    }
  }

  void _onSessionChanged(SessionState? previous, SessionState next) {
    // 区分「冷启动钥匙串恢复（previous is SessionLoading）」与「用户运行期主动登录/切服」：
    if (previous is! SessionLoading && next is SessionConnected) {
      final switchedServer =
          previous is! SessionConnected || previous.server.id != next.server.id;
      if (switchedServer) {
        _manualTouched = true;
        _persistedKey = next.server.id;
        state = remoteSourceOfServer(next.server);
        _restoring.value = false;
        unawaited(_persistSourceKey(next.server.id));
        return;
      }
    }

    if (next is SessionDisconnected && previous is SessionConnected) {
      if (state.sourceKey == previous.server.id) {
        _manualTouched = true;
        _persistedKey = kLocalSourceKey;
        state = const LocalContentSource();
        _restoring.value = false;
        unawaited(_persistSourceKey(kLocalSourceKey));
        return;
      }
    }

    _reconcile();
  }

  void _onRegistryChanged(SourceRegistry? _, SourceRegistry _) {
    unawaited(
      Future<void>.microtask(() {
        if (ref.mounted) _reconcile();
      }),
    );
  }

  void _setStateIfChanged(ContentSource next) {
    if (state == next) return;
    state = next;
  }

  void _reconcile() {
    final registry = ref.read(sourceRegistryProvider);
    final session = ref.read(sessionProvider);
    // 手动选择同样会更新 `_persistedKey`；统一读取 `_persistedKey` 可保证：
    // 若用户选择目标源时注册表尚未就绪，待 `serverListProvider` 加载完毕后立刻生效而无需冷启动（P3）。
    final desiredKey = _persistedKey;

    if (desiredKey == null) {
      if (!_restored) return;
      if (session is SessionConnected) {
        _setStateIfChanged(remoteSourceOfServer(session.server));
        _restoring.value = false;
      } else if (session is! SessionLoading) {
        _setStateIfChanged(const LocalContentSource());
        _restoring.value = false;
      }
      return;
    }

    if (isLocalSourceKey(desiredKey)) {
      _setStateIfChanged(const LocalContentSource());
      _restoring.value = false;
      return;
    }

    // 仅查轻量描述符，绝不在此触发远程会话或仓库连接池创建（P3）。
    final remoteSource = registry.remoteSourceOrNull(desiredKey);
    if (remoteSource != null) {
      _setStateIfChanged(remoteSource);
      _restoring.value = false;
      return;
    }

    // 若注册表和会话均已加载完毕但找不到目标服务器（已被删除），回退本机源。
    final listSettled = !ref.read(serverListProvider).isLoading;
    if (_restored && session is! SessionLoading && listSettled) {
      _setStateIfChanged(const LocalContentSource());
      _restoring.value = false;
    }
  }

  /// 用户在书架/收藏分组栏主动切换内容源。
  Future<void> selectSource(String sourceKey) async {
    _manualTouched = true;
    if (isLocalSourceKey(sourceKey)) {
      _persistedKey = kLocalSourceKey;
      state = const LocalContentSource();
      _restoring.value = false;
      await _persistSourceKey(kLocalSourceKey);
      return;
    }

    _persistedKey = sourceKey;
    final registry = ref.read(sourceRegistryProvider);
    final remoteSource = registry.remoteSourceOrNull(sourceKey);
    if (remoteSource != null) {
      state = remoteSource;
      _restoring.value = false;
    } else {
      _restoring.value = true;
    }
    await _persistSourceKey(sourceKey);
  }

  Future<void> _persistSourceKey(String key) {
    return _settingsStore.update(
      (AppSettings s) => s.copyWith(activeSourceKey: key),
    );
  }
}

final NotifierProvider<ActiveSourceController, ContentSource>
activeSourceProvider = NotifierProvider<ActiveSourceController, ContentSource>(
  ActiveSourceController.new,
);

/// 当前是否正处于冷启动恢复持久化的活动源阶段（N8）。
final Provider<bool> activeSourceRestoringProvider = Provider<bool>((Ref ref) {
  final ctrl = ref.watch(activeSourceProvider.notifier);
  void onChanged() => ref.invalidateSelf();
  ctrl.restoringListenable.addListener(onChanged);
  ref.onDispose(() => ctrl.restoringListenable.removeListener(onChanged));
  return ctrl.restoringListenable.value;
});

/// 当前激活内容源对应的 [SourceBundle]（冷启动未恢复、源未就绪或已被删除时返回 `null`，绝不静默回退本机源）。
final Provider<SourceBundle?> activeSourceBundleProvider =
    Provider<SourceBundle?>((Ref ref) {
      if (ref.watch(activeSourceRestoringProvider)) return null;
      final active = ref.watch(activeSourceProvider);
      final registry = ref.watch(sourceRegistryProvider);
      return registry.bundleOrNull(active.sourceKey);
    });
