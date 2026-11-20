# 代码评审问题清单与架构修复计划（2026-11）

> **评审日期**：2026-11-20
> **评审范围**：全仓库 7 个 Workspace 包（201 个生产 Dart 文件、136 个测试文件、`tool/ci.dart` 门禁与 `docs/adr/`）
> **评审基线总分**：**79 / 100**（架构设计 84 · 功能解耦 74 · 设计模式 78 · 代码规范 79）
> **目标**：把评审暴露的 12 条结构性与正确性问题拆解为 **12 个独立可交付、可单测验收的修复任务（`ARC-01` ~ `ARC-12`）**，消除数据串库与静默失效隐患，收敛架构边界，并将规范红线固化进 `tool/ci.dart`，使整体代码质量提升至 **90+ / 100**。

---

## 0. 评分基线与修复原则

### 0.1 评审基线拆解

| 评审维度 | 权重 | 当前得分 | 核心优势 | 主要失分点 |
|---|---:|---:|---|---|
| **架构设计与分层治理** | 30% | 84 | Workspace 纯逻辑包零 UI/IO 依赖、`ci.dart` 自动分层扫描、强类型 lint、TOFU 证书固定 | 多服务器表缺少 `serverId` 分区；整本下载页图被全局 LRU 淘汰；UI 层存在直接写仓库/Store |
| **功能解耦与内聚性** | 25% | 74 | UI 与 `dio`/`komga_api` 完全隔离；墨水屏退化由 `effectiveEinkProvider` 与 Token 统一收口 | `LibraryRepository` 膨胀为 17 方法上帝接口；4 处重复建 `Dio` 连接池；缓存库混装用户历史与置顶 |
| **设计模式与状态管理** | 25% | 78 | `KomgaError` → `ShelfFailure` 双层密封异常、`_generation` 防竞态、`_touched` 异步恢复保护 | `KomgaLibraryRepository` 漏传排序/筛选参数且违背 404 空值契约；`ReaderPrefs` 拷贝漂移；Outbox 队头阻塞 |
| **代码规范与可维护性** | 20% | 79 | 无 `dynamic`/`print`、JSON 容错解析扎实、测试与黄金图覆盖广、注释交代“为什么” | 10 文件超 350 行、5 类超 300 行；存在裸 `catch (_)` 与 `unawaited_futures` 告警；中英硬编码混排 |

### 0.2 修复推进原则

1. **先止血正确性，再动表结构，最后做拆包与门禁**：
   - 先在不改 SQLite 表结构的前提下修掉“参数漏传、设置静默失效、队头阻塞、未捕获异常”（**B0 / B1**）；
   - 再集中处理数据库分库归位、多服务器复合主键迁移与下载缓存保护（**B2**，一次把 Drift 迁移写干净、测透）；
   - 最后拆分上帝接口、清理超长文件与死代码，并在 `tool/ci.dart` 中把行数和 `catch (_)` 门禁补上，防止回退（**B3**）。
2. **一任务一提交**：每个 `ARC-XX` 保持独立闭环，严格执行 `AGENTS.md` 标准交付流程（补单测/黄金图 → `dart run tool/ci.dart check` 全绿 → `dart run tool/ci.dart install` 设备实操验证）。
3. **不破坏既有存档与离线数据**：涉及 `SecureSettingsStore`、`ReaderPrefsStore`、Drift `schemaVersion` 的改动必须提供向后兼容迁移与旧数据回放单测。

---

## 1. 修复路线图与任务总表

> **估时口径**：S ≤ 0.5–1 天；M = 1.5–3 天；L = 3–5 天（含单测、迁移测试、黄金图与模拟器验证）。

