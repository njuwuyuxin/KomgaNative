import 'package:yomu_domain/yomu_domain.dart';
import 'package:test/test.dart';

void main() {
  group('ReadingDirection.parse', () {
    test('识别 Komga 常见取值与多种写法', () {
      expect(
        ReadingDirection.parse('LEFT_TO_RIGHT'),
        ReadingDirection.leftToRight,
      );
      expect(
        ReadingDirection.parse('RIGHT_TO_LEFT'),
        ReadingDirection.rightToLeft,
      );
      expect(ReadingDirection.parse('rtl'), ReadingDirection.rightToLeft);
      expect(ReadingDirection.parse('WEBTOON'), ReadingDirection.webtoon);
      expect(ReadingDirection.parse('vertical'), ReadingDirection.vertical);
    });

    test('未知/空值退化为 unknown 而不是抛异常', () {
      expect(ReadingDirection.parse(null), ReadingDirection.unknown);
      expect(ReadingDirection.parse(''), ReadingDirection.unknown);
      expect(ReadingDirection.parse('SOMETHING_NEW'), ReadingDirection.unknown);
    });
  });

  group('MediaProfile', () {
    test('EPUB 与未知类型不走图片序列路径', () {
      expect(MediaProfile.parse('DIVINA').isImageSequence, isTrue);
      expect(MediaProfile.parse('PDF').isImageSequence, isTrue);
      expect(MediaProfile.parse('EPUB').isImageSequence, isFalse);
      expect(MediaProfile.parse(null).isImageSequence, isFalse);
    });
  });

  group('ReadProgress', () {
    test('值相等只看页码/完成态/服务端时间', () {
      final t = DateTime.utc(2026, 11, 17);
      final a = ReadProgress(page: 3, completed: false, lastModified: t);
      final b = ReadProgress(
        page: 3,
        completed: false,
        lastModified: t,
        readDate: t,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('Book', () {
    Book book({ReadProgress? progress, String? seriesTitle}) => Book(
      id: 'b',
      seriesId: 's',
      name: 'Vol. 1',
      seriesTitle: seriesTitle,
      number: '1',
      pagesCount: 10,
      readProgress: progress,
    );

    test('withProgress 能换也能清空（copyWith 分不清这两种意图）', () {
      final progress = ReadProgress(
        page: 3,
        completed: false,
        lastModified: DateTime.utc(2026, 1, 1),
      );

      final withProgress = book().withProgress(progress);
      expect(withProgress.readProgress, progress);
      expect(withProgress.id, 'b', reason: '其它字段原样保留');

      expect(book(progress: progress).withProgress(null).readProgress, isNull);
    });

    test('withProgress 保留 seriesTitle（本地叠加进度不该丢系列名）', () {
      final progress = ReadProgress(
        page: 3,
        completed: false,
        lastModified: DateTime.utc(2026, 1, 1),
      );
      final updated = book(seriesTitle: 'Frieren').withProgress(progress);
      expect(updated.seriesTitle, 'Frieren');
      // 没有系列名时保持 null，不要变成空串。
      expect(book().withProgress(progress).seriesTitle, isNull);
    });

    test('未读/读完的判断', () {
      expect(book().isUnread, isTrue);
      expect(
        book(
          progress: ReadProgress(
            page: 10,
            completed: true,
            lastModified: DateTime.utc(2026, 1, 1),
          ),
        ).isCompleted,
        isTrue,
      );
    });
  });

  group('Series', () {
    test('进度按已读/总数计算并夹在 0..1', () {
      expect(
        const Series(
          id: 's',
          libraryId: 'l',
          title: 't',
          booksCount: 10,
          booksReadCount: 5,
        ).progress,
        0.5,
      );
      expect(const Series(id: 's', libraryId: 'l', title: 't').progress, 0.0);
      expect(
        const Series(
          id: 's',
          libraryId: 'l',
          title: 't',
          booksCount: 0,
          booksReadCount: 3,
        ).progress,
        0.0,
      );
    });
  });

  group('PageInfo', () {
    test('缺宽高时 aspectRatio 为 null（阅读器需解码后测量）', () {
      expect(const PageInfo(number: 1).aspectRatio, isNull);
      expect(
        const PageInfo(number: 1, width: 0, height: 100).aspectRatio,
        isNull,
      );
      expect(
        const PageInfo(number: 1, width: 400, height: 200).aspectRatio,
        2.0,
      );
    });
  });
}
