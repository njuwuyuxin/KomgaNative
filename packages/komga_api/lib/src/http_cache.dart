import 'dart:typed_data';

/// GET 响应的离线缓存。
///
/// 为什么放在传输层：**只有这里知道"这次请求到底成功了没有"**。
/// 放在 Repository 层要给每个方法各写一遍"失败读缓存"，很快就会漏。
///
/// 为什么是接口：具体存储（Drift/SQLite）属于 app，`komga_api` 保持纯 Dart，
/// 单测里用假实现就能覆盖"命中 / 未命中 / 不该回退"三种分支。
abstract interface class HttpCache {
  /// 读缓存。未命中返回 null。
  ///
  /// [scope] 是服务器身份（规范化后的 baseUrl），多服务器共用一个库也不会串数据；
  /// [url] 是完整请求地址（**含查询串**，否则搜索/分页会互相覆盖）。
  Future<Uint8List?> read(String scope, String url);

  /// 只读整本下载受保护（`pinned`）的离线缓存；未命中或非 pinned 返回 null。
  ///
  /// 用于字节资源（页图）的 Cache-First：已整本下载的书在线阅读直接读本地，零网络流量。
  Future<Uint8List?> readPinned(String scope, String url);

  /// 写入成功响应。[kind] 决定淘汰策略，见 [CacheKind]。
  Future<void> write(String scope, String url, CacheKind kind, Uint8List body);

  /// 请求成功：UI 可以撤掉"离线"提示。
  void reportOnline(String scope);

  /// 请求失败（网络不可达 / 5xx）：UI 应提示"正在显示缓存内容"。
  void reportOffline(String scope);
}

/// 缓存内容的类型。
///
/// JSON 不参与字节预算淘汰：它很小，却是"书架/书能不能打开"的前提；
/// 页图/封面才是空间大头，按 LRU 淘汰它们不会让离线模式变成一堆空页面。
enum CacheKind { json, image }
