import 'dart:io';

import 'package:flutter/services.dart';
import 'package:yomu_platform/src/external_roots_local.dart';

/// 外部挂载目录的底层权限介质类型（LMB-08）。
enum ExternalRootKind { androidSaf, iosBookmark, localDirectory }

/// 已挂载的外部漫画根目录元数据。
final class MountedExternalRoot {
  const MountedExternalRoot({
    required this.id,
    required this.displayName,
    required this.uriOrBookmark,
    required this.kind,
    this.hasNomedia = false,
    this.permissionValid = true,
  });

  final String id;
  final String displayName;

  /// Android SAF `content://` 树 URI、iOS Security-Scoped Bookmark（Base64）或普通路径。
  final String uriOrBookmark;
  final ExternalRootKind kind;
  final bool hasNomedia;
  final bool permissionValid;
}

/// 外部目录树扫描出的单个条目（支持识别 iOS `.icloud` 云端占位文件）。
final class ExternalTreeEntry {
  const ExternalTreeEntry({
    required this.uri,
    required this.relativePath,
    required this.name,
    required this.isDirectory,
    this.sizeBytes = 0,
    this.lastModifiedMs = 0,
    this.isCloudPlaceholder = false,
  });

  final String uri;
  final String relativePath;
  final String name;
  final bool isDirectory;
  final int sizeBytes;
  final int lastModifiedMs;
  final bool isCloudPlaceholder;
}

/// 外部目录原位挂载与随机字节读取平台桥接（LMB-08）。
abstract interface class ExternalRootsBridge {
  /// 拉起系统目录选择器（Android SAF / iOS Folder Picker）并持久化授权；取消返回 `null`。
  Future<MountedExternalRoot?> pickDirectory();

  /// 递归枚举挂载根目录下的文件与目录条目（跳过隐藏项，感知 `.nomedia` 与 `.icloud`）。
  Future<List<ExternalTreeEntry>> listTree(MountedExternalRoot root);

  /// 校验持久化授权是否依然有效（防止用户撤销权限或外置卡拔出）。
  Future<bool> checkPermission(MountedExternalRoot root);

  /// 在挂载根目录下确保存在 `.nomedia` 标记文件（防止 Android 系统相册扫描漫画页图）。
  Future<bool> ensureNomedia(MountedExternalRoot root);

  /// 原位读取外部文件总字节数（零拷贝，用于构建 `RandomAccessByteSource`）。
  Future<int?> fileLength(String uri, {MountedExternalRoot? root});

  /// 原位读取外部文件 `[offset, offset + length)` 区间字节（零拷贝随机访问）。
  Future<Uint8List?> readFileRange(
    String uri,
    int offset,
    int length, {
    MountedExternalRoot? root,
  });

  /// iOS iCloud 占位文件触发按需下载；其余平台返回 `false`。
  Future<bool> triggerCloudDownload(String uri, {MountedExternalRoot? root});

  /// 卸载目录时释放持久化权限。
  Future<void> releasePermission(MountedExternalRoot root);
}

/// 基于 `yomu/external_roots` MethodChannel + 普通文件系统本地目录兜底的实现。
class ChannelExternalRootsBridge implements ExternalRootsBridge {
  ChannelExternalRootsBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('yomu/external_roots');

  final MethodChannel _channel;

