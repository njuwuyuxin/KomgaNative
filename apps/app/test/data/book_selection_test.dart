import 'package:flutter_test/flutter_test.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/book_selection.dart';

/// UI-P2-4 详情页主按钮"读哪一本"的纯逻辑。
void main() {
  Book book(String id, {int? page, bool completed = false}) => Book(
    id: id,
    seriesId: 's1',
    name: 'Vol. $id',
    number: id,
    pagesCount: 20,
    readProgress: page == null
        ? null
        : ReadProgress(
            page: page,
            completed: completed,
            lastModified: DateTime.utc(2026, 1, 1),
          ),
  );

  group('nextBookToRead', () {
    test('优先"在读"的那本（有进度没读完）', () {
      final books = <Book>[
        book('1', page: 20, completed: true),
        book('2', page: 7),
        book('3'),
      ];
      expect(nextBookToRead(books)?.id, '2');
    });

    test('没有在读的 → 第一本未读的', () {
      final books = <Book>[
        book('1', page: 20, completed: true),
        book('2', page: 20, completed: true),
        book('3'),
        book('4'),
      ];
      expect(nextBookToRead(books)?.id, '3');
    });

    test('全读完了 → null（主按钮换文案由调用方决定）', () {
      final books = <Book>[
        book('1', page: 20, completed: true),
        book('2', page: 20, completed: true),
      ];
      expect(nextBookToRead(books), isNull);
    });

    test('空列表 → null，不抛异常', () {
      expect(nextBookToRead(const <Book>[]), isNull);
    });

    test('多本在读时取列表里的第一本（书列表按卷号排）', () {
      final books = <Book>[book('1', page: 3), book('2', page: 9)];
      expect(nextBookToRead(books)?.id, '1');
    });
  });

  group('isUnstartedSeries', () {
    test('一本都没读过 → true', () {
      expect(isUnstartedSeries(<Book>[book('1'), book('2')]), isTrue);
    });

    test('有一本读过（哪怕已读完）→ false', () {
      expect(
        isUnstartedSeries(<Book>[book('1', page: 20, completed: true)]),
        isFalse,
      );
    });

    test('空列表算"没开始"', () {
      expect(isUnstartedSeries(const <Book>[]), isTrue);
    });
  });
}
