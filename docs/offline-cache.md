# 离线与缓存

> 目标：**断网冷启动不是错误页，看过的东西还能看。**
> 进度在 ADR 0002 里已经落盘补交；这里解决"内容"。

## 用户能看到什么

| 场景 | 行为 |
|---|---|
| 在线逛书架 | 系列列表 / 封面 / 系列详情 / 书列表 / 页图 / 页列表 全部写进本地缓存 |
| 断网打开 App | 书架显示上次的列表与封面，顶部出现「Offline · showing saved content」提示条 |
| 断网点进系列 | 系列详情与书列表从缓存出；没缓存过就仍是错误页（会提示可重试） |
| 断网打开读过的书 | 页图从缓存出，翻页正常；**没读过的页会显示页内错误**，可重试 |
| 网络恢复 | 任意一次成功请求（GET 或进度 PATCH）后离线提示自动消失 |
| 设置 → Storage | 显示缓存占用与条数、已下载书籍数量与体积，可一键清空缓存（不影响阅读进度） |
| 设置 → Downloaded books | 下载管理页（UI-P3-13）：进行中/排队/已下载，显示进度、书名、页数与体积，可取消、删除 |
| 系列详情 → 每本书的下载按钮 | 整本下载（显示进度、可取消、可删除），下载完的书断网可整本阅读 |

## 整本下载

系列详情每本书右侧的 ⬇ 按钮：

- **开始**：逐页请求页图（请求走带缓存的会话，所以"下载"与"缓存"是同一条链路），
  按钮变成环形进度；再点一次 = 取消；
- **取消**：在页与页之间生效（不中断已在途的单页请求），已下载的页保留；
- **完成**：写入 `downloaded_books`（书、页数、字节数），图标变成 ✓；
- **删除**：确认后同时删掉下载记录与该书已缓存的页图，其他书的缓存不动。
- **队列**（UI-P3-13）：一次只跑一本；后面的显示"排队中"，前一本完成/取消后自动开始。
  并发下载只会互相抢带宽，进度也更难解释。

下载管理页（`screens/downloads_screen.dart`）从设置页进入：列出进行中、排队、
已下载三类；进行中显示线性进度与取消，已下载显示页数/体积与删除。书名按
`bookId` 查一次（`bookByIdProvider`），查不到就退化成 id，不阻塞列表。

为什么不"靠缓存里有没有这些页"反推已下载：页图缓存会被字节预算 LRU 淘汰，
而"用户明确下载过"是意图，不能被自动淘汰悄悄改写。两者必须显式管理。

为什么下载是逐页顺序请求：并发抓 100 页对 NAS 是瞬时压力，收益只有几秒；
顺序还能让取消点干净、进度真实。

## 实现地图

| 位置 | 职责 |
|---|---|
| `packages/komga_api/lib/src/http_cache.dart` | `HttpCache` 接口（纯 Dart，四个方法） |
| `packages/komga_api/lib/src/session.dart` | GET 成功写缓存；网络错误/5xx 读缓存并上报离线状态 |
| `apps/app/lib/src/data/cache/http_cache_database.dart` | Drift 表 + 字节预算 LRU + JSON 条数裁剪 + 占用统计 |
| `apps/app/lib/src/data/cache/drift_http_cache.dart` | 接口实现 + `ValueNotifier<bool> offline` 广播 |
| `apps/app/lib/src/providers/cache_providers.dart` | 缓存库/实例/占用/离线状态 provider |
| `apps/app/lib/src/widgets/offline_banner.dart` | 离线提示条（带 Retry） |
| `apps/app/lib/src/screens/settings_screen.dart` | Storage 区：占用展示 + 清空 + 下载管理入口 |
| `apps/app/lib/src/screens/downloads_screen.dart` | 下载管理页（UI-P3-13） |
| `apps/app/test/downloads_queue_test.dart` | 下载队列串行单测 |

决策与理由见 [ADR 0003](adr/0003-http-response-cache.md)。

## 容量与淘汰

- **图片（页图 + 封面）**：总字节预算 256 MB，按 `lastUsedSeq` LRU 淘汰，分批（32 行）删除。
- **JSON（列表/详情/页列表）**：每服务器最多 400 条，按最久未用裁剪；**不参与字节预算**，
  因为它是"书能不能打开"的前提，而体积很小。
- 单条超过预算的图片允许暂时超额（刚写入的那条受保护），下一次写入再还。
- 清空：`设置 → Storage → Clear`，清的是 `komga_cache.sqlite`，用户库 `komga_native.sqlite`（阅读进度、系列置顶、阅读历史与统计）完全不受影响。

## 分区

缓存键 = `(scope, url)`：

- `scope` 是规范化后的服务器 `baseUrl`（含反代子路径），多服务器不会串数据；
- `url` 含查询串，所以 `?search=`、`?page=`、`?convert=jpeg` 各自独立，不会互相覆盖。

## 明确不做（阶段 C/D 范围内）

- **离线登录**：凭据仍从钥匙串读，离线只影响内容，不影响"你是谁"。
- **整库镜像**：v1 范围外（`docs/tech-selection.md` §11）。
- **缓存加密**：内容落在应用私有目录，与"下载到本地"是同一类暴露面。

## 验证

- `packages/komga_api/test/http_cache_test.dart`（11 个）：命中回退、查询串隔离、
  404/401 不回退、5xx 回退、缓存读写自身失败不拖垮在线请求。
- `apps/app/test/data/http_cache_database_test.dart`（13 个）：覆盖写、分区隔离、
  字节预算 LRU、超预算单条、JSON 不被字节淘汰、JSON 条数上限、占用统计、清空。
- `apps/app/test/data/download_service_test.dart`（6 个）：进度、幂等、取消、失败、删除、空书。
- `apps/app/test/download_button_test.dart`（3 个）：按钮状态机（未下载 → 已下载 → 删除）。
- `apps/app/test/widgets/offline_banner_test.dart`（3 个）：在线不占位、离线出现/恢复消失、Retry 回调。
- 黄金图 `library_offline@phone_light`：离线提示条 + 缓存书架的真实排版。
- **未验证**：真机断网冷启动（阶段 D 之后连同整本下载一起在模拟器上验；本阶段只有单测与黄金图）。
