import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

/// 本地受管漫画存储根目录解析器（生产指向 `<ApplicationSupport>/local_comics`，单测注入临时目录）。
final class LocalComicsStorage {
  LocalComicsStorage({Future<Directory> Function()? rootResolver})
    : _rootResolver = rootResolver ?? _defaultRoot;

  final Future<Directory> Function() _rootResolver;

  static Future<Directory> _defaultRoot() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/local_comics');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> rootDirectory() async {
    final dir = await _rootResolver();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> resolveFile(String relativePath) async {
    final clean = _sanitizeRelativePath(relativePath);
    final root = await rootDirectory();
    final rootNorm = root.path.replaceAll(r'\', '/');
    final prefix = rootNorm.endsWith('/') ? rootNorm : '$rootNorm/';
    return File('$prefix$clean');
  }

  Future<Directory> resolveDirectory(String relativePath) async {
    final clean = _sanitizeRelativePath(relativePath);
    final root = await rootDirectory();
    final rootNorm = root.path.replaceAll(r'\', '/');
    final prefix = rootNorm.endsWith('/') ? rootNorm : '$rootNorm/';
    return Directory('$prefix$clean');
  }

  static String _sanitizeRelativePath(String raw) {
    final norm = raw.replaceAll(r'\', '/').trim();
    final stripped = norm.startsWith('/') ? norm.substring(1) : norm;
    final parts = stripped.split('/');
    if (stripped.isEmpty || parts.contains('..')) {
      throw const ArchiveException(
        ArchiveErrorKind.corruptedArchive,
        'Invalid local relative path',
      );
    }
    return stripped;
  }
}

/// 将底层本地归档异常映射为 UI 可识别的 [ShelfFailure]。
ShelfFailure shelfFailureFromArchive(ArchiveException error) {
  return switch (error.kind) {
    ArchiveErrorKind.ioError ||
    ArchiveErrorKind.pageOutOfRange => const NotFoundFailure(),
    ArchiveErrorKind.emptyFile ||
    ArchiveErrorKind.unsupportedContainer ||
    ArchiveErrorKind.corruptedArchive ||
    ArchiveErrorKind.encryptedArchive ||
    ArchiveErrorKind.unsupportedCompression ||
    ArchiveErrorKind.noImages => UnexpectedFailure(error.toString()),
  };
}
