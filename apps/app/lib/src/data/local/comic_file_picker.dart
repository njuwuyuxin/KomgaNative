import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// 用户从系统选择器中选中的单个待导入文件（流式读取兼容 Android `content://` URI 与本地路径）。
final class PickedComicFile {
  const PickedComicFile({
    required this.name,
    required this.openRead,
    this.sizeBytes = 0,
  });

  factory PickedComicFile.fromFile(File file, {String? name, int? sizeBytes}) {
    final resolvedName =
        name ?? file.path.replaceAll(r'\', '/').split('/').last;
    return PickedComicFile(
      name: resolvedName,
      openRead: file.openRead,
      sizeBytes: sizeBytes ?? 0,
    );
  }

  final String name;
  final Stream<List<int>> Function() openRead;
  final int sizeBytes;
}

/// 系统漫画文件与文件夹选择抽象（隔离 `file_picker` 插件以便单测离线注入）。
abstract interface class ComicFilePicker {
  /// 选择一个或多个本地漫画压缩包（`.cbz` / `.zip`），或一组图片页文件。
  Future<List<PickedComicFile>> pickArchiveFiles();

  /// 选择一个本地文件夹路径（若平台返回非 `file://` URI，则回退多选该目录下的文件）。
  Future<String?> pickComicDirectory();

  /// 选择一组漫画内页图片以合成为一本本地漫画（兼容 Android SAF 图片目录导入）。
  Future<List<PickedComicFile>> pickImagePages();

  /// 清理系统文件选择器在临时目录留下的拷贝缓存。
  Future<void> clearTemporaryCache();
}

/// 生产实现：调用跨平台 `file_picker` 13.x（见 ADR 0009）。
final class PlatformComicFilePicker implements ComicFilePicker {
  const PlatformComicFilePicker();

  @override
  Future<List<PickedComicFile>> pickArchiveFiles() async {
    // Android 系统文件管理器常将 .cbz 标为 application/octet-stream，
    // 传 FileType.any 防止 .cbz 被置灰；非 Android 平台过滤 cbz/zip。
    final files = Platform.isAndroid
        ? await FilePicker.pickFiles()
        : await FilePicker.pickFiles(
            type: FileType.custom,
            allowedExtensions: const <String>[
              'cbz',
              'zip',
              'epub',
              'cbt',
              'tar',
              'pdf',
              'cbr',
              'rar',
              'cb7',
              '7z',
            ],
          );
    return _mapPlatformFiles(files);
  }

  @override
  Future<String?> pickComicDirectory() async {
    final uri = await FilePicker.pickDirectory();
    if (uri == null) return null;
    if (uri.scheme == 'file') {
      return uri.toFilePath();
    }
    return null;
  }

  @override
  Future<List<PickedComicFile>> pickImagePages() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    return _mapPlatformFiles(files);
  }

  @override
  Future<void> clearTemporaryCache() async {
    try {
      await FilePicker.clearTemporaryFiles();
    } on Exception catch (error) {
      // 平台不支持或清理失败绝不阻断已完成的入库结果。
      debugPrint('ComicFilePicker: clearTemporaryFiles failed: $error');
    }
  }

  static List<PickedComicFile> _mapPlatformFiles(List<PlatformFile> files) {
    if (files.isEmpty) return const <PickedComicFile>[];
    return <PickedComicFile>[
      for (final item in files)
        PickedComicFile(
          name: item.name,
          openRead: item.readAsByteStream,
          sizeBytes: item.lengthSync() ?? 0,
        ),
    ];
  }
}
