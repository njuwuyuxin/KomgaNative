import 'package:komga_domain/komga_domain.dart';

/// 打开阅读器时从列表页带过来的上下文。
///
/// 阅读方向存在 `Series.metadata` 里、不在 `Book` 上，所以必须显式带过来；
/// 深链没有它时按从左到右处理（默认值）。
class ReaderArgs {
  const ReaderArgs({
    required this.book,
    this.direction = ReadingDirection.unknown,
  });

  final Book book;
  final ReadingDirection direction;
}
