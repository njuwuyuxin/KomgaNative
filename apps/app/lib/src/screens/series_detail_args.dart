/// 打开系列详情时从货架带过来的上下文。
class SeriesDetailArgs {
  const SeriesDetailArgs({this.heroTag, this.sourceKey});

  /// 源货架卡片上的 Hero tag；null 表示用默认 tag。
  final String? heroTag;

  /// 跨源跳转时目标系列所属的 `sourceKey`。
  final String? sourceKey;
}
