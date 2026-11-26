# 本地漫画导入与无感云端融合实施任务书（2026-11）

> **架构决策依据**：
> - [ADR 0008：来源无感的统一书库与通用融合中间层架构（本地全功能底座 + Komga 云同步增强）](adr/0008-local-first-multi-source-architecture.md)
> - [ADR 0009：本地漫画导入（`file_picker`）与纯 Dart 随机访问 CBZ/ZIP 引擎](adr/0009-local-comic-import-and-cbz-reader.md)
> **三大产品体验铁律（已确认）**：
> 1. **底层来源完全无感**：不设“切换本地/服务器”模式开关；本地导入与 Komga 云端漫画同处一个统一书架、正在读、搜索、收藏集与阅读历史中，阅读器内体验 100% 一致，由通用中间层 `Unified*Repository` 按 `local:` 命名空间 ID 透明路由。
> 2. **克制的云端标识**：仅对来自 Komga 云端的系列（及云端收藏集）在标题旁展示一枚低调不显眼的小云朵图标（`Icons.cloud_outlined`，`AppSizes.iconXs`），不压封面、不分组隔断、不强调来源差异。
> 3. **本地全功能闭环 + 登录解锁云同步**：不登录 Komga 即可完整使用包括**收藏集与阅读列表**在内的全部本地阅读与管理能力；登录 Komga 后自动接入云端书库，并无缝复用 Komga 的跨端阅读进度对账与服务端收藏集同步能力。
>
> **工程红线（遵循 `AGENTS.md`）**：
> - 每个 `LMA-XX` 任务独立闭环、独立可验收；
> - 全仓非生成生产 `.dart` 文件严格 **≤ 350 行**、单类 **≤ 300 行**、零 `dynamic`、零裸 `catch (_)`；
> - 新增 UI 补齐黄金图（Windows 基线：手机 `light` / 平板 `dark` / 墨水屏 `eink`）并用 `read_image` 自查；
> - 每次代码提交前必须通过 `dart run tool/ci.dart check` 全绿 + `dart run tool/ci.dart install` 模拟器实操验证。

---

## 0. 批次划分与交付门禁总览

> **估时口径**：S ≤ 0.5–1 天；M = 1.5–2.5 天；L = 3–4 天（均已包含单测、数据库迁移测试、黄金图与模拟器验证）。

| 批次 | 阶段目标 | 包含任务 | 预估周期 | 阶段交付出口（Gate） |
|---|---|---|---|---|
| **Batch L0：纯逻辑与数据底座** | 纯 Dart 归档引擎、本地目录 + 本地收藏集 SQLite 表、本地四大 Repository 就绪（不改线上 UI） | `LMA-01` ~ `LMA-04` | 约 5–6 天 | `komga_local_archive` 全边界单测全绿；`Local*Repository` 四大接口（含本地收藏集/阅读列表）契约测试全绿 |
| **Batch L1：无感融合中间层与 MVP 闭环** | 通用融合层 `Unified*Repository`、破除开屏登录墙、`file_picker` 导入管线、低调云图标与设置云同步入口 | `LMA-05` ~ `LMA-08` | 约 5–6 天 | **可对外发版获客**：免登录享受含收藏集在内的完整本地阅读体验；登录 Komga 后云端漫带微云标无感汇入同一书架并自动跨端同步 |
| **Batch L2：本地编目精修与外部打开** | 本地书籍/系列删除、系列合并/拆分与元数据编辑、自定义封面、系统外部点击 `.cbz` 直接用 Yomu 打开 | `LMA-09` ~ `LMA-12` | 约 4–5 天 | 本地散装单卷整理体验对齐一线阅读器；支持从系统文件/聊天/网盘一键打开入库 |

---

## 1. 任务总表与依赖拓扑