| 批次 | 任务 ID | 对应评审项 | 修复主题 | 级别 | 估时 | 前置依赖 | 状态 |
|---|---|---|---|---|---|---|---|
| **B0 正确性止血** | `ARC-01` | #2 | 修复 `KomgaLibraryRepository` 漏传排序/筛选、404 空值契约与进度叠加 | P0 | S | — | [x] |
| **B0 正确性止血** | `ARC-02` | #9, #10 | 修复列表行 `onLongPress` 失效、`build` 静态副作用、裸 `catch (_)` 与分析告警 | P2 | S | — | [x] |
| **B0 正确性止血** | `ARC-03` | #6 | 修复 `badCertificate` 错误归类与进度 Outbox 404/400 队头永久阻塞 | P1 | S | — | [x] |
| **B1 模式与数据流** | `ARC-04` | #3 | 抽离 `ReaderConfig` 值对象，根治 `ReaderPrefs` 原型拷贝漂移与系列覆盖失效 | P1 | M | — | [x] |
| **B1 模式与数据流** | `ARC-05` | #5 | 收敛 UI 层直接 I/O 与存储操作，补齐长按菜单异常捕获与搜索历史响应式同步 | P1 | M | `ARC-01` | [ ] |
| **B2 存储与多服隔离** | `ARC-06` | #7 | 数据库职责归位：将 `PinnedSeriesRows` 与 `ReadingSessions` 迁回用户库 | P2 | M | — | [ ] |
| **B2 存储与多服隔离** | `ARC-07` | #1 (前半) | 多服务器数据隔离闭环：进度、下载、队列、历史与阅读偏好补齐 `serverId` | P0 | L | `ARC-04`, `ARC-06` | [ ] |
| **B2 存储与多服隔离** | `ARC-08` | #1 (后半) | 解耦“整本下载”与被动浏览 LRU 缓存淘汰，保护已下载页图不被静默驱逐 | P0 | M | `ARC-07` | [ ] |
| **B3 解耦与规范收口** | `ARC-09` | #4 | 下沉共享 `komgaSessionProvider` 连接池，按限界上下文拆分 `LibraryRepository` | P1 | M | `ARC-01`, `ARC-05` | [ ] |
| **B3 解耦与规范收口** | `ARC-10` | #8 | `/downloads` 纳入 `GoRouter`，以 Drift 流监听与统一失效钩子替代手工 `invalidate` | P2 | M | `ARC-07`, `ARC-09` | [ ] |
| **B3 解耦与规范收口** | `ARC-11` | #9, #11 | 清理 M0 死代码与重复实现，`SessionController` 本地化，消除 UI 魔法值 | P2/P3 | M | — | [ ] |
| **B3 解耦与规范收口** | `ARC-12` | #9, #12 | 拆分 10 个超长文件/5 个超大类，提炼通用增量分页器，并在 `ci.dart` 加门禁 | P2/P3 | L | `ARC-04`, `ARC-09` | [ ] |

---

## 2. 逐项修复规格与验收标准

### 2.1 批次 B0：正确性止血（不改表结构，优先落地）

#### `ARC-01` 修复 `KomgaLibraryRepository` 漏传参数、404 空值契约与本地进度叠加
- **对应评审问题**：#2（P0 · 设计模式 / 适配器契约失真）
- **问题定位**：
  - `apps/app/lib/src/data/library_repository.dart:282-304`：`KomgaLibraryRepository.books` 接收了 `BooksSort? sort` 与 `SeriesReadStatus? readStatus`，但调用 `_session.fetchSeriesBooks(seriesId, page: page, size: size)` 时漏传了这两个参数，导致系列详情页的排序与阅读状态筛选在真机上完全无效。
  - `apps/app/lib/src/data/library_repository.dart:30-31, 170-177`：接口文档承诺 `book(bookId)` 在书不存在时返回 `null`，但实现未捕获 `KomgaNotFoundError`（直接转成 `ProtocolFailure` 抛出）。
  - `apps/app/lib/src/data/library_repository.dart:170-190, 265-280`：`book()`、`searchBooks()`、`readListBooks()` 返回的 `Book` 未走 `_sync.overlay` / `_sync.overlayOne`，导致离线阅读后的最新进度在搜索结果、阅读列表、下载页回退为服务端旧值。
