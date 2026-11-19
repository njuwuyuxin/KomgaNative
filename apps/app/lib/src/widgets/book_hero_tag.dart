/// 书封面的 Hero tag（"正在读"继续阅读卡片 → 阅读器开场）。
///
/// 与 `seriesHeroTag` 分开：书封面和系列封面可能同时出现在一个页面
/// （继续阅读卡片 + 货架），前缀不同才不会撞 tag。
String bookHeroTag(String bookId) => 'book-$bookId';