| 任务 ID | 所属批次 | 任务名称 | 优先级 | 估时 | 前置依赖 | 状态 |
|---|---|---|---|---|---|---|
| `LMA-01` | Batch L0 | 新建纯 Dart 包 `komga_local_archive`（`RandomAccessByteSource`、魔数嗅探、ZIP/CBZ 按页读取、宽高嗅探、`ComicInfo.xml`、自然排序） | P0 | M | — | [ ] |
| `LMA-02` | Batch L0 | 领域实体轻量扩展 `isRemote` 与 `local:` 命名空间 ID 工具（`packages/komga_domain`） | P0 | S | — | [ ] |
| `LMA-03` | Batch L0 | 扩展用户库 `komga_native.sqlite` 新增本地书目表与本地收藏集/阅读列表表，打通本地进度直写 | P0 | M | `LMA-02` | [ ] |
| `LMA-04` | Batch L0 | 完整实现本地四大仓库：`LocalLibrary` / `LocalReader` / `LocalCollections` / `LocalReadStatusRepository` | P0 | M | `LMA-01`, `LMA-03` | [ ] |
| `LMA-05` | Batch L1 | 实现通用融合中间层 `Unified*Repository`（ID 透明路由、双游标归并分页、收藏集智能云/本地分流、断网保本地） | P0 | M–L | `LMA-04` | [ ] |
| `LMA-06` | Batch L1 | 接入 `file_picker` 与受管沙盒导入管线 `LocalComicImporter`（CBZ/ZIP + 图片文件夹 + 首图封面提取） | P0 | M | `LMA-01`, `LMA-03` | [ ] |
| `LMA-07` | Batch L1 | 解除 `router.dart` 登录墙、Provider 接入融合层、云端系列低调小云标与「云端同步（Komga）」设置升级 | P0 | M | `LMA-05`, `LMA-06` | [ ] |
| `LMA-08` | Batch L1 | MVP 中英双语文案、黄金图基线（无感书架/云微标/本地空态/设置云同步）与模拟器端到端验收 | P0 | S–M | `LMA-07` | [ ] |
| `LMA-09` | Batch L2 | 本地书籍/系列单选与多选批量删除（SQLite + 沙盒物理文件 + 存储统计联动） | P1 | M | `LMA-08` | [ ] |
| `LMA-10` | Batch L2 | 本地编目管理：编辑标题/卷号/方向/简介、散装单卷合并与拆分系列 | P1 | M | `LMA-09` | [ ] |
| `LMA-11` | Batch L2 | 本地自定义封面（阅读器「将当前页设为封面」与相册选图） | P2 | S–M | `LMA-10` | [ ] |
| `LMA-12` | Batch L2 | 系统文件关联（Android Intent / iOS Document Types & Files.app 共享）：外部点击 `.cbz` 直接导入阅读 | P1 | S–M | `LMA-06`, `LMA-08` | [ ] |

---

## 2. 核心架构与数据模型设计

### 2.1 通用融合中间层（`src/data/unified/`）职责边界

全部多源复杂度严格收敛在 `apps/app/lib/src/data/unified/` 四个融合类中，对上层 Riverpod Controller 与 UI 完全透明（每文件 ≤ 280 行）：

```
apps/app/lib/src/data/
├─ local/
│  ├─ local_tables.dart                  # LocalSeries / LocalBooks / LocalPages / LocalCollections / LocalReadLists
│  ├─ local_catalog_dao.dart             # 本地书目与分页/排序/搜索/ondeck 查询 DAO
│  ├─ local_curation_dao.dart            # 本地收藏集与阅读列表 CRUD DAO
│  ├─ local_library_repository.dart      # 本地书架与封面实现
│  ├─ local_reader_repository.dart       # 本地 ZIP/文件夹按页读取 + ByteLruCache
│  ├─ local_collections_repository.dart  # 本地收藏集与阅读列表完整实现
│  ├─ local_read_status_repository.dart  # 本地整系列/单本标为已读未读
│  └─ local_comic_importer.dart          # file_picker -> 沙盒流式入库 + 宽高嗅探 + 300px 封面生成
└─ unified/
   ├─ unified_library_repository.dart    # 合并本地与可选 Komga 书架、搜索、ondeck、库筛选与封面路由
   ├─ unified_reader_repository.dart     # 按 bookId 是否以 'local:' 开头 O(1) 路由页图与书详情
   ├─ unified_collections_repository.dart# 未登录走本地；已登录合并展示，纯云端成员自动走 Komga 同步，含本地成员落本地
   └─ unified_read_status_repository.dart# 按 seriesId / bookId 前缀路由已读状态变更
```

