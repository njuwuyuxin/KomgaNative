import 'package:komga_domain/komga_domain.dart';

/// 阅读器占位数据（M2 接真实书页后删除）。
///
/// 书架已经走真实 API（`lib/src/data/library_repository.dart`），这里只剩
/// 阅读器还需要一本假书；M2 做书页加载时一并替换。
const List<Book> kSampleBooks = <Book>[
  Book(id: 'b1', seriesId: 's1', name: 'Vol. 1', number: '1', pagesCount: 24),
  Book(id: 'b2', seriesId: 's1', name: 'Vol. 2', number: '2', pagesCount: 22),
];

Book? sampleBook(String bookId) {
  for (final book in kSampleBooks) {
    if (book.id == bookId) return book;
  }
  return null;
}