- **改造方案**：
  1. 在 `KomgaLibraryRepository.books` 中向 `_session.fetchSeriesBooks` 完整透传 `sort: sort`、`readStatus: readStatus`。
  2. 在 `KomgaLibraryRepository.book` 中捕获 `on KomgaNotFoundError { return null; }`，并对返回的 `Book` 调用 `_sync.overlayOne`。
  3. 在 `searchBooks` 与 `readListBooks` 返回前统一套用 `_sync.overlay(result.items)`。
- **验收标准**：
  - 新增针对 `KomgaLibraryRepository`（配合 Fake `Dio` adapter 而非跳过仓库的 Fake repository）的单测，断言请求 URL 查询串包含 `sort` 与 `read_status`，404 返回 `null`，且四处 `Book` 查询出口均叠加本地未同步进度。
  - 连接 Komga 实例在系列详情页切换排序/未读筛选，列表顺序与过滤结果真实生效。

---

#### `ARC-02` 修复 `SeriesShelfRow` 长按失效、`build` 全局静态副作用、裸 `catch (_)` 与分析告警
- **对应评审问题**：#9 部分、#10（P2 · 代码规范与 UI 交互 Bug）
- **问题定位**：
  - `apps/app/lib/src/widgets/series_shelf_tile.dart:156, 189-199`：`SeriesShelfRow` 声明了 `onLongPress`（注释标明用于多选模式勾选），但 `InkWell.onLongPress` 未判断 `onLongPress ?? ...`，导致书架列表视图下外部传入的长按回调完全失效。
  - `apps/app/lib/src/app.dart:28`：`KomgaApp.build()` 内直接写静态全局变量 `AppHaptics.enabled = settings.haptics;`，违反 `build` 纯函数原则并在并行测试中共享可变全局状态。
  - `apps/app/lib/src/screens/library_screen_batch.dart:24`：使用 `catch (_)` 裸捕获（违反 `AGENTS.md` 反模式红线，会吞掉 `Error`）。
  - `apps/app/lib/src/widgets/page_curl.dart:226`：`_pending.remove(page)` 返回 `Future<void>?` 未消费，触发 `dart analyze` 的 `unawaited_futures` info 告警。
- **改造方案**：
  1. `SeriesShelfRow` 第 191 行改为 `onLongPress: onLongPress ?? () => unawaited(showSeriesMenu(...))`。
  2. 将 `AppHaptics.enabled` 的同步移入 `SettingsController`（恢复/更新时同步）或在 `KomgaApp` 中通过 `ref.listen<bool>(settingsProvider.select((s) => s.haptics), ...)` 驱动，不在 `build` 主体产生写入副作用。
  3. `library_screen_batch.dart:24` 改为 `on ShelfFailure` 精确捕获。
  4. `page_curl.dart:226` 改为 `_pending.remove(page)?.ignore();`（或赋给忽略变量），使 `dart run tool/ci.dart analyze` 达到 **0 issues**。
- **验收标准**：
  - 补充列表视图（`ShelfView.list`）多选模式下长按系列行的 widget 测试。
  - `dart run tool/ci.dart analyze` 输出 `No issues found!`。

---

#### `ARC-03` 修复 `badCertificate` 错误归类与进度 Outbox 404/400 队头永久阻塞
- **对应评审问题**：#6（P1 · 错误模型与同步可靠性）
- **问题定位**：
  - `packages/komga_api/lib/src/errors.dart:89-101`：`mapDioException` 在 `e.error` 不是 `HandshakeException` 时，把 `DioExceptionType.badCertificate` 映射成了 `KomgaNetworkError`，导致无法触发 TOFU 证书信任面板。
  - `apps/app/lib/src/data/progress/progress_sync_service.dart:55-70`：`_flushLoop` 顺序遍历 `pending()` 时，遇到任何非鉴权 `ShelfFailure` 直接保留记录并 `return` 结束循环。若队首书籍在服务端已被删除（404）或页码越界（400），后续所有正常书籍的进度将被永久卡死。