**四个关键无感融合契约**：
1. **单实体 \(O(1)\) 透明路由**：所有 `bookId` / `seriesId` / `collectionId` / `readListId` 经 `isLocalContentId(id)`（`id.startsWith('local:')`）一步分发。阅读器内翻页、预取、保存进度、切下一本、加收藏集，UI 代码 **0 处判断来源**。
2. **书架融合与筛选（`UnifiedLibraryRepository`）**：
   - 未连接 Komga 时：直接返回 `LocalLibraryRepository` 结果，`libraries()` 返回空列表（不展示多余筛选条）；
   - 已连接 Komga 时：
     - `libraryId == null`（默认「全部」）：按当前 `SeriesSort` 确定性归并本地系列与云端系列（云端系列携带 `isRemote: true`）；
     - 若本地已有导入系列，`libraries()` 返回 `[Library(id: 'local://library', name: 本地导入), ...komgaLibraries]`，自然复用现有 `LibraryFilterBar` 胶囊，**绝不引入生硬的顶栏“模式切换器”**；
     - 当手机处于飞行模式/断网导致 `KomgaLibraryRepository` 抛 `NetworkFailure` 且无缓存时，若本地存在漫画，**保留全部本地漫画正常渲染**，仅通过轻量提示告知云端暂不可达，绝不让断网把整个书架变成报错页。
3. **收藏集智能云同步分流（`UnifiedCollectionsRepository`）**：
   - 未登录 Komga：所有新建/编辑收藏集与阅读列表均写入 `LocalCollectionsRepository`；
   - 已登录 Komga：
     - 列表页合并展示本地收藏集（`isRemote: false`）与 Komga 收藏集（`isRemote: true`，标题旁带低调微云标）；
     - 新建收藏集/阅读列表时：若所选成员**全部为云端项**（`!isLocalContentId`），直接调用 `KomgaCollectionsRepository` 创建在 Komga 服务端以享受跨端同步；若包含**本地项**（纯本地或本地+云端混选），自动创建在 `LocalCollectionsRepository`，读取成员时由中间层透明并发拉取本地与云端详情拼装返回，彻底杜绝服务端 `400` 报错。
4. **统一置顶、历史与统计**：
   - `PinnedSeries`、`ReadingSessions`（阅读历史）与 `Insights`（阅读热力图）在未连接服务器时读写 `'local://device'`，在连接服务器后同时聚合 `'local://device'` 与当前连接服务器的 `scope`，点击任意历史记录直接打开 `/reader/:bookId` 无缝续读。

### 2.2 `packages/komga_local_archive` 纯 Dart 归档包结构（每文件 ≤ 250 行）

```
packages/komga_local_archive/
├─ pubspec.yaml                      # 纯 Dart 包，零第三方依赖，仅依赖 komga_domain
├─ lib/
│  ├─ komga_local_archive.dart       # 统一公开导出
│  └─ src/
│     ├─ byte_source.dart            # RandomAccessByteSource 接口 + MemoryByteSource + FileByteSource
│     ├─ archive_errors.dart         # ArchiveException + ArchiveErrorKind 密封枚举 + 文件头魔数嗅探
│     ├─ natural_sort.dart           # 跨平台自然文件名排序 + 垃圾条目过滤器
│     ├─ zip_directory.dart          # EOCD / ZIP64 EOCD 与中央目录解析器 + 非 UTF-8 文件名容错
│     ├─ zip_page_reader.dart        # 按偏移读单页 + ZLibCodec(raw: true) 解压
│     ├─ folder_page_reader.dart     # 本地图片文件夹阅读实现（统一 ArchiveBookSource 接口）
│     ├─ image_dimensions.dart       # PNG / JPEG / WebP / GIF / AVIF 头部极速宽高嗅探
│     └─ comic_info_parser.dart      # 零依赖 ComicInfo.xml 解析器 + 文件名启发式卷号提取
└─ test/                             # 纯内存字节构造 ZIP/ZIP64/伪后缀/损坏包/加密包/图片头/XML 单测
```

---

## 3. 逐项任务规格与验收标准

### 3.1 Batch L0：纯逻辑与本地全功能数据底座

#### `LMA-01` 新建纯 Dart 包 `packages/komga_local_archive`
- **目标**：把 `.cbz/.zip` 随机访问按页读取、魔数嗅探、图片文件夹扫描、图片头极速宽高嗅探、`ComicInfo.xml` 解析与自然排序做成零外部依赖的 100% 纯 Dart 引擎。
- **改造内容**：
  1. 在根 `pubspec.yaml` 的 `workspace:` 注册 `packages/komga_local_archive`，并同步加入 `tool/ci.dart`（`_purePackages`）与 `tool/ci_checks.dart`（`_productionRoots` + `pureForbidden`）；
  2. 实现 `RandomAccessByteSource`、`sniffContainerMagic`、`ZipDirectory`、`ZipPageReader`、`FolderPageReader`、`ImageDimensions`、`ComicInfoParser` 与 `naturalCompare`。
