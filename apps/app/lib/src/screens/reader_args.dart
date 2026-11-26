import 'package:yomu_domain/yomu_domain.dart';

/// 打开阅读器时从列表页带过来的上下文。
class ReaderArgs {
  const ReaderArgs({
    required this.book,
    this.direction = ReadingDirection.unknown,
    this.heroTag,
    this.sourceKey,
  });

  final Book book;
  final ReadingDirection direction;
  final String? heroTag;

  /// 显式指定内容源标识；未传时默认取 `book.sourceKey`。
  final String? sourceKey;
}