- **改造方案**：
  1. 在 `mapDioException` 中将 `case DioExceptionType.badCertificate:` 单独映射为 `KomgaTlsError`。
  2. 在 `ShelfFailure`（或 `ProgressUpload` 返回结果）中保留 `NotFoundFailure` / `BadRequestFailure`（或在 `ShelfFailureKind` 中细分不可重试的客户端/资源不存在错误）：
     - 遇到 `AuthFailure`：置 `_authBlocked = true` 并暂停本轮；
     - 遇到 `NetworkFailure` / `ServerFailure` / `CertificateFailure`：保留 pending 并暂停本轮等待下次网络恢复；
     - 遇到 **404（书已删除）或 400（参数越界不可恢复）**：调用 `_store.ack(item.target.bookId, item.seq)`（或移除该条坏死 pending）并 **`continue` 继续冲洗后续书籍**，绝不阻塞整条队列。
- **验收标准**：
  - `komga_api_test.dart` 增加 `DioExceptionType.badCertificate`（无 `HandshakeException` cause）映射为 `KomgaTlsError` 的用例。
  - `progress_wiring_test.dart` 增加“第 1 本书返回 404/400、第 2 本书返回 204”的队列冲洗测试，断言第 1 本出队不死循环、第 2 本成功上传。

---

### 2.2 批次 B1：值对象解耦与单向数据流收敛

#### `ARC-04` 抽离 `ReaderConfig` 值对象，根治 `ReaderPrefs` 原型拷贝漂移
- **对应评审问题**：#3（P1 · 设计模式）
- **问题定位**：
  - `apps/app/lib/src/data/reader_prefs.dart:270-324, 565-589` 与 `apps/app/lib/src/providers/reader_prefs_provider.dart:75-102`：
    - `setTapZone`、`setInvertTapZones`、`setDoubleTapZoom`、`setAutoScrollSpeed`、`setShowSessionTime` 传入了 `seriesId`，但 `configOnly()` 丢弃了这 5 项且 `forSeries()` 从全局读取它们，导致开启“按系列覆盖”时修改这 5 项全部静默失效；
    - `withConfig()` 漏掉了 `pageTurn`，导致全局应用预设时翻页动画丢失；
    - `hashCode` 漏掉了 `showSessionTime`、`tabletLayout`、`autoScrollSpeed`。
- **改造方案**：
  1. 拆出不可变纯配置类 `ReaderConfig`（放在独立文件 `reader_config.dart`），包含全部可随预设/系列覆盖走的参数（`mode`、`brightness`、`keepAwake`、`fit`、`direction`、`background`、`lockZoom`、`trimBorders`、`pageTurn`、`tapZone`、`invertTapZones`、`doubleTapZoom`、`autoScrollSpeed`、`showSessionTime`），`==` 与 `hashCode`（用 `Object.hashAll`）只写一处。
  2. `ReaderPrefs` 简化为顶层聚合容器：`final ReaderConfig global; final TabletLayoutChoice tabletLayout; final Map<String, int> spreadFrom; final List<ReaderPreset> presets; final Map<String, ReaderConfig> seriesOverrides;`。
  3. **删除** `configOnly()` 与 `withConfig()`：`forSeries(seriesId)` 直接返回 `seriesOverrides[seriesId] ?? global`，预设 `ReaderPreset` 直接持有 `ReaderConfig`。
  4. **存档兼容**：`ReaderPrefs.toJson()` / `fromJson()` 保持现有扁平顶层 JSON 字段格式兼容旧存档（读旧版扁平 JSON 直接解析为 `global: ReaderConfig.fromJson(json)`），`PrefsBackup` 版本号无需破坏性升级。
- **验收标准**：
  - 新增“所有 `ReaderConfig` 字段随机非默认值 → 保存为预设 → 应用到全局 / 应用到系列覆盖 → 逐字段全等”的属性往返单测。
  - 旧版 JSON 存档反序列化兼容单测全绿；`reader_prefs.dart` 与 `reader_config.dart` 单文件均控制在 300 行以内。

---