- **单测边界覆盖（必测）**：
  - 0 页空包、无图片包、伪后缀（`.cbr` 实为 ZIP 魔数）、含 `__MACOSX/` 与 `.DS_Store` 垃圾条目的压缩包；
  - Stored (`method = 0`) 与 Deflate (`method = 8`) 随机跳页字节一致性；加密 ZIP 与截断损坏包返回结构化枚举错误；
  - 自然排序（`2.jpg < 10.jpg`）、PNG/JPEG(含 EXIF)/WebP 头部宽高提取、`ComicInfo.xml`（BOM、实体转义、`Manga="YesAndRightToLeft"`）。
- **验收标准**：`dart test packages/komga_local_archive` 1 秒内全绿，`dart run tool/ci.dart check` 全绿。

---

#### `LMA-02` 领域实体扩展 `isRemote` 与 `local:` 命名空间 ID 工具
- **目标**：在不污染现有领域模型与不引发既有 99 张黄金图漂移的前提下，提供最小化的来源标记与 ID 路由判据。
- **改造内容**：
  1. `packages/komga_domain` 新增 `src/content_origin.dart`：定义常量 `kLocalScopeKey = 'local://device'`、`kLocalLibraryId = 'local://library'`、`kLocalIdPrefix = 'local:'` 及纯函数 `isLocalContentId(String id)`；
  2. 在 `Series`、`Book`、`KomgaCollection`、`ReadList` 构造函数增加可选参数 `this.isRemote = false`（默认 `false` 保证全部存量单测与黄金图基线向后兼容）；
  3. 在 `KomgaLibraryRepository` 与 `KomgaCollectionsRepository`（或 `komga_api` 解析出口）将来自服务端的 `Series`、`Book`、`KomgaCollection`、`ReadList` 标记为 `isRemote = true`。
- **验收标准**：`dart test packages/komga_domain` 与 `dart test packages/komga_api` 全绿，现有黄金图零意外变动。

---

#### `LMA-03` 扩展 `komga_native.sqlite` 新增本地书目表与本地收藏集表
- **目标**：一次性完成用户资产数据库 `ProgressDatabase` 的平滑迁移，同时覆盖本地系列/书籍/页索引与**本地收藏集/阅读列表**，并打通本地阅读进度直写。
- **改造内容**：
  1. 新增 `local_tables.dart`：定义 `LocalSeriesRows`、`LocalBooksRows`（存相对于 `<ApplicationSupport>/local_comics/` 的 `relativePath`，防 iOS 容器 UUID 变化失效）、`LocalPagesRows`、`LocalCollectionsRows`、`LocalReadListsRows`；
  2. 拆分为 `local_catalog_dao.dart`（系列/书籍查询、搜索、全部 `SeriesSort`、`SeriesReadStatus`、本地 `ondeck` 推导）与 `local_curation_dao.dart`（本地收藏集与阅读列表增删改查），升级 `ProgressDatabase.schemaVersion` 并编写无损 `onUpgrade`；
  3. 调整 `ProgressSyncService`：遇到 `isLocalContentId(bookId)` 时直接以 `scope = kLocalScopeKey`、`pendingSeq = null` 落盘 `LocalProgress`，不进入远程 HTTP 冲洗队列。
- **验收标准**：旧版 `ProgressDatabase` 升级迁移单测 100% 保留原有数据；本地书目排序/筛选、`ondeck` 下一卷推导与本地收藏集 CRUD 单测全绿。

---

#### `LMA-04` 完整实现本地四大仓库（`LocalLibrary` / `Reader` / `Collections` / `ReadStatus`）
- **目标**：让未登录状态下的本地模式具备与在线 Komga 100% 对等的四大 Repository 实现（含完整收藏集与阅读列表）。
- **改造内容**：
  1. `LocalLibraryRepository`：实现书架分页、全局搜索、`ondeck`、磁盘 300px 封面读取 + 内存 `ByteLruCache`；
  2. `LocalReaderRepository`：从 `LocalPagesRows` 秒返含精确宽高的 `PageInfo`，经 `ZipPageReader` / `FolderPageReader` 单页按需解压 + 64 页内存 `ByteLruCache` + `_inFlight` 并发去重；
  3. `LocalCollectionsRepository`：完整实现 13 个收藏集与阅读列表接口（支持创建、改名、排序、成员增删、删除，与 `curation_ops.dart` 无缝配合）；
  4. `LocalReadStatusRepository`：实现本地整系列与单本书标记已读/未读。
