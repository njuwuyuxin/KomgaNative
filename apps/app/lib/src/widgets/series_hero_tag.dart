/// 系列封面的 Hero tag（书架 / "正在读" → 详情页头部）。
///
/// [scope] 用来区分**同一页面上同一个系列的多份副本**："正在读"页的
/// "最近添加"货架与按库货架会同时出现同一个系列，如果两处用同一个 tag，
/// Flutter 在开始飞行时只会随便挑其中一个 Hero（debug 下直接断言失败），
/// 封面就会从另一份的位置飞进来、退出时又飞回错误的位置。
///
/// 约定：详情页通过 `SeriesDetailArgs` 接收源卡片的 tag，两边必须一致。
String seriesHeroTag(String seriesId, {String? scope}) =>
    scope == null ? 'series-$seriesId' : 'series-$seriesId@$scope';