#### `ARC-05` 收敛 UI 层直接 I/O 与存储操作，补齐未捕获异常处理
- **对应评审问题**：#5（P1 · 架构分层与单向数据流）
- **问题定位**：
  - `apps/app/lib/src/widgets/series_shelf_tile.dart:338-346`：`showSeriesMenu` 在 `unawaited` 中调用 `seriesReadProvider.notifier.setRead` 未捕获 `ShelfFailure`，失败时抛出未处理异步异常。
  - `apps/app/lib/src/screens/series_detail_screen.dart:170-173` 与 `apps/app/lib/src/screens/collections_screen.dart:327-360`：Widget `State` 直接调 `libraryRepositoryProvider` 发起新建/改名/删除收藏集请求。
  - `apps/app/lib/src/screens/search_screen.dart:67-123`：Widget 内部直接读写 `settingsStoreProvider` 维护私有 `_history`，与 `SettingsBackupSection` 导入配置失步。
  - `apps/app/lib/src/screens/settings_screen.dart:295-299`：顶层函数 `_removeServer` 直接编排 `serverStoreProvider.remove` + `signOut`。
- **改造方案**：
  1. 新增 `CollectionsController`（或扩展收藏集操作 provider）承接 `create` / `rename` / `delete` intent 及自动刷新；Widget 只调 controller 方法并根据返回结果弹提示。
  2. 新增 `searchHistoryProvider`（或并入设置状态派生），消除 `SearchScreen` 内部手工 `_loadHistory` 与私有 `_history` 副本，确保导入备份后搜索历史立即同步。
  3. 将“删除已保存服务器（若为当前活动服务器则自动登出）”收进 `SessionController.removeServer(StoredServer server)`。
  4. 在 `showSeriesMenu` 中捕获 `ShelfFailure` 并通过 `ScaffoldMessenger` 展示本地化错误提示（与 `SeriesDetailScreen._markSeriesRead` 行为对齐）。
- **验收标准**：
  - 模拟断网长按书架卡片点“全部标为已读”，不抛未捕获异常且底部弹出错误 SnackBar。
  - 导入含 `searchHistory` 的备份后切到已挂载的搜索页，历史列表即时更新。

---

### 2.3 批次 B2：存储分库归位、多服务器隔离与下载缓存保护

#### `ARC-06` 数据库职责归位：将 `PinnedSeriesRows` 与 `ReadingSessions` 迁回用户数据库
- **对应评审问题**：#7（P2 · 功能耦合 / 单一职责原则）
- **问题定位**：
  - `apps/app/lib/src/data/cache/http_cache_database.dart:90-128`：置顶系列与本地阅读会话统计属于不可再生的用户资产，却放在随时可能因清缓存/损坏而重建的 `komga_cache.sqlite` 中。
- **改造方案**：
  1. 将 `PinnedSeriesRows` 与 `ReadingSessions` 表定义及 DAO 方法迁入 `komga_native.sqlite`（可将 `ProgressDatabase` 重命名或扩展为统一的 `UserDatabase`，`schemaVersion` 升至 2）。
  2. **平滑迁移**：首次升级打开用户库时，若检测到同目录下 `komga_cache.sqlite` 存在旧的 `pinned_series_rows` / `reading_sessions` 数据，一次性读取迁入新库后再清理旧表（或通过 `ATTACH DATABASE` 拷贝，包裹在 `try/on Object` 中做到失败不崩）。
  3. 扩展 `PrefsBackup`（可选升至兼容段或保持可选字段 `pinnedSeries`）以允许备份置顶列表。
- **验收标准**：
  - 迁移单测：准备含置顶与阅读会话的 v5 `HttpCacheDatabase`，执行迁移后在新库中完整读出，且清空/删除 `komga_cache.sqlite` 完全不影响阅读历史、Insights 统计与置顶系列。

---

