import 'package:komga_domain/komga_domain.dart';

/// M0 的示例数据：让 UI 与黄金图在不连服务器的情况下可渲染。
///
/// M1 会用真实 Repository 替换，这里的存在意义是"可复现的渲染基线"。
const List<Series> kSampleSeries = <Series>[
  Series(
    id: 's1',
    libraryId: 'l1',
    title: 'Frieren',
    booksCount: 12,
    booksReadCount: 5,
  ),
  Series(
    id: 's2',
    libraryId: 'l1',
    title: 'Vagabond',
    booksCount: 37,
    booksReadCount: 37,
  ),
  Series(
    id: 's3',
    libraryId: 'l1',
    title: 'Blame!',
    booksCount: 10,
    booksReadCount: 0,
  ),
  Series(
    id: 's4',
    libraryId: 'l1',
    title: 'Akira',
    booksCount: 6,
    booksReadCount: 2,
    readingDirection: ReadingDirection.rightToLeft,
  ),
  Series(
    id: 's5',
    libraryId: 'l1',
    title: 'Sunny',
    booksCount: 6,
    booksReadCount: 3,
  ),
  Series(
    id: 's6',
    libraryId: 'l1',
    title: 'Pluto',
    booksCount: 8,
    booksReadCount: 8,
  ),
];

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

Series? sampleSeries(String seriesId) {
  for (final series in kSampleSeries) {
    if (series.id == seriesId) return series;
  }
  return null;
}
