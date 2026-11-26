# ADR 0008：「编目按源分组 + 阅读跨源无感」的多源双栖架构（面向 Local / Komga / 未来 Kavita & OPDS）

- 状态：已采纳（2026-11-26 终审定稿）
- 日期：2026-11-26
- 相关：`apps/app/lib/src/router.dart`、`apps/app/lib/src/data/`、`apps/app/lib/src/providers/`、`packages/yomu_domain`、`packages/yomu_design_system`、`docs/local-manga-plan-2026-11.md`

## 背景

当前应用在路由层（`router.dart`）将未连接状态强制重定向至 `/connect` 服务器登录页，将 95%+ 未部署过 Komga 的普通漫画读者拒之门外。

在将产品演进为「支持本地漫画导入与多服务器接入的通用漫画阅读器」时，我们需要同时满足两个层面的核心诉求：

1. **用户体验诉求**：
   - **免登录完整可用**：不登录任何服务器即可享受包含书架、正在读、**收藏集、阅读列表**、搜索、历史与统计热力图在内的 100% 完整本地阅读体验；登录 Komga 呈现为“解锁远程云书库与跨设备云同步”的纯增量价值；
   - **阅读与续读无感**：在日常高频的「打开首页接着读（Reading Now）」与「阅读器内翻页（Reader）」过程中，用户无需关心漫画来自本地还是云端服务器，阅读手感完全一致；云端漫画仅以低调的小云朵图标（`Icons.cloud_outlined`）克制标识。
2. **长期维护与多协议扩展诉求（规避伪 iCloud 全局混排陷阱）**：
   - 不同于拥有单一中心库的 Apple iCloud，「本机 SQLite + Komga + 未来的 Kavita / OPDS」属于**互不通气、主键格式不同（如 Kavita 采用自增整数 ID）、排序规则不等价、能力不对称的异构自治数据源**；
   - 若在「书架分页网格」与「收藏集成员」层强行做跨源全局混排，会引发 **收藏集跨源同步分裂（Split-Brain 与服务端 400 报错）、多路异构分页乱序漏项、慢网远程源插队导致网格跳动（Layout Shift）、同名漫画重影不可合并、批量多选能力坍缩** 五大结构性深坑。

## 决策

采用经过 Panels 与 Infuse 等成熟多源客户端验证的 **「编目按源分组隔离 + 正在读与阅读器跨源无感汇聚（管理归各家，阅读归一处）」** 架构，确立四条核心架构不变量：

### 1. 可扩展多协议标识 `sourceKey`（替代二元布尔 `isRemote`）

- 摒弃无法扩展第 3 种协议的二元布尔判断，统一使用字符串分区标识 `sourceKey` 表征内容归属源：
  - **本机内置源**：固定常量 `kLocalSourceKey = 'local://device'`；
  - **Komga 服务器源**：沿用规范化 `server.address.baseUrl`（与 `ARC-07` 既有 `komga_native.sqlite` / `komga_cache.sqlite` 的 `scope` 列 **100% 零迁移兼容**）；
  - **未来异构远程源预留**：采用显式协议前缀（如 `'kavita|<baseUrl>'`、`'opds|<baseUrl>'`），彻底杜绝 Kavita 整数 ID 与多台服务器之间的主键碰撞。
- 领域实体 `Series`、`Book`、`KomgaCollection`、`ReadList` 携带 `sourceKey`（默认 `kLocalSourceKey`，派生只读属性 `bool get isCloud => sourceKey != kLocalSourceKey`）。

### 2. 编目流（书架 / 收藏集 / 搜索）：单源时隐形，多源时按源清晰分组

- **开屏免登录守卫**：移除 `router.dart` 中 `SessionDisconnected -> /connect` 的强制拦截，`/splash` 恢复完成后直达主界面 `/reading`；`/connect` 退化为从设置页或引导入口按需 push 的普通路由。
- **冷启动源选择与老用户兼容**：
  - 优先恢复用户上次选中的 `activeSourceKey`（若对应服务器已移除则自动回退 `kLocalSourceKey`）；
  - 首次升级尚无 `activeSourceKey` 时：若 `ServerStore.load() != null`（老版本已登录 Komga 用户），默认选中该服务器分组保证升级零感知；否则默认选中「本机」源。
- **单源隐形原则（服务 95% 纯本地用户）**：
  - 当应用未配置任何远程服务器（仅存在「本机」单一源）时，书架与收藏页**完全隐藏源切换分组栏**，界面没有任何服务器概念残留；本地书架、**本地收藏集与本地阅读列表**（`LocalCollectionsRepository`）从首期起即 100% 完整可用。
