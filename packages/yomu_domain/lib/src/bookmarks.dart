/// 单本漫画内部的章节跳转锚点（如 EPUB TOC、子文件夹章节或 `ComicInfo.xml` 书签，LMB-05）。
final class BookChapter {
  const BookChapter({required this.title, required this.startPage});

  final String title;

  /// 1 基起始页码。
  final int startPage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookChapter &&
          other.title == title &&
          other.startPage == startPage);

  @override
  int get hashCode => Object.hash(title, startPage);

  @override
  String toString() => 'BookChapter($title -> p.$startPage)';
}

/// 通用页级书签（同时支持本机漫画与 Komga 远程漫画，按 `{scope, bookId, page}` 分区隔离）。
final class PageBookmark {
  const PageBookmark({
    required this.scope,
    required this.bookId,
    required this.page,
    required this.createdAt,
    this.note = '',
  });

  /// 来源分区键（本机为 `kLocalSourceKey`，远程为规范化 `serverKey`）。
  final String scope;
  final String bookId;

  /// 1 基页码。
  final int page;

  /// 可选书签备注。
  final String note;

  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PageBookmark &&
          other.scope == scope &&
          other.bookId == bookId &&
          other.page == page &&
          other.note == note &&
          other.createdAt == createdAt);

  @override
  int get hashCode => Object.hash(scope, bookId, page, note, createdAt);
}
