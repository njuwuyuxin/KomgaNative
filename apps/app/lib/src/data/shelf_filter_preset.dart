import 'package:komga_domain/komga_domain.dart';

/// 一组命名的书架筛选条件（LIB-04）：排序 + 阅读状态 + 库。
///
/// 为什么把三者打包而不是只存排序：用户的实际用法是"我常看某库的未读，
/// 按最近添加排"，单存一项等于每次还要手动拨另外两项。
class ShelfFilterPreset {
  const ShelfFilterPreset({
    required this.id,
    required this.name,
    this.sort,
    this.readStatus,
    this.libraryId,
  });

  final String id;
  final String name;
  final SeriesSort? sort;
  final SeriesReadStatus? readStatus;
  final String? libraryId;

  /// 三项都为空：这个组合等于"没有筛选"，存了也没意义。
  bool get isEmpty => sort == null && readStatus == null && libraryId == null;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    if (sort != null) 'sort': sort!.name,
    if (readStatus != null) 'readStatus': readStatus!.name,
    if (libraryId != null) 'libraryId': libraryId,
  };

  /// 从存档解析一条；坏条目返回 null（调用方直接丢掉，不影响其它条）。
  static ShelfFilterPreset? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    return ShelfFilterPreset(
      id: id,
      name: name,
      sort: _enumByName(SeriesSort.values, raw['sort']),
      readStatus: _enumByName(SeriesReadStatus.values, raw['readStatus']),
      libraryId:
          raw['libraryId'] is String && (raw['libraryId'] as String).isNotEmpty
          ? raw['libraryId'] as String
          : null,
    );
  }

  static T? _enumByName<T extends Enum>(List<T> values, Object? raw) {
    if (raw is! String) return null;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ShelfFilterPreset &&
      other.id == id &&
      other.name == name &&
      other.sort == sort &&
      other.readStatus == readStatus &&
      other.libraryId == libraryId;

  @override
  int get hashCode => Object.hash(id, name, sort, readStatus, libraryId);
}