#### `ARC-07` 多服务器数据隔离闭环：核心本地表与阅读偏好补齐 `serverId / scope`
- **对应评审问题**：#1 前半（P0 · 架构与多租户隔离）
- **问题定位**：
  - `LocalProgress`（`progress_database.dart:13`）、`DownloadedBooks` 与 `DownloadQueueEntries`（`http_cache_database.dart:40-86`）、`ReadingSessions`（`http_cache_database.dart:107`）均无服务器标识列；`ReaderPrefs.seriesOverrides` 与 `spreadFrom` 也仅用裸 `seriesId`/`bookId` 作 key。
- **改造方案**：
  1. 统一服务器分区键口径为规范化 `serverKey`（`server.address.baseUrl`，与 `CachedResponses.scope`、`PinnedSeriesRows.serverId` 一致）。
  2. 数据库迁移：
     - `LocalProgress` 主键升级为 `{scope, bookId}`；`ProgressSyncService` 按记录自带的 `scope`（仅冲洗当前已连接 `session.server.id == scope` 的待同步项）上传，彻底杜绝把服务器 A 的进度 `PATCH` 到服务器 B。
     - `DownloadedBooks` 与 `DownloadQueueEntries` 主键升级为 `{scope, bookId}`；`downloadedBooksProvider`、`downloadsUsageProvider`、`DownloadsController` 按当前 `activeServerKeyProvider` 过滤（设置页同时保留“当前服务器下载”或“全部离线占用”清晰口径）。
     - `ReadingSessions` 增加 `scope` 列（默认空串兼容旧行，迁移时如能读取当前活动服务器则回填），点击历史跳阅读器前校验所属服务器。
  3. `ReaderPrefs` 的 `seriesOverrides` 与 `spreadFrom` 键格式支持 `$serverKey|$id`（读取时若命中无前缀旧键则自动回退兼容老存档）。
- **验收标准**：
  - 多服务器隔离单测：在服务器 A 产生未提交进度、下载记录、阅读历史与系列覆盖设置，调用 `SessionController.switchTo(serverB)` 后：
    1. 服务器 A 的 pending 进度**不会**发往服务器 B；
    2. 服务器 B 的书架、下载管理页不混入服务器 A 的书籍；
    3. 切回服务器 A 后，其待同步进度、已下载列表与系列覆盖完整恢复。

---

#### `ARC-08` 解耦“整本下载”与被动浏览 LRU 缓存淘汰
- **对应评审问题**：#1 后半（P0 · 数据耦合）
- **问题定位**：
  - `apps/app/lib/src/data/cache/http_cache_database.dart:465-490`：`_evictImages` 在 `image` 总字节超过 `maxImageBytes`（256 MB）时，按 `lastUsedSeq` 删除最久未读的图片行，未排除 `DownloadedBooks` 已整本下载的页图。
- **改造方案**：
  1. 在 `CachedResponses` 表增加 `pinned` 布尔列（默认 `false`，或新增 `CacheKind.downloadedImage`）：
     - 被动在线阅读/浏览封面写入 `kind = 'image', pinned = false`，继续受 256 MB LRU 字节预算约束；
     - `KomgaDownloadService` 下载页图（或 `markDownloaded` 完成时）将对应 `{scope, bookId}` 下的页图标记为 `pinned = true`；
     - `_evictImages` 与 `_imageBytes` 只统计并淘汰 `kind == 'image' && pinned == false` 的被动缓存行。
  2. `KomgaDownloadService.delete(book)` 删除下载记录时，同步删掉该书对应的缓存页；设置页清晰区分“浏览缓存（可一键清理，不含已下载）”与“已下载书籍”。
- **验收标准**：
  - 新增缓存淘汰单测：设置极小的 `maxImageBytes`（如 10 KB），先整本下载 `book-1`（3 页共 9 KB），再连续浏览写入 20 张新页图（共 60 KB），断言被动缓存被正常裁剪到预算内，而 `book-1` 的全部 3 页离线读取依然 100% 命中。

---

### 2.4 批次 B3：仓库解耦、路由统一与规范门禁收口

