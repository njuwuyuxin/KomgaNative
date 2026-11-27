/// 多源内容来源标识与能力声明（ADR 0008）。
///
/// 面向「本机 + Komga + 未来 Kavita / OPDS」的可扩展插件化寻址模型，
/// 替代无法扩展第三种协议的二元布尔判断。
library;

/// 本机内置书库的固定分区与来源标识。
const String kLocalSourceKey = 'local://device';

/// 本机书库的默认虚拟库 ID。
const String kLocalLibraryId = 'local://library';

/// 判断给定的 [sourceKey] 是否为本机书库标识。
///
/// 空串 `''` 不合法且不再隐式等同于本机；历史存档的空 `scope` 应在数据库迁移阶段补齐为 [kLocalSourceKey]。
bool isLocalSourceKey(String sourceKey) => sourceKey == kLocalSourceKey;

/// 支持或预留的内容源协议种类。
enum SourceKind {
  local,
  komga,
  kavita,
  opds;

  /// 从持久化字符串解析协议种类；空或未知值默认回退 [SourceKind.komga] 以兼容老版本存档。
  static SourceKind parse(String? raw) {
    for (final kind in values) {
      if (kind.name == raw) return kind;
    }
    return SourceKind.komga;
  }
}

/// 某个内容源对上层 UI 声明的静态能力位。
final class SourceCapabilities {
  const SourceCapabilities({
    required this.canImportLocalFiles,
    required this.canMutateCatalog,
    required this.canDownloadOffline,
    required this.showsNetworkOfflineBanner,
    required this.supportsCollections,
    required this.syncsProgressRemotely,
  });

  /// 本机书库默认能力：可导入、可编辑删除、支持本地收藏集，无需离线下载与断网横幅。
  static const SourceCapabilities local = SourceCapabilities(
    canImportLocalFiles: true,
    canMutateCatalog: true,
    canDownloadOffline: false,
    showsNetworkOfflineBanner: false,
    supportsCollections: true,
    syncsProgressRemotely: false,
  );

  /// 双向同步型远程服务器能力：支持整本离线缓存、服务端收藏集与远程进度 Outbox 对账。
  static const SourceCapabilities remoteSync = SourceCapabilities(
    canImportLocalFiles: false,
    canMutateCatalog: false,
    canDownloadOffline: true,
    showsNetworkOfflineBanner: true,
    supportsCollections: true,
    syncsProgressRemotely: true,
  );

  /// 只读远程目录源能力（如 OPDS）：支持目录浏览与离线下载，不支持远程收藏集变更或进度同步。
  static const SourceCapabilities remoteReadOnly = SourceCapabilities(
    canImportLocalFiles: false,
    canMutateCatalog: false,
    canDownloadOffline: true,
    showsNetworkOfflineBanner: true,
    supportsCollections: false,
    syncsProgressRemotely: false,
  );

  /// 按协议种类返回默认能力声明。
  static SourceCapabilities forKind(SourceKind kind) => switch (kind) {
    SourceKind.local => local,
    SourceKind.komga || SourceKind.kavita => remoteSync,
    SourceKind.opds => remoteReadOnly,
  };

  /// 未知或已移除内容源的最保守能力集（全部能力关闭，避免误判为可下载或可远程同步）。
  static const SourceCapabilities none = SourceCapabilities(
    canImportLocalFiles: false,
    canMutateCatalog: false,
    canDownloadOffline: false,
    showsNetworkOfflineBanner: false,
    supportsCollections: false,
    syncsProgressRemotely: false,
  );

  final bool canImportLocalFiles;
  final bool canMutateCatalog;
  final bool canDownloadOffline;
  final bool showsNetworkOfflineBanner;
  final bool supportsCollections;
  final bool syncsProgressRemotely;
}

/// 书库内容源描述符（密封类型）。
sealed class ContentSource {
  const ContentSource();

  /// 全局唯一的稳定分区键（本机为 [kLocalSourceKey]，Komga 为规范化 `baseUrl`）。
  String get sourceKey;

  SourceKind get kind;

  SourceCapabilities get capabilities;

  bool get isCloud => kind != SourceKind.local;
}

/// 常驻内置的本机书库源（无需登录，不可移除）。
final class LocalContentSource extends ContentSource {
  const LocalContentSource();

  @override
  String get sourceKey => kLocalSourceKey;

  @override
  SourceKind get kind => SourceKind.local;

  @override
  SourceCapabilities get capabilities => SourceCapabilities.local;

  @override
  bool operator ==(Object other) => other is LocalContentSource;

  @override
  int get hashCode => kLocalSourceKey.hashCode;
}

/// 远程服务器内容源（协议插件提供具体实现）。
final class RemoteContentSource extends ContentSource {
  const RemoteContentSource({
    required this.sourceKey,
    required this.displayName,
    this.subtitle = '',
    this.kind = SourceKind.komga,
    this.capabilities = SourceCapabilities.remoteSync,
  }) : assert(
         sourceKey.length > 0 && sourceKey != kLocalSourceKey,
         'RemoteContentSource.sourceKey must be a non-empty remote key',
       );

  @override
  final String sourceKey;

  final String displayName;
  final String subtitle;

  @override
  final SourceKind kind;

  @override
  final SourceCapabilities capabilities;

  @override
  bool operator ==(Object other) =>
      other is RemoteContentSource &&
      other.sourceKey == sourceKey &&
      other.kind == kind &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(sourceKey, kind, displayName);
}
