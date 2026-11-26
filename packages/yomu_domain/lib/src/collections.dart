/// Komga 的"收藏集"（Collection）与"阅读列表"（ReadList）。
///
/// 两者都是服务端维护的策展集合：
/// - Collection = 一组系列（按系列 id 排序）；
/// - ReadList = 一组书（可以跨系列，按书 id 排序）。
library;

/// 收藏集：一组系列。
class KomgaCollection {
  const KomgaCollection({
    required this.id,
    required this.name,
    required this.ordered,
    required this.seriesIds,
    this.createdDate,
    this.lastModifiedDate,
  });

  final String id;
  final String name;

  /// 用户是否手动指定了系列顺序。
  final bool ordered;

  final List<String> seriesIds;
  final DateTime? createdDate;
  final DateTime? lastModifiedDate;

  int get seriesCount => seriesIds.length;

  @override
  String toString() =>
      'KomgaCollection($id, $name, ${seriesIds.length} series)';
}

/// 阅读列表：一组书。
class ReadList {
  const ReadList({
    required this.id,
    required this.name,
    required this.summary,
    required this.ordered,
    required this.bookIds,
    this.createdDate,
    this.lastModifiedDate,
  });

  final String id;
  final String name;
  final String summary;
  final bool ordered;
  final List<String> bookIds;
  final DateTime? createdDate;
  final DateTime? lastModifiedDate;

  int get bookCount => bookIds.length;

  @override
  String toString() => 'ReadList($id, $name, ${bookIds.length} books)';
}