#### `ARC-09` 下沉共享 `komgaSessionProvider` 连接池，拆分上帝接口 `LibraryRepository`
- **对应评审问题**：#4（P1 · 功能耦合）
- **问题定位**：
  - `libraryRepositoryProvider`、`readerRepositoryProvider`、`downloadServiceProvider`、`progressSyncProvider` 各自独立创建 `KomgaSession`（其中 `progressSyncProvider` 每次上传新建并销毁 `Dio` 以绕开循环依赖）；
  - `LibraryRepository` 拥有 17 个跨子域方法。
- **改造方案**：
  1. 新增 `komgaSessionProvider`：监听 `sessionProvider`，在已连接时构造唯一共享的 `KomgaSession.withApiKey`（含统一 `Dio` 连接池、`TlsTrust` 与 `HttpCache`），`ref.onDispose(session.close)` 只在一处管理。
  2. `progressSyncProvider` 直接调用 `komgaSessionProvider`（或轻量的 `ProgressUploader` 函数接口）上传进度，删除每次 `PATCH` 新建/关闭 `Dio` 的补丁，并清理 `ReaderRepository.uploadProgress` 死方法。
  3. 按限界上下文将 `LibraryRepository` 拆分为：
     - `LibraryRepository`（库、系列、书籍目录、搜索、ondeck、封面）；
     - `CollectionsRepository`（收藏集 CRUD、收藏集系列、阅读列表及书籍）；
     - `ReadStatusRepository`（或并入进度服务：`setSeriesRead`、`setBookRead`）。
- **验收标准**：
  - `ci.dart check` 分层检查与全量测试通过；每个仓库文件 ≤ 250 行；同一会话内书架、阅读器、下载器、进度补交共享同一个 `KomgaSession` 实例。

---

#### `ARC-10` `/downloads` 纳入 `GoRouter`，收敛跨模块响应式状态失效
- **对应评审问题**：#8（P2 · 路由与状态耦合）
- **问题定位**：
  - `apps/app/lib/src/screens/settings_screen.dart:206-211` 使用 `Navigator.of(context).push(MaterialPageRoute(...))` 打开 `DownloadsScreen`，游离于 `router.dart` 之外。
  - `_clearCache` 与 `SeriesReadController.setRead` 等多处手写 `ref.invalidate` 漏刷下游消费者。
- **改造方案**：
  1. 在 `apps/app/lib/src/router.dart` 注册顶层路由 `GoRoute(path: '/downloads', ...)`，`SettingsScreen` 改为 `context.push('/downloads')`，`DownloadsScreen` 返回按钮改为 `context.pop()`。
  2. 将 `downloadedBooksProvider`、`downloadsUsageProvider`、`pinnedSeriesIdsProvider`、`readingSessionsProvider` 从一次性 `FutureProvider` 升级为基于 Drift `.watch()` 的 `StreamProvider`——数据库行增删改后所有监听页面自动更新，删除散落在业务代码里的手工 `ref.invalidate` 清单。
  3. 在 `SeriesReadController.setRead` 与 `BookReadController.setRead` 成功后补齐 `shelfProvider.notifier.refreshInPlace()`、`recentSeriesProvider`、`pinnedSeriesProvider` 的联动刷新。
- **验收标准**：
  - 在设置页清空缓存后进入 `/downloads` 无残留项；在系列详情页或长按菜单将系列标为已读后，返回书架与“正在读”页，未读角标与进度条立即更新。

---

#### `ARC-11` 清理 M0 死代码与重复实现，`SessionController` 错误本地化与魔法值清理
- **对应评审问题**：#9 部分、#11（P2/P3 · 代码规范与架构卫生）
- **问题定位**：
  - `packages/komga_api/lib/src/transport.dart`（`KomgaTransport`）全仓零引用且含全局 `Accept: application/json` 反模式。
  - `packages/komga_sync_engine/lib/src/outbox.dart`（`ProgressOutbox`）未被 `InMemoryProgressStore` 复用。
  - `packages/komga_platform/lib/src/device_profile.dart`（`DeviceProfile` / `formFactorFor`）与 `komga_domain` 的 `FormFactor` 全仓零业务引用，与 `WindowSizeClass` 重复且阈值不一致。
  - `apps/app/lib/src/session/session_controller.dart:204-252` 中英文错误字符串混排硬编码；部分 Widget 残留 `Colors.black12`/`black26` 与 `440`/`600`/`0.85` 魔法值。
