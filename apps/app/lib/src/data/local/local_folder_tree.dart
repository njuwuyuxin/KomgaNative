import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

/// 文件夹树视图中的单册漫画节点项（LMB-10）。
final class LocalFolderBookItem {
  const LocalFolderBookItem({
    required this.book,
    required this.direction,
    required this.folderSegments,
    this.numberSort = 0,
    this.isCloudPlaceholder = false,
  });

  final Book book;
  final ReadingDirection direction;

  /// 从逻辑根目录起的父文件夹路径段（例如 `['SD Comics', '少年漫', '芙莉莲']`）。
  final List<String> folderSegments;
  final double numberSort;
  final bool isCloudPlaceholder;
}

/// 不可变文件夹树节点（任意层级，天然排序，含递归册数统计）。
final class LocalFolderNode {
  const LocalFolderNode({
    required this.path,
    required this.name,
    required this.subfolders,
    required this.books,
    required this.totalBooksCount,
  });

  /// 规范化路径键（根节点为空串 `''`）。
  final String path;
  final String name;
  final List<LocalFolderNode> subfolders;
  final List<LocalFolderBookItem> books;
  final int totalBooksCount;

  bool get isEmpty => subfolders.isEmpty && books.isEmpty;
}

/// 根据每本书的逻辑目录路径段构建自然排序的文件夹树（LMB-10）。
LocalFolderNode buildLocalFolderTree(List<LocalFolderBookItem> items) {
  final root = _MutableFolder(path: '', name: '');

  for (final item in items) {
    var cursor = root;
    for (final rawSeg in item.folderSegments) {
      final seg = rawSeg.trim();
      if (seg.isEmpty) continue;
      final childPath = cursor.path.isEmpty ? seg : '${cursor.path}/$seg';
      cursor = cursor.children.putIfAbsent(
        seg,
        () => _MutableFolder(path: childPath, name: seg),
      );
    }
    cursor.books.add(item);
  }

  return root.freeze();
}

/// 按面包屑路径段定位目标文件夹节点；路径失效时安全回退到最深有效祖先或根节点。
({LocalFolderNode node, List<String> resolvedPath}) resolveFolderNode(
  LocalFolderNode root,
  List<String> breadcrumb,
) {
  var current = root;
  final resolved = <String>[];
  for (final seg in breadcrumb) {
    LocalFolderNode? match;
    for (final child in current.subfolders) {
      if (child.name == seg) {
        match = child;
        break;
      }
    }
    if (match == null) break;
    current = match;
    resolved.add(seg);
  }
  return (node: current, resolvedPath: resolved);
}

/// 为数据库记录推导文件夹树路径段：
/// - 外部原位挂载书：`[rootDisplayName, ...sourceRelativePath 的父目录]`；
/// - 受管沙盒导入书：`[importedGroupLabel, seriesTitle]`。
List<String> folderSegmentsForLocalBook({
  required String? mountRootId,
  required String? sourceRelativePath,
  required String? mountRootDisplayName,
  required String seriesTitle,
  required String importedGroupLabel,
}) {
  if (mountRootId != null &&
      sourceRelativePath != null &&
      sourceRelativePath.trim().isNotEmpty) {
    final norm = sourceRelativePath.replaceAll(r'\', '/');
    final parts = norm
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final parentDirs = parts.length > 1
        ? parts.sublist(0, parts.length - 1)
        : const <String>[];
    final rootName =
        (mountRootDisplayName != null && mountRootDisplayName.trim().isNotEmpty)
        ? mountRootDisplayName.trim()
        : mountRootId;
    return <String>[rootName, ...parentDirs];
  }

  final cleanSeries = seriesTitle.trim();
  return <String>[importedGroupLabel, if (cleanSeries.isNotEmpty) cleanSeries];
}

final class _MutableFolder {
  _MutableFolder({required this.path, required this.name});

  final String path;
  final String name;
  final Map<String, _MutableFolder> children = <String, _MutableFolder>{};
  final List<LocalFolderBookItem> books = <LocalFolderBookItem>[];

  LocalFolderNode freeze() {
    final sortedSubfolders = children.values.map((c) => c.freeze()).toList()
      ..sort((a, b) => naturalCompare(a.name, b.name));
    final sortedBooks = List<LocalFolderBookItem>.of(books)
      ..sort((a, b) {
        final bySort = a.numberSort.compareTo(b.numberSort);
        if (bySort != 0) return bySort;
        return naturalCompare(a.book.name, b.book.name);
      });

    var total = sortedBooks.length;
    for (final child in sortedSubfolders) {
      total += child.totalBooksCount;
    }
    return LocalFolderNode(
      path: path,
      name: name,
      subfolders: List<LocalFolderNode>.unmodifiable(sortedSubfolders),
      books: List<LocalFolderBookItem>.unmodifiable(sortedBooks),
      totalBooksCount: total,
    );
  }
}
