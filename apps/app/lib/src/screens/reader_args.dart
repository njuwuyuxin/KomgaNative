import 'package:komga_domain/komga_domain.dart';

/// 打开阅读器时从列表页带过来的上下文。
///
/// 阅读方向存在 `Series.metadata` 里、不在 `Book` 上，所以必须显式带过来；
/// 深链没有它时按从左到右处理（默认值）。
class ReaderArgs {
  const ReaderArgs({
    required this.book,
    this.direction = ReadingDirection.unknown,
    this.heroTag,
  });

  final Book book;
  final ReadingDirection direction;

  /// 源卡片的封面 Hero tag（"正在读"继续阅读卡片 → 阅读器开场，UI-P2-2）。
  ///
  /// 系列详情/深链没有源卡片，为 null：阅读器不建开场封面 Hero。
  final String? heroTag;
}