- **多源同构分组原则（服务双修与未来多协议用户）**：
  - 一旦连接了 1..N 台服务器（Komga，及未来的 Kavita / OPDS），书架与收藏页顶部（窄屏胶囊条 / 平板 `ShelfSideRail`）展示清晰的源分组切换：`[ 本机 ]`、`[ ☁ Komga ]`……
  - **严格同源归属**：每个分组内部 100% 调用该源独立的 `LibraryRepository` 与 `CollectionsRepository`：
    - 「本机」分组：2ms 纯本地 SQLite 分页，支持本地物理删除、合并系列、修改元数据、创建本地收藏集，永远不受远程断网或慢网拖累；
    - 「☁ Komga」分组：纯 Komga 原生流式分页、标签筛选与 **100% 服务端双向同步收藏集**（只选该服书籍，零跨源外键 400 错误，零多端同步分裂）；
    - **\(O(1)\) 协议扩展性**：未来接入 Kavita 或 OPDS 时，只需新增独立的 `SourceBackend` 实现挂入 `SourceRegistry`，对本地引擎与 Komga 仓库代码 **0 侵入**。

### 3. 阅读与回访流（正在读 / 阅读器 / 历史统计）：跨源无感汇聚 + 低调小云标

在不会产生异构分页与写冲突的「消费与回访层」实现完全无感的跨源体验：

1. **首页「正在读（`ReadingNowScreen`）」跨源汇聚**：
   - 顶部的「继续阅读」大卡与「最近阅读」横滑条，自动从「本机」与已连接远程源各取最近活跃的前 N 本在读/下一卷书籍，在内存中按最后阅读时间归并展示（仅十几条活跃数据，无分页负担；远程源断网时静默保留本机活跃书与命中缓存的云端书，绝不阻断首页）；
   - 来自云端源（`isCloud == true`）的卡片仅在标题旁渲染一枚 `AppSizes.iconXs`（16dp）、`colorScheme.onSurfaceVariant` 低对比度的 `Icons.cloud_outlined` 细线小云标，克制且不遮挡封面。
2. **阅读器（`ReaderScreen`）跨源直达与完全一致体验**：
   - 路由与阅读器通过 `(sourceKey, bookId)` 从 `SourceRegistry` 直接解析对应源的 `ReaderRepository`（无需强迫用户先在书架切分组就能从「正在读」或「阅读历史」一键开读任意源的书）；
   - 本地归档与远程服务统一产出 `Book`、`List<PageInfo>` 与 `Uint8List`，双页书脊卷页、裁白边、动态背景、缩略图条、预设与按系列覆盖（键格式 `$sourceKey|$seriesId`）100% 无差别生效。
3. **阅读历史与统计热力图（`HistoryScreen` / `InsightsScreen`）全局汇总**：
   - 本地 `ReadingSessions` 统一记录本机与所有服务器的阅读时长（每条记录已自带 `scope = sourceKey`），热力图完整反映用户的全部阅读足迹；点击历史记录直接按其 `scope` 打开对应阅读器续读。

### 4. 单书唯一权威源，进度回写物理绝缘（零同步冲突）

- 每本书永远只向其所属的 `sourceKey` 回写阅读进度：
  - `sourceKey == 'local://device'` → `ProgressSyncService` 直接写入本地 `LocalProgress`（`pendingSeq = null`），跳过网络队列；
  - `sourceKey == komgaBaseUrl` → 写入该服专属 `scope` 的 Outbox 并仅向该台 Komga 执行 `PATCH` 与 `lastModified` 对账；
  - 未来 `sourceKey == 'kavita|...'` → 路由至独立的 Kavita 进度同步器。
- 不做跨源同名书籍进度猜测互写，从根源上保证多服务器并存时 **0 同步冲突**。

## 备选方案与否决理由

| 备选方案 | 否决理由 |
|---|---|
| **类 iCloud 书架与收藏集全局强混排** | 异构源缺乏统一主键与一致排序规则，会导致跨源收藏集同步分裂/400 报错、分页重复漏项、慢服务器插队引发布局抖动，且后续接入 Kavita / OPDS 时特判复杂度呈 \(O(N^2)\) 爆炸。 |
| **未连接时的互斥「离线模式」（登录服务器后隐藏本地书）** | 登录服务器后本地导入漫画消失，存在严重体验断层；且将 95% 纯本地用户置于残缺试用版心智。 |
| **完全孤岛隔离（连首页「正在读」与阅读历史都互不相通）** | 每次打开 App 想接着看上一本书还需先回忆并切换源分组，牺牲了最低成本即可换取的高频续读流畅感。 |

## 后果

- **体验与工程维护双赢**：未登录用户获得零打扰的纯粹本地阅读器；多源用户在高频续读与阅读器内获得无感体验，同时在书架整理与收藏集同步上拥有清晰稳定的边界。
- **天然就绪的多服务器插件底座**：抽象出以 `sourceKey` 寻址的 `SourceRegistry`（管理每个源的 `Library` / `Reader` / `Collections` / `ReadStatus` 四大仓库实例与 `SourceCapabilities` 能力位），未来横向扩展 Kavita、OPDS、WebDAV 时无需改动上层状态机与 UI 框架。
