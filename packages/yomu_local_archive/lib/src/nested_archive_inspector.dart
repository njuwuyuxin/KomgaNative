import 'package:yomu_local_archive/src/archive_errors.dart';
import 'package:yomu_local_archive/src/byte_source.dart';
import 'package:yomu_local_archive/src/natural_sort.dart';
import 'package:yomu_local_archive/src/zip_directory.dart';

/// 判断归档内路径是否属于受支持的漫画子归档文件（`.cbz/.zip/.epub/.cbt/.tar`）。
bool isNestedComicArchivePath(String rawPath) {
  final norm = rawPath.replaceAll(r'\', '/');
  if (norm.isEmpty || norm.endsWith('/')) return false;
  final segments = norm.split('/');
  for (final seg in segments) {
    if (seg.isEmpty) continue;
    if (seg == '__MACOSX' || seg.startsWith('.')) return false;
  }
  final lower = segments.last.toLowerCase();
  return lower.endsWith('.cbz') ||
      lower.endsWith('.zip') ||
      lower.endsWith('.epub') ||
      lower.endsWith('.cbt') ||
      lower.endsWith('.tar');
}

/// 检测给定 ZIP 是否为「嵌套合集包」（内部不含直接漫画图片页，但包含多个子漫画归档，LMB-06）。
///
/// 返回按自然序排列的子归档条目列表；若不是嵌套合集包或不是合法 ZIP，返回空列表。
Future<List<ZipEntryInfo>> inspectNestedZipArchives(
  RandomAccessByteSource source,
) async {
  final List<ZipEntryInfo> entries;
  try {
    entries = await readZipCentralDirectory(source);
  } on ArchiveException {
    return const <ZipEntryInfo>[];
  }

  final nested = <ZipEntryInfo>[];
  for (final entry in entries) {
    if (entry.isDirectory) continue;
    if (isSupportedComicImagePath(entry.name)) {
      // 含直接漫画图片：属于普通单本漫画包，不走合集拆包。
      return const <ZipEntryInfo>[];
    }
    if (isNestedComicArchivePath(entry.name)) {
      nested.add(entry);
    }
  }

  nested.sort((a, b) => naturalCompare(a.name, b.name));
  return List<ZipEntryInfo>.unmodifiable(nested);
}
