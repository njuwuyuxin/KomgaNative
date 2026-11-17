/// 书架查询参数（排序、阅读状态筛选）。
///
/// 只列**已对真实 Komga 1.30.1 验证过**的取值，证据与复现命令见
/// `docs/series-queries.md`：多写一个没验证的键，用户点下去要么 400，
/// 要么得到顺序诡异的列表——比没有这个功能更糟。
///
/// 这里是语言无关的枚举；API 的 wire 值（`metadata.titleSort,asc` 等）
/// 由 `komga_api` 负责映射，UI 文案由界面层负责（将来接 i18n）。
library;

/// 书架排序方式。
enum SeriesSort {
  /// 标题升序（按 Komga 的 titleSort，忽略 `The ` 之类前缀）。
  titleAsc,

  /// 标题降序。
  titleDesc,

  /// 最近添加。
  recentlyAdded,

  /// 最近阅读。
  recentlyRead,
}

/// 阅读状态筛选；`null` 表示不筛选。
enum SeriesReadStatus {
  /// 系列里一本都没读过。
  unread,

  /// 读过一部分，还没读完。
  inProgress,

  /// 全部读完。
  read,
}