- **改造方案**：
  1. 删除 `packages/komga_api/lib/src/transport.dart` 及其在 `komga_api.dart` 的导出。
  2. 让 `InMemoryProgressStore` 内部委托复用 `ProgressOutbox`，消除重复的 `seq`/`ack` 实现。
  3. 清理未使用的 `DeviceProfile` / `FormFactor`（或将其与 `WindowSizeClass` 收敛为单一出口，遵循 `AGENTS.md` 不变量 6）。
  4. 将 `SessionDisconnected` 的 `error`/`hint` 改为结构化的 `ConnectionFailureKind` 枚举（类似 `ShelfFailureKind`），由 `ConnectionScreen` 通过 `AppLocalizations` 渲染对应语言文案（补齐 `app_en.arb` / `app_zh.arb`）。
  5. 将散落的 `Colors.black12`、表单最大宽度 `440`、底部弹窗高度比例等收进 `AppSizes` / 主题色方案。
- **验收标准**：
  - 切换中文/英文语言后，连接页的所有错误提示（密码错误、证书不受信任、HTTPS 端口错误、网络不通、服务端 5xx）100% 跟随当前语言，无中英混排。

---

#### `ARC-12` 拆分超长文件/大类、提炼通用增量分页器，并在 `tool/ci.dart` 固化门禁
- **对应评审问题**：#9 部分、#12（P2/P3 · 代码规范与性能）
- **问题定位**：
  - 10 个生产文件超过 350 行红线：`library_providers.dart`（666）、`reader_prefs.dart`（597）、`session.dart`（585）、`collections_screen.dart`（576）、`http_cache_database.dart`（556）、`download_providers.dart`（450）、`library_repository.dart`（410）、`tool/ci.dart`（408）、`search_screen.dart`（392）、`reader_screen_derive.dart`（386）。
  - 系列书列表、搜索、收藏集、阅读列表使用“递增 `size` 重拉 `page = 0`”造成长列表 \(O(N^2)\) 流量与缓存膨胀。
- **改造方案**：
  1. 按职责拆分超长文件：
     - `KomgaSession` 按客户端能力拆分为基础会话核心 + 目录/收藏集/进度扩展文件（或子客户端）；
     - `library_providers.dart` 拆分为 `shelf_controller.dart`（书架状态机）、`search_providers.dart`、`collections_providers.dart`；
     - `collections_screen.dart` 拆出 `collections_tab.dart` 与 `readlists_tab.dart`；
     - `search_screen.dart` 拆出 `search_results_sliver.dart`；
     - `ReaderScreen` 整理视口上下文快照，减少 `part + mixin` 隐式可变字段。
  2. 提炼通用的 `PagedListController<T>`（内置 `page` 递增拼接、`_generation` 竞态丢弃、保留旧数据报错逻辑），替换长列表的“递增 `size` 重拉全量前缀”写法。
  3. **门禁加固**：在 `tool/ci.dart` 的 `layerCheck()` 中新增两条自动扫描规则：
     - 扫描 `packages/*/lib` 与 `apps/app/lib`（排除生成代码）：单文件超过 350 行直接报错；
     - 扫描非注释代码中的裸 `catch (_)` 直接报错。
  4. 同步更新 `AGENTS.md` 的“当前阶段”段落与 `docs/` 架构说明，消除文档与代码现状脱节。
- **验收标准**：
  - 全仓所有非生成生产 `.dart` 文件严格 ≤ 350 行，单类 ≤ 300 行。
  - 长系列（> 200 本）点击“加载更多”只请求增量页 `page=1, 2...`，不重拉第 0 页。
  - `dart run tool/ci.dart check`（含新增的行数与 `catch (_)` 门禁）全绿，模拟器实操回归通过。
