/// 打开系列详情时从货架带过来的上下文。
///
/// 只用来让 Hero 找到**被点的那一份**：同一个系列可能在"正在读"页同时出现在
/// "最近添加"和按库货架里，两处 tag 相同的话 Flutter 只会挑其中一个，
/// 封面就会从另一份的位置飞进来（真机上撞到过）。
///
/// 深链 / 冷启动没有这个 extra，详情页按默认 `series-<id>` 处理：
/// 没有源卡片，自然也就不飞。
class SeriesDetailArgs {
  const SeriesDetailArgs({this.heroTag});

  /// 源货架卡片上的 Hero tag；null 表示用默认 tag。
  final String? heroTag;
}