- **验收标准**：四大本地仓库离线契约单测全绿，文件缺失/损坏统一映射为 `ShelfFailure` 而不抛未捕获异常。

---

### 3.2 Batch L1：通用融合中间层与 MVP 交付闭环

#### `LMA-05` 实现通用融合中间层 `Unified*Repository`
- **目标**：把本地仓库与可选的 `Komga*Repository` 无感粘合为单一对外接口，兑现“底层来源对用户无感 + 登录即叠加云同步”。
- **改造内容**：
  1. 实现 `UnifiedLibraryRepository`：按 ID 前缀路由 `seriesById` / `book` / `books` / `seriesCover` / `bookCover`；融合 `libraries()`、`series()`（双游标归并分页 + 按库筛选）、`searchBooks()`、`ondeck()`，并在云端断网失败时保住全部本地书籍正常展示；
  2. 实现 `UnifiedReaderRepository` 与 `UnifiedReadStatusRepository`：按 `isLocalContentId` \(O(1)\) 透明路由；
  3. 实现 `UnifiedCollectionsRepository`：合并展示本地与云端收藏集/阅读列表；未登录或成员含本地项时写 `LocalCollectionsRepository`（混合成员列表支持跨本地与云端拉取详情拼装），已登录且全为云端成员时写 `KomgaCollectionsRepository` 同步上云。
- **验收标准**：编写详尽的 `unified_repositories_test.dart`：覆盖 ① 纯本地未登录；② 本地 + Komga 双源混合排序分页与搜索；③ 已登录但断网时本地漫画与已缓存云端漫画照常可读；④ 纯云端收藏集自动上云、纯本地与混合收藏集自动落本地且零 400 报错。

---

#### `LMA-06` 接入 `file_picker` 与受管沙盒导入管线 `LocalComicImporter`
- **目标**：支持一键多选导入 `.cbz` / `.zip` 压缩包或漫画图片文件夹，自动提取元数据与封面。
- **改造内容**：
  1. `apps/app/pubspec.yaml` 引入 `file_picker`（关联 ADR 0009），封装抽象 `ComicFilePicker` 供测试替换；
  2. 实现 `LocalComicImporter` 与 `LocalImportController`：流式分块拷入受管目录 `<ApplicationSupport>/local_comics/<bookId>/` → 校验归档并嗅探每页宽高 → 解析 `ComicInfo.xml`（无 XML 时按目录/文件名启发式归并同名系列与卷号）→ 解码生成 360px 封面缩略图（连体宽封支持自动裁正封）→ 事务落库并清理选择器临时文件。
- **验收标准**：单测覆盖多卷同名系列自动聚合、正常包与加密/损坏包混合导入容错、沙盒零残留垃圾文件。

---

#### `LMA-07` 解除开屏登录墙、低调云端小图标与「云端同步」设置体验
- **目标**：打通开箱即用的无感 UI 闭环，视觉保持极度克制。
- **改造内容**：
  1. **路由与 Provider 接线**：
     - `router.dart` 移除 `SessionDisconnected -> /connect` 重定向，冷启动恢复后直达 `/reading`；`/connect` 增加返回按钮；
     - `libraryRepositoryProvider`、`readerRepositoryProvider`、`collectionsRepositoryProvider`、`readStatusRepositoryProvider` 统一注入 `Unified*Repository`（监听 `komgaSessionProvider` 动态热插拔云端分支，彻底移除未登录抛错的 `requireKomgaSession`）；
     - 统一 `PinnedSeries`、`ReadingSessions` 与 `ReaderPrefs` 支持本地与当前服务器的复合查询/读写，移除 `SettingsLibrarySection` 在未登录时的隐藏限制；
  2. **低调云端微标（唯一视觉区分）**：
     - 在 `SeriesTile`（标题文字右侧）与 `SeriesShelfRow`、`CollectionsTab` / `ReadListsTab` 中：仅当 `isRemote == true` 时渲染一枚 `AppSizes.iconXs`（16dp）、`colorScheme.onSurfaceVariant` 颜色的 `Icons.cloud_outlined` 细线小云朵图标，不遮挡封面、不加底色框；
     - `SeriesBookRow` 与 `SeriesDetailScreen` 对本地书籍（`!book.isRemote`）自然隐藏离线下载按钮；`OfflineOverlay` 仅在已连接 Komga 服务器且发生网络断连时温和提示云端离线（纯本地未登录时永不出现）；
  3. **导入入口与设置页「云端同步增强」卡片**：
     - 书架顶栏增加简洁的「导入漫画（`+`）」玻璃动作按钮（支持选文件 / 选文件夹）；空书架展示优雅的「导入本地漫画」主引导 + 轻量次级链接「连接 Komga 云端书库」；
     - 设置页将「服务器」组升级为 **「云端同步与远程书库（Komga）」**（清晰传达“登录即可跨设备同步进度与收藏集、流式浏览 NAS 书库”），并在「存储」组展示本地导入漫画占用空间。
