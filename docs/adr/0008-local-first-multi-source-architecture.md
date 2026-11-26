# ADR 0008：来源无感的统一书库与通用融合中间层架构（本地全功能底座 + Komga 云同步增强）

- 状态：已采纳（2026-11-26 修订定稿）
- 日期：2026-11-26
- 相关：`apps/app/lib/src/router.dart`、`apps/app/lib/src/data/`、`apps/app/lib/src/providers/`、`packages/komga_domain`、`packages/komga_design_system`、`docs/local-manga-plan-2026-11.md`

## 背景

当前应用在路由层（`router.dart`）将未连接状态无条件重定向至 `/connect` 服务器登录页，把绝大多数未听说、未部署过 Komga 的普通漫画读者拒之门外。

为了同时服务好「95% 纯本地读者」与「5% Komga 自建库读者」，产品体验确立了三条核心准则：

1. **来源对用户完全无感**：阅读与日常浏览过程中，用户无需关心一本书是本地导入的还是来自 Komga 服务器，也不需要手动在“本地模式”和“服务器模式”之间来回切换数据源；本地与云端漫画共享完全一致的阅读体验与书架流。
2. **极度克制的云端标识**：仅对来自 Komga 服务器的云端漫画系列（及云端收藏集）在标题旁标注一枚低调、不显眼的小云朵图标（如 `Icons.cloud_outlined`，尺寸 `AppSizes.iconXs`），不遮挡封面主视觉，除此之外不在界面上强调两种来源的区别。
3. **本地全功能闭环，登录 Komga 作为“云同步增值增强”**：未登录服务器时，包括书架、正在读、**收藏集、阅读列表**、全局搜索、阅读历史、统计热力图与全套阅读器配置在内的绝大多数核心功能均在本地完整可用；当用户自行登录 Komga 后，自动解锁远程云端书库接入，并复用 Komga 服务端的跨设备进度对账与收藏集同步能力。

## 决策

摒弃“手动切换数据源（二选一割裂书架）”的做法，采用 **「单一无感融合书库 + 通用融合仓库中间层（`Unified*Repository`）」** 架构：

### 1. 开屏零登录墙，连接服务器升级为可选「云端同步增强」

- **路由守卫解耦**：移除 `router.dart` 中 `SessionDisconnected -> /connect` 的强制拦截。应用完成 `/splash` 初始化后，无论是否配置过 Komga 服务器，一律直达主界面 `/reading`；`/connect` 变为从设置页或空书架次级入口按需打开的普通顶层路由（带返回按钮，随时可退回）。
- **连接心智定调**：未登录时界面零报错、零离线横幅、零功能置灰；设置页原「服务器」分组升级为 **「云端书库与同步（Komga）」**——未登录时温和说明“连接 Komga 后可流式访问云端书库，并跨设备同步阅读进度与收藏集”；登录成功后，云端漫画自动汇入同一书架。

### 2. 通用融合中间层（`Unified*Repository`）与命名空间 ID 透明路由

在现有四大限界上下文抽象接口（`LibraryRepository`、`ReaderRepository`、`CollectionsRepository`、`ReadStatusRepository`）之下，构建双引擎 + 统一融合中间层：

```
UI (Screens / Widgets)  —— 零感知来源，只调 4 大抽象 Repository 接口
        │
Unified*Repository（通用融合中间层：透明路由 + 双源归并）
   ├── Local*Repository  （常驻激活：读写本地 SQLite + 本地 CBZ/文件夹归档引擎）
   └── Komga*Repository? （可选挂载：当 SessionConnected 时激活，走原生 REST + Outbox 对账）
```

1. **命名空间 ID 零查表透明路由（`local:` 前缀约定）**：
   - 本地导入生成的实体 ID 统一携带 `'local:'` 前缀（如系列 `local:s_<id>`、书籍 `local:b_<id>`、收藏集 `local:c_<id>`、阅读列表 `local:rl_<id>`）；Komga 云端实体保持服务端原生 ID。
   - 任何单实体读写操作——进详情页 `/series/:seriesId`、进阅读器 `/reader/:bookId`、取页图 `pageImage(bookId, page)`、取封面、标为已读/未读——`Unified*Repository` 仅凭 `id.startsWith('local:')` 即可在 **\(O(1)\) 时间透明路由**至 `Local*Repository` 或 `Komga*Repository`。
   - **阅读器 100% 一致**：`ReaderScreen` 及全部 25+ 个阅读器子组件拿到的始终是标准 `Book`、`List<PageInfo>` 与 `Uint8List`，双页书脊卷页、动态取色背景、自动裁白边、缩略图滑条、按系列阅读器覆盖配置（`ReaderPrefs`）与阅读会话统计在本地漫与云端漫上完全无差别运行。
