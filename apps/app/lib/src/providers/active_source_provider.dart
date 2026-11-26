import 'dart:async';

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

  @override
  ContentSource build() {
    final initialSession = ref.read(sessionProvider);
    // 同步触发 serverListProvider 预热，使多服务器注册表尽快就绪。
    ref.read(serverListProvider);
    ref.listen<SessionState>(sessionProvider, _onSessionChanged);
    ref.listen<SourceRegistry>(sourceRegistryProvider, _onRegistryChanged);
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
    } on Object {
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
        unawaited(_persistSourceKey(next.server.id));
        return;
      }
    }

    if (next is SessionDisconnected && previous is SessionConnected) {
      if (state.sourceKey == previous.server.id) {
        _manualTouched = true;
        _persistedKey = kLocalSourceKey;
        state = const LocalContentSource();
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
    final desiredKey = _manualTouched ? state.sourceKey : _persistedKey;

    if (desiredKey == null) {
      if (session is SessionConnected) {
        _setStateIfChanged(remoteSourceOfServer(session.server));
      } else if (_restored && session is! SessionLoading) {
        _setStateIfChanged(const LocalContentSource());
      }
      return;
    }

    if (isLocalSourceKey(desiredKey)) {
      _setStateIfChanged(const LocalContentSource());
      return;
    }

    final remote = registry.remoteBundleOrNull(desiredKey);
    if (remote != null) {
      _setStateIfChanged(remote.source);
      return;
    }

    // 若注册表和会话均已加载完毕但找不到目标服务器（已被删除），回退本机源。
    final listLoaded = ref.read(serverListProvider).hasValue;
    if (_restored && session is! SessionLoading && listLoaded) {
      _setStateIfChanged(const LocalContentSource());
    }
  }

  /// 用户在书架/收藏分组栏主动切换内容源。
  Future<void> selectSource(String sourceKey) async {
    _manualTouched = true;
    if (isLocalSourceKey(sourceKey)) {
      _persistedKey = kLocalSourceKey;
      state = const LocalContentSource();
      await _persistSourceKey(kLocalSourceKey);
      return;
    }

    _persistedKey = sourceKey;
    final registry = ref.read(sourceRegistryProvider);
    final bundle = registry.remoteBundleOrNull(sourceKey);
    if (bundle != null) {
      state = bundle.source;
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

/// 当前激活内容源对应的 [SourceBundle]。
final Provider<SourceBundle> activeSourceBundleProvider =
    Provider<SourceBundle>((Ref ref) {
      final active = ref.watch(activeSourceProvider);
      final registry = ref.watch(sourceRegistryProvider);
      return registry.bundleFor(active.sourceKey);
    });