- **验收标准**：Widget 测试覆盖未登录全页面畅通（含新建本地收藏集）、登录 Komga 后同屏展示本地系列（无图标）与云端系列（带低调小云标）、本地书行不显示下载按钮、断网不阻断本地阅读。

---

#### `LMA-08` MVP 双语文案、黄金图基线与模拟器端到端验收
- **改造内容**：
  1. 补齐 `app_en.arb` 与 `app_zh.arb` 文案（严禁“离线受限模式”类负面表述，统一采用自然的书库导入与云同步增强措辞）；
  2. 更新并新增黄金图基线（覆盖含本地与云端微标混排的书架、本地空态引导、设置页云同步区块，涵盖手机 `light`、平板 `dark`、墨水屏 `eink`），逐张通过 `read_image` 复查视觉克制度；
  3. 更新 `AGENTS.md` 架构现状说明。
- **验收标准**：
  - `dart run tool/ci.dart check` 全绿；
  - `dart run tool/ci.dart install` 装 Release 包到模拟器，实测：① 全新未登录状态下导入 `.cbz` 阅读、建收藏集、看历史热力图完整闭环；② 登录本地 Komga 后，云端漫画带低调小云标自动汇入同一书架，云端阅读进度与收藏集正常同步。

---

### 3.3 Batch L2：本地编目精修与外部文件打开

#### `LMA-09` 本地书籍与系列删除（单删 + 批量多选删除）
- **改造内容**：支持对本地书籍/系列（`!isRemote`）单删或多选批量「从本机删除」，事务清理 SQLite 书目、进度、收藏集成员引用及沙盒 `local_comics/<bookId>` 物理文件（若多选同时勾选了云端系列，明确仅删除其中的本地导入项或给出清晰说明）。
- **验收标准**：删除后书架与收藏集即时刷新，沙盒文件零残留，存储占用实时扣减。

#### `LMA-10` 本地编目编辑与散装单卷合并/拆分系列
- **改造内容**：对本地系列/书籍开放「编辑信息」面板（改标题、卷号、作者、简介、阅读方向 LTR/RTL/条漫，置 `metadataLocked = true`），以及书架多选将多个本地散装单卷「合并为一个系列」、书行菜单「拆出为独立系列」。
- **验收标准**：3 个散装 `.cbz` 合并并重排卷号后，系列详情与阅读器「下一本」连续跳转完全准确。

#### `LMA-11` 本地自定义封面（阅读器设当前页为封面 + 相册选图）
- **改造内容**：本地书籍在阅读器 `⋯` 菜单支持「将当前页设为封面」，在系列编辑面板支持从系统文件选取自定义封面图。
- **验收标准**：设第 3 页彩页为封面后返回书架，缩略图即时更新。

#### `LMA-12` 系统级外部文件打开导入（Open With & iOS Files.app 共享目录）
- **改造内容**：Android `AndroidManifest.xml` 注册 `.cbz` / `.zip` 的 `ACTION_VIEW` 与 `ACTION_SEND`；iOS `Info.plist` 配置 `CFBundleDocumentTypes` 与 `UIFileSharingEnabled = true`；从系统文件管理器、聊天软件或网盘点击 `.cbz` 选择用 Yomu 打开时自动入库并直接进入阅读器。
- **验收标准**：模拟器系统「文件」App 点击 `.cbz` 选择 Yomu 打开，一步入库并展示第 1 页。
