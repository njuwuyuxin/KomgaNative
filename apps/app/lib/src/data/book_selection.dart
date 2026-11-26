import 'package:yomu_domain/yomu_domain.dart';

/// "接着读哪一本"（UI-P2-4 详情页主按钮）。
///
/// 规则（与 Komga 的 ondeck 语义一致，但不依赖服务端）：
/// 1. 有"在读（有进度但没读完）"的书 → 取第一本（书列表按卷号排序）；
/// 2. 否则取第一本**未读**的书；
/// 3. 全都读完了 → 返回 null（主按钮换成"从头再看"由调用方决定）。
///
/// 为什么不用 `ondeck` 接口：那个接口是"整个库的继续阅读"，一次只给 20 本，
/// 也不按系列过滤；详情页需要的是"这个系列里下一本该读的"。
Book? nextBookToRead(List<Book> books) {
  if (books.isEmpty) return null;
  for (final book in books) {
    final progress = book.readProgress;
    if (progress != null && !book.isCompleted) return book;
  }
  for (final book in books) {
    if (!book.isCompleted) return book;
  }
  return null;
}

/// 这个系列是否"一本都没开始读"（决定主按钮是"开始阅读"还是"继续阅读"）。
bool isUnstartedSeries(List<Book> books) =>
    books.every((Book book) => book.readProgress == null);
