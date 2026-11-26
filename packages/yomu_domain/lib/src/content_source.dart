/// 多源内容来源标识与能力声明（ADR 0008）。
///
/// 面向「本机 + Komga + 未来 Kavita / OPDS」的可扩展插件化寻址模型，
/// 替代无法扩展第三种协议的二元布尔判断。
library;

/// 本机内置书库的固定分区与来源标识。
const String kLocalSourceKey = 'local://device';

/// 本机书库的默认虚拟库 ID。
const String kLocalLibraryId = 'local://library';

/// 判断给定的 [sourceKey] 是否属于本机书库（空串兼容旧存档与单测默认值）。
bool isLocalSourceKey(String sourceKey) =>
    sourceKey.isEmpty || sourceKey == kLocalSourceKey;

/// 支持或预留的内容源协议种类。
enum SourceKind { local, komga, kavita, opds }

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

  /// Komga 服务器能力：支持整本离线缓存、服务端双向收藏集与远程进度 Outbox 对账。
  static const SourceCapabilities komga = SourceCapabilities(
    canImportLocalFiles: false,
    canMutateCatalog: false,
    canDownloadOffline: true,
    showsNetworkOfflineBanner: true,
    supportsCollections: true,
    syncsProgressRemotely: true,
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

/// 远程服务器内容源（Komga，及后续扩展的 Kavita / OPDS）。
final class RemoteContentSource extends ContentSource {
  const RemoteContentSource({
    required this.sourceKey,
    required this.displayName,
    this.subtitle = '',
    this.kind = SourceKind.komga,
    this.capabilities = SourceCapabilities.komga,
  });

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
