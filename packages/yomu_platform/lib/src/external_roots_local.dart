import 'dart:io';

import 'package:yomu_platform/src/external_roots.dart';

/// 普通文件系统目录的树扫描实现（用于桌面端、单测以及 iOS `Files.app` 目录，LMB-08）。
Future<List<ExternalTreeEntry>> listLocalDirectoryTree(String rootPath) async {
  final dir = Directory(rootPath);
  if (!await dir.exists()) return const <ExternalTreeEntry>[];
  final normRoot = _normalizeDirPrefix(dir.path);
  final out = <ExternalTreeEntry>[];

  try {
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      final full = entity.path.replaceAll(r'\', '/');
      final rel = full.startsWith(normRoot)
          ? full.substring(normRoot.length)
          : full.split('/').last;
      if (rel.isEmpty) continue;
      final segments = rel.split('/');
      final name = segments.last;
      final isIcloud = name.startsWith('.') && name.endsWith('.icloud');
      if (!isIcloud && segments.any((s) => s.startsWith('.'))) continue;

      if (entity is Directory) {
        out.add(
          ExternalTreeEntry(
            uri: entity.path,
            relativePath: rel,
            name: name,
            isDirectory: true,
          ),
        );
      } else if (entity is File) {
        final stat = await entity.stat();
        final logicalName = isIcloud ? _stripIcloudStub(name) : name;
        final logicalRel = isIcloud
            ? <String>[
                ...segments.sublist(0, segments.length - 1),
                logicalName,
              ].join('/')
            : rel;
        out.add(
          ExternalTreeEntry(
            uri: entity.path,
            relativePath: logicalRel,
            name: logicalName,
            isDirectory: false,
            sizeBytes: stat.size,
            lastModifiedMs: stat.modified.millisecondsSinceEpoch,
            isCloudPlaceholder: isIcloud,
          ),
        );
      }
    }
  } on FileSystemException {
    return out;
  }
  return out;
}

ExternalTreeEntry? parseExternalTreeEntry(Object? raw) {
  if (raw is! Map<Object?, Object?>) return null;
  final uri = raw['uri'];
  final rel = raw['relativePath'];
  final name = raw['name'];
  if (uri is! String || rel is! String || name is! String) return null;
  return ExternalTreeEntry(
    uri: uri,
    relativePath: rel,
    name: name,
    isDirectory: raw['isDirectory'] == true,
    sizeBytes: (raw['sizeBytes'] as int?) ?? 0,
    lastModifiedMs: (raw['lastModifiedMs'] as int?) ?? 0,
    isCloudPlaceholder: raw['isCloudPlaceholder'] == true,
  );
}

String _stripIcloudStub(String stub) {
  var s = stub;
  if (s.startsWith('.')) s = s.substring(1);
  if (s.endsWith('.icloud')) s = s.substring(0, s.length - '.icloud'.length);
  return s;
}

String _normalizeDirPrefix(String path) {
  final norm = path.replaceAll(r'\', '/');
  return norm.endsWith('/') ? norm : '$norm/';
}