  @override
  Future<MountedExternalRoot?> pickDirectory() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'pickDirectory',
      );
      if (raw == null) return null;
      final uri = raw['uriOrBookmark'];
      final name = raw['displayName'];
      final kindRaw = raw['kind'];
      if (uri is! String || uri.isEmpty) return null;
      final kind = switch (kindRaw) {
        'androidSaf' => ExternalRootKind.androidSaf,
        'iosBookmark' => ExternalRootKind.iosBookmark,
        _ => ExternalRootKind.localDirectory,
      };
      return MountedExternalRoot(
        id: 'root_${DateTime.now().microsecondsSinceEpoch}',
        displayName: (name is String && name.trim().isNotEmpty)
            ? name.trim()
            : uri.replaceAll(r'\', '/').split('/').last,
        uriOrBookmark: uri,
        kind: kind,
        hasNomedia: raw['hasNomedia'] == true,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<List<ExternalTreeEntry>> listTree(MountedExternalRoot root) async {
    if (root.kind == ExternalRootKind.localDirectory) {
      return listLocalDirectoryTree(root.uriOrBookmark);
    }
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'listTree',
        <String, Object?>{
          'uriOrBookmark': root.uriOrBookmark,
          'kind': root.kind.name,
        },
      );
      if (raw == null) return const <ExternalTreeEntry>[];
      return <ExternalTreeEntry>[
        for (final item in raw)
          if (parseExternalTreeEntry(item) case final ExternalTreeEntry e) e,
      ];
    } on MissingPluginException {
      return const <ExternalTreeEntry>[];
    } on PlatformException {
      return const <ExternalTreeEntry>[];
    }
  }

  @override
  Future<bool> checkPermission(MountedExternalRoot root) async {
    if (root.kind == ExternalRootKind.localDirectory) {
      return Directory(root.uriOrBookmark).exists();
    }
    try {
      final ok = await _channel.invokeMethod<bool>(
        'checkPermission',
        <String, Object?>{
          'uriOrBookmark': root.uriOrBookmark,
          'kind': root.kind.name,
        },
      );
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> ensureNomedia(MountedExternalRoot root) async {
    if (root.kind == ExternalRootKind.localDirectory) {
      try {
        final marker = File('${root.uriOrBookmark}/.nomedia');
        if (!await marker.exists()) {
          await marker.create(recursive: true);
        }
        return true;
      } on FileSystemException {
        return false;
      }
    }
    try {
      final ok = await _channel.invokeMethod<bool>(
        'ensureNomedia',
        <String, Object?>{
          'uriOrBookmark': root.uriOrBookmark,
          'kind': root.kind.name,
        },
      );
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<int?> fileLength(String uri, {MountedExternalRoot? root}) async {
    if (!uri.startsWith('content://') &&
        (root == null || root.kind == ExternalRootKind.localDirectory)) {
      try {
        return await File(uri).length();
      } on FileSystemException {
        return null;
      }
    }
    try {
      return await _channel.invokeMethod<int>('fileLength', <String, Object?>{
        'uri': uri,
        'rootUriOrBookmark': root?.uriOrBookmark,
        'kind': root?.kind.name,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<Uint8List?> readFileRange(
    String uri,
    int offset,
    int length, {
    MountedExternalRoot? root,
  }) async {
    if (length <= 0) return Uint8List(0);
    if (!uri.startsWith('content://') &&
        (root == null || root.kind == ExternalRootKind.localDirectory)) {
      RandomAccessFile? raf;
      try {
        raf = await File(uri).open();
        await raf.setPosition(offset);
        return await raf.read(length);
      } on FileSystemException {
        return null;
      } finally {
        await raf?.close();
      }
    }
    try {
      return await _channel.invokeMethod<Uint8List>(
        'readFileRange',
        <String, Object?>{
          'uri': uri,
          'offset': offset,
          'length': length,
          'rootUriOrBookmark': root?.uriOrBookmark,
          'kind': root?.kind.name,
        },
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> triggerCloudDownload(
    String uri, {
    MountedExternalRoot? root,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'triggerCloudDownload',
        <String, Object?>{
          'uri': uri,
          'rootUriOrBookmark': root?.uriOrBookmark,
          'kind': root?.kind.name,
        },
      );
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> releasePermission(MountedExternalRoot root) async {
    if (root.kind == ExternalRootKind.localDirectory) return;
    try {
      await _channel.invokeMethod<void>('releasePermission', <String, Object?>{
        'uriOrBookmark': root.uriOrBookmark,
        'kind': root.kind.name,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
