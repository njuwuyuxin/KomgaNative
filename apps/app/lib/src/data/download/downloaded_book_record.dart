/// 已整本离线下载书籍的纯领域/展示记录（与 Drift `DownloadedBook` 行类型解耦，供 UI 层消费）。
final class DownloadedBookRecord {
  const DownloadedBookRecord({
    required this.scope,
    required this.bookId,
    required this.seriesId,
    required this.bookName,
    required this.pageCount,
    required this.bytes,
    required this.savedAt,
  });

  final String scope;
  final String bookId;
  final String seriesId;
  final String bookName;
  final int pageCount;
  final int bytes;
  final DateTime savedAt;
}
