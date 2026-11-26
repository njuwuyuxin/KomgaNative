/// 收藏集（Collection）与阅读列表（ReadList）领域模型。
///
/// 在本机源与远程服务器源（如 Komga）下共用同一套结构：
/// - Collection = 一组系列（按系列 id 组织）；
/// - ReadList = 一组书（可以跨系列，按书 id 组织）。
library;

import 'package:yomu_domain/src/content_source.dart';

/// 收藏集：一组系列。
class Collection {
  const Collection({
    required this.id,
    required this.name,
    required this.ordered,
    required this.seriesIds,
    this.createdDate,
    this.lastModifiedDate,
    this.sourceKey = kLocalSourceKey,
  });

  final String id;
  final String name;
  final bool ordered;
  final List<String> seriesIds;
  final DateTime? createdDate;
  final DateTime? lastModifiedDate;
  final String sourceKey;

  bool get isCloud => !isLocalSourceKey(sourceKey);

  int get seriesCount => seriesIds.length;

  Collection withSource(String nextSourceKey) => Collection(
    id: id,
    name: name,
    ordered: ordered,
    seriesIds: seriesIds,
    createdDate: createdDate,
    lastModifiedDate: lastModifiedDate,
    sourceKey: nextSourceKey,
  );

  @override
  String toString() => 'Collection($id, $name, ${seriesIds.length} series)';
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
    this.sourceKey = kLocalSourceKey,
  });

  final String id;
  final String name;
  final String summary;
  final bool ordered;
  final List<String> bookIds;
  final DateTime? createdDate;
  final DateTime? lastModifiedDate;
  final String sourceKey;

  bool get isCloud => !isLocalSourceKey(sourceKey);

  int get bookCount => bookIds.length;

  ReadList withSource(String nextSourceKey) => ReadList(
    id: id,
    name: name,
    summary: summary,
    ordered: ordered,
    bookIds: bookIds,
    createdDate: createdDate,
    lastModifiedDate: lastModifiedDate,
    sourceKey: nextSourceKey,
  );

  @override
  String toString() => 'ReadList($id, $name, ${bookIds.length} books)';
}