2. **列表与搜索的无感融合（`UnifiedLibraryRepository`）**：
   - **未登录 Komga 时**：100% 直接委托 `LocalLibraryRepository`，毫秒级返回本地 SQLite 查询结果。
   - **已登录 Komga 时**：
     - **书架与搜索（`series` / `searchBooks`）**：在「全部」视图下，按当前排序规则（标题升/降、最近添加、书籍数量、发行日期）对本地 SQLite 结果与 Komga 分页结果执行确定性的**双游标归并分页（Dual-Cursor Merge）**；若本地同时存有导入漫画，`libraries()` 自动拼入虚拟筛选项「本地导入」与各云端库，复用既有 `LibraryFilterBar` 即可按需筛选，**不新增任何生硬的“源切换开关”**。
     - **继续阅读（`ondeck`）**：将本地在读/下一卷与云端 `ondeck` 按最近阅读活跃时间融合排序，首页大卡永远展示用户上一次真正在读的那本书。
     - **断网优雅退化**：已登录 Komga 但设备处于无网环境时，云端未命中缓存不抛整页错误，本地导入漫画与已缓存/已下载的云端漫画照常同屏展示和阅读。

### 3. 克制的云端微标设计（`isRemote`）

- 领域实体 `Series`、`KomgaCollection`、`ReadList`（及 `Book`）仅增加轻量布尔属性 `isRemote`（默认 `false`；`Komga*Repository` 映射实体置为 `true`）。
- **唯一视觉差异点**：当 `series.isRemote == true` 时，`SeriesTile`（网格标题行末尾）与 `SeriesShelfRow`（列表标题旁）渲染一枚 `AppSizes.iconXs`（16dp）、`colorScheme.onSurfaceVariant` 次级灰调的 `Icons.cloud_outlined` 小云朵图标（墨水屏下自动退化为单色细线图标）——**不压在封面上破坏构图、不用彩色胶囊抢眼、不把书架硬拆成“本地分区 / 云端分区”**。
- 在系列详情书行（`SeriesBookRow`）中：本地书籍本身已在设备存储内，自然不渲染右侧「下载离线副本」按钮；云端书籍保留原有的轻量离线缓存下载按钮。

### 4. 收藏集与阅读进度的“本地全可用 + 登录即享云同步”机制

1. **阅读进度与用户资产存储（复用 `ARC-07` `scope` 复合主键）**：
   - 本地书籍的阅读进度、置顶系列、阅读历史与按系列配置统一落入 `scope = 'local://device'` 分区；云端书籍落入对应服务器的 `scope = server.address.baseUrl` 分区。
   - `ProgressSyncService` 根据 `bookId` 前缀自动分流：本地书籍直接写入本地 `LocalProgress`（`pendingSeq = null`）并实时刷新本地已读计数；云端书籍写入 Outbox 并在在线时自动与 Komga 服务端执行 `lastModified` 双向对账同步。
   - `PinnedSeries`（置顶系列）、`ReadingSessions`（阅读历史）与 `Insights`（统计热力图）在展示层聚合 `'local://device'` 与当前已连接服务器 `scope`，实现全书库统一的历史与统计体验。
2. **收藏集与阅读列表（`UnifiedCollectionsRepository`）**：
   - **未登录 Komga 时**：由 `LocalCollectionsRepository`（基于 `komga_native.sqlite` 的 `LocalCollectionsRows` / `LocalReadListsRows`）完整提供新建、重命名、成员增删、排序、删除与封面拼贴，体验零阉割。
   - **已登录 Komga 时**：
     - 「收藏」Tab 合并展示本地收藏集与 Komga 云端收藏集（云端收藏集标题旁同样带低调小云朵微标）；
     - 当用户将**云端系列/书籍**新建或加入收藏集/阅读列表时，`UnifiedCollectionsRepository` **直接复用 `KomgaCollectionsRepository` 同步至 Komga 服务端**，实现多设备云端共享；
     - 当用户将**本地系列/书籍**（或同时勾选本地漫 + 云端漫组建混合书单）加入新收藏集/阅读列表时，自动持久化至 `LocalCollectionsRepository`（因 Komga 服务端 API 不接受未知本地 ID，混合书单在读取成员详情时由统一中间层透明并发拉取本地与云端条目拼装返回），用户全程无感、零报错。

## 备选方案与否决理由

| 备选方案 | 否决理由 |
|---|---|
| **显式数据源切换模式（顶栏下拉框在「本地库」与「Komga 库」间二选一）** | 强迫用户时刻感知并记忆“某本书在本地还是在服务器”，搜书和继续阅读被割裂成两个孤岛，违背“来源对用户无感”的核心体验目标。 |
| **未连接时的互斥「离线模式」（连接服务器后隐藏本地书）** | 存在“登录服务器后本地书消失”的致命断层，且把绝大多数未建服务器的普通用户置于功能受限的“试用二等公民”心智。 |
| **将远程 Komga 全量拉取塞进本地目录 SQLite 表** | 数万册远程 NAS 大库在首次连接时会遭遇漫长的同步卡顿与删改对账风暴；通过 `Unified*Repository` 实时归并本地表与远程流式分页，既能秒开又能保持 Komga 原生能力。 |

## 后果

- **用户体验高度纯粹统一**：不登录就是功能 100% 完整的现代本地漫画阅读器；登录 Komga 则是纯粹的“加法增益”（书架自然多出带低调小云标的云端藏书，并自动获得进度与收藏集跨端同步）。
- **UI 层改动面进一步缩小**：无需设计、维护顶栏/侧栏数据源切换器，书架、收藏、搜索、历史、阅读器的现有页面结构与交互流 95% 保持原貌，所有多源路由与归并复杂度全部封装在 `src/data/unified/` 仓库中间层内，可由纯 Dart 单测高覆盖锁定。
