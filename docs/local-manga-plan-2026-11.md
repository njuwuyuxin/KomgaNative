# 本地漫画导入与多源双栖架构实施任务书（2026-11 定稿）

> **架构决策依据**：
> - [ADR 0008：「编目按源分组 + 阅读跨源无感」的多源双栖架构（面向 Local / Komga / 未来 Kavita & OPDS）](adr/0008-local-first-multi-source-architecture.md)
> - [ADR 0009：本地漫画导入（`file_picker`）与纯 Dart 随机访问 CBZ/ZIP 引擎](adr/0009-local-comic-import-and-cbz-reader.md)
> **核心产品与架构边界（已确认定稿）**：
> 1. **管理归各家（零同步冲突、易扩展 Kavita/OPDS）**：未登录任何服务器时自动隐藏分组切换栏，呈现纯粹完整的本地书架与**本地收藏集/阅读列表**；登录服务器后，书架、搜索与收藏集按源清晰分组（`[本机]` / `[☁ Komga]` / 未来 `[☁ Kavita]`），严格同源归属，彻底杜绝异构分页乱序与跨源收藏集同步分裂。
> 2. **阅读归一处（高频续读与阅读器完全无感）**：首页「正在读（`Reading Now`）」、阅读历史、统计热力图跨源汇聚（云端项仅在标题旁标一枚 `AppSizes.iconXs` 的低调小云标 `Icons.cloud_outlined`）；点击任意书籍均通过三段式 `sourceKey` 直达同一套 `ReaderScreen`，阅读体验 100% 一致，进度按所属 `sourceKey` 物理绝缘回写。
> 3. **首期格式聚焦**：Phase 1 聚焦 **`CBZ / ZIP` 压缩包 + 图片文件夹 + `ComicInfo.xml` 解析**，全仓仅新增 `file_picker` 一个第三方插件依赖。
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
| **Batch L0：纯逻辑与本地全功能仓库** | 纯 Dart 归档引擎、`sourceKey` 多源注册模型、本地书目+本地收藏集 SQLite 表与四大 `Local*Repository` | `LMA-01` ~ `LMA-04` | 约 5–6 天 | `komga_local_archive` 全边界单测全绿；`Local*Repository`（含本地收藏集/阅读列表）离线契约单测全绿 |
| **Batch L1：多源注册路由与 MVP 闭环** | `SourceRegistry` 多源路由、解除开屏登录墙、跨源「正在读」汇聚、书架单源隐形/多源分组、`file_picker` 导入 | `LMA-05` ~ `LMA-08` | 约 5–6 天 | **可对外发版获客**：未登录享完整本地书架与收藏集；登录 Komga 后分组清晰、首页续读无感带微云标、零同步冲突 |
| **Batch L2：本地编目精修与外部打开** | 本地书籍/系列物理删除、散装单卷合并/拆分与元数据编辑、自定义封面、系统外部点击 `.cbz` 直接用 Yomu 打开 | `LMA-09` ~ `LMA-12` | 约 4–5 天 | 本地散装漫画整理体验对齐 Panels；支持从系统文件/聊天/网盘一键打开入库 |

---

## 1. 任务总表与依赖拓扑

| 任务 ID | 所属批次 | 任务名称 | 优先级 | 估时 | 前置依赖 | 状态 |
|---|---|---|---|---|---|---|
| `LMA-01` | Batch L0 | 新建纯 Dart 包 `komga_local_archive`（`RandomAccessByteSource`、魔数嗅探、ZIP/CBZ 按页读取、宽高嗅探、`ComicInfo.xml`、自然排序） | P0 | M | — | [ ] |
| `LMA-02` | Batch L0 | 领域层新增 `ContentSource` / `SourceCapabilities` 与实体 `sourceKey` 标识（面向未来 Kavita/OPDS 预留） | P0 | S | — | [ ] |
| `LMA-03` | Batch L0 | 扩展用户库 `komga_native.sqlite` 新增本地书目表与本地收藏集/阅读列表表，打通本地进度直写 | P0 | M | `LMA-02` | [ ] |
| `LMA-04` | Batch L0 | 完整实现本地四大仓库：`LocalLibrary` / `LocalReader` / `LocalCollections` / `LocalReadStatusRepository` | P0 | M | `LMA-01`, `LMA-03` | [ ] |
| `LMA-05` | Batch L1 | 实现 `SourceRegistry` 多源插件表、活动源状态机（含老用户升级兼容）与跨源「正在读 / 历史」汇聚器 | P0 | M | `LMA-04` | [ ] |
| `LMA-06` | Batch L1 | 接入 `file_picker` 与受管沙盒导入管线 `LocalComicImporter`（CBZ/ZIP + 图片文件夹 + 首图封面提取） | P0 | M | `LMA-01`, `LMA-03` | [ ] |
| `LMA-07` | Batch L1 | 解除 `router.dart` 登录墙、单源隐形/多源分组胶囊、跨源卡片低调小云标与「云端同步（Komga）」设置升级 | P0 | M | `LMA-05`, `LMA-06` | [ ] |
| `LMA-08` | Batch L1 | MVP 中英双语文案、多形态黄金图基线补齐与模拟器端到端验收 | P0 | S–M | `LMA-07` | [ ] |
| `LMA-09` | Batch L2 | 本地书籍/系列单选与多选批量删除（SQLite + 沙盒物理文件 + 存储统计联动） | P1 | M | `LMA-08` | [ ] |
| `LMA-10` | Batch L2 | 本地编目管理：编辑标题/卷号/方向/简介、散装单卷合并与拆分系列 | P1 | M | `LMA-09` | [ ] |
| `LMA-11` | Batch L2 | 本地自定义封面（阅读器「将当前页设为封面」与相册选图） | P2 | S–M | `LMA-10` | [ ] |
| `LMA-12` | Batch L2 | 系统文件关联（Android Intent / iOS Document Types & Files.app 共享）：外部点击 `.cbz` 直接导入阅读 | P1 | S–M | `LMA-06`, `LMA-08` | [ ] |

---

## 2. 核心架构与可扩展插件槽设计

### 2.1 `SourceRegistry` 多源插件架构（为后续 Kavita / OPDS 预留干净插槽）

```
                   ┌─── ActiveSourceProvider (书架 / 收藏集 / 搜索 当前选中的源分组)
                   │
UI / Controllers ──┼─── CrossSourceReadingNowProvider (首页「正在读」汇聚各源 Top N 活跃书)
                   │
                   └─── ScopedReader / History (按实体携带的 sourceKey 精确寻址对应源仓库)
                                  │
                                  ▼
                    SourceRegistry (Map<String sourceKey, SourceBundle>)
                     ├── 'local://device'       ──► LocalSourceBundle (常驻内置，零网络依赖)
                     ├── '<komgaBaseUrl>'       ──► KomgaSourceBundle (原生 REST + Outbox 对账)
                     └── 'kavita|<baseUrl>' (预留) ► KavitaSourceBundle (未来独立插件包零侵入挂载)
```

每个 `SourceBundle` 封装该源同构的一套：
- `ContentSource descriptor`（含 `sourceKey`、`displayName`、`SourceKind`、`SourceCapabilities`）；
- `LibraryRepository library`；
- `ReaderRepository reader`；
- `CollectionsRepository collections`；
- `ReadStatusRepository readStatus`。

**为什么这套边界长期维护最轻松？**
1. **书架与收藏集零交叉污染**：`libraryRepositoryProvider` 与 `collectionsRepositoryProvider` 直接返回 `registry.bundleFor(activeSource).library / .collections`。本机分组只管本地 SQLite，Komga 分组只管该台 Komga，未来 Kavita 分组只管该台 Kavita——**不需要写任何跨源分页归并器，也不可能把本地书误发给远程收藏集 API**。
2. **阅读器与首页续读无感直通**：`Series` 与 `Book` 均携带 `sourceKey`。当用户在首页「正在读」或「阅读历史」点击一本非当前书架分组的书时，`ReaderArgs`（或路由查询参数 `?source=...`）将 `sourceKey` 传入 `ReaderScreen`，直接从 `SourceRegistry` 取出对应源的 `ReaderRepository` 打开阅读并向该源专属进度队列回写，无需切分组、零同步冲突。

### 2.2 `packages/komga_local_archive` 模块拆分（每文件 ≤ 250 行）

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

### 3.1 Batch L0：纯逻辑与本地全功能仓库底座

#### `LMA-01` 新建纯 Dart 包 `packages/komga_local_archive`
- **目标**：把 `.cbz/.zip` 随机访问按页解压、魔数识别、图片文件夹扫描、图片头极速宽高嗅探、`ComicInfo.xml` 解析与自然排序做成零外部依赖的 100% 纯 Dart 引擎。
- **改造内容**：
  1. 在根 `pubspec.yaml` 的 `workspace:` 注册 `packages/komga_local_archive`，并加入 `tool/ci.dart`（`_purePackages`）与 `tool/ci_checks.dart`（`_productionRoots` + `pureForbidden`）；
  2. 实现 `RandomAccessByteSource`、`sniffContainerMagic`、`ZipDirectory`、`ZipPageReader`、`FolderPageReader`、`ImageDimensions`、`ComicInfoParser` 与 `naturalCompare`。
- **单测边界覆盖**：0 页空包、纯非图片包、伪后缀（`.cbr` 实为 ZIP 魔数）、`__MACOSX/` 与 `.DS_Store` 垃圾过滤、Stored/Deflate 随机跳页一致性、加密与损坏包枚举错误、自然排序（`2.jpg < 10.jpg`）、PNG/JPEG(含 EXIF)/WebP 宽高嗅探、`ComicInfo.xml`（BOM、转义、`Manga="YesAndRightToLeft"`）。
- **验收标准**：`dart test packages/komga_local_archive` 1 秒内全绿，`dart run tool/ci.dart check` 全绿。

---

#### `LMA-02` 领域层新增 `ContentSource` / `SourceCapabilities` 与实体 `sourceKey`
- **目标**：建立面向多服务器协议（Local / Komga / 未来 Kavita & OPDS）的可扩展源标识与能力模型。
- **改造内容**：
  1. `packages/komga_domain` 新增 `src/content_source.dart`：定义 `kLocalSourceKey = 'local://device'`、`SourceKind { local, komga, kavita, opds }`、`ContentSource` 与 `SourceCapabilities`（`canImportLocalFiles`、`canMutateCatalog`、`canDownloadOffline`、`showsNetworkOfflineBanner`、`supportsCollections`）；
  2. 在 `Series`、`Book`、`KomgaCollection`、`ReadList` 增加可选属性 `this.sourceKey = kLocalSourceKey` 及计算属性 `bool get isCloud => sourceKey != kLocalSourceKey`（默认本地值保证全部既有单测与 99 张黄金图零意外变化）；
  3. 在 `KomgaLibraryRepository`、`KomgaReaderRepository`、`KomgaCollectionsRepository` 中将产出的领域实体注入当前服务器的 `sourceKey`（`session.address.baseUrl`）。
- **验收标准**：`dart test packages/komga_domain` 与 `apps/app` 存量测试 100% 通过。

---

#### `LMA-03` 扩展 `komga_native.sqlite` 新增本地书目表与本地收藏集表
- **目标**：在用户资产库 `ProgressDatabase` 中一次性落地本地系列/书籍/页索引与**本地收藏集/阅读列表**，并打通本地阅读进度直写。
- **改造内容**：
  1. 新增 `local_tables.dart`：`LocalSeriesRows`、`LocalBooksRows`（存相对于 `<ApplicationSupport>/local_comics/` 的 `relativePath`，规避 iOS 容器 UUID 变化失效）、`LocalPagesRows`、`LocalCollectionsRows`、`LocalReadListsRows`；
  2. 拆分为 `local_catalog_dao.dart`（系列/书籍查询、搜索、全部 `SeriesSort`、`SeriesReadStatus`、本地 `ondeck` 推导）与 `local_curation_dao.dart`（本地收藏集与阅读列表 CRUD），升级 `ProgressDatabase.schemaVersion` 并补无损 `onUpgrade`；
  3. 扩展 `ProgressSyncService`：支持按显式传入的 `scope`（`sourceKey`）保存进度；当 `scope == kLocalSourceKey` 时直接以 `pendingSeq = null` 落盘本地 `LocalProgress`，绝不入远程上传队列。
- **验收标准**：旧版数据库升级迁移单测全绿；本地书目排序筛选、`ondeck` 下一卷推导与本地收藏集 CRUD 单测全绿。

---

#### `LMA-04` 完整实现本地四大仓库（`LocalLibrary` / `Reader` / `Collections` / `ReadStatus`）
- **目标**：使未登录状态下的「本机」源拥有与 Komga 100% 对等的四大抽象仓库实现。
- **改造内容**：
  1. `LocalLibraryRepository`：本地分页、搜索、`ondeck`、磁盘 360px 缩略图读取 + 内存 `ByteLruCache`；
  2. `LocalReaderRepository`：从 `LocalPagesRows` 秒返含精确宽高的 `PageInfo`，经 `ZipPageReader` / `FolderPageReader` 单页读取 + 64 页内存 `ByteLruCache` + `_inFlight` 并发合并；
  3. `LocalCollectionsRepository`：完整实现收藏集与阅读列表的新建、改名、成员增删、排序与删除；
  4. `LocalReadStatusRepository`：本地整系列与单本书标记已读/未读。
- **验收标准**：四大本地仓库契约测试全绿，文件缺失/损坏统一转换为 `ShelfFailure`。

---

### 3.2 Batch L1：多源注册路由与 MVP 交付闭环

#### `LMA-05` 实现 `SourceRegistry`、活动源状态机与跨源「正在读 / 历史」汇聚
- **目标**：实现“编目按活动源严格隔离，正在读与阅读器按 `sourceKey` 跨源直达”。
- **改造内容**：
  1. 实现 `sourceRegistryProvider`：常驻注册 `'local://device'` 本地 `SourceBundle`，并为已连接的 `StoredServer` 动态挂载 `KomgaSourceBundle`（支持同时保留后台已存服务器的按需会话读取或当前活动连接池）；
  2. 实现 `activeSourceProvider`（持久化 `AppSettings.activeSourceKey`）：
     - 首次升级兼容：无 `activeSourceKey` 时若 `ServerStore.load() != null` 默认选中该 Komga 源（保护老用户升级不跳空书架），否则默认选中 `LocalSource`；
     - 新增登录服务器后自动切到该新服务器分组；删除当前活动服务器后自动平滑回退到 `LocalSource`；
  3. 实现跨源 `readingNowOndeckProvider` 与跨源 `readingSessionsProvider`：
     - 「正在读」并发拉取本机 `LocalLibraryRepository.ondeck()` 与当前已连远程源 `ondeck()`（远程断网报错时静默忽略远程错误，保留本机与缓存项），按最近阅读时间排序输出；
     - 阅读器路由 `/reader/:bookId` 与系列详情 `/series/:seriesId` 支持携带 `sourceKey`（通过 `ReaderArgs` / `SeriesDetailArgs` 及查询参数 `?source=` 兜底深链与冷启动），使从首页「正在读」或「阅读历史」点击任何源的卡片都能直接打开对应源仓库阅读，无需先切书架分组！
- **验收标准**：多源隔离与跨源续读单测：在本机读《漫画 A》到第 5 页，切到 Komga 读《漫画 B》到第 8 页 → 首页「正在读」同时展示 B（带云标）与 A → 当前停留在 Komga 书架时去首页点《漫画 A》直接打开本地阅读器且进度准确回写本机，零跨源污染。

---

#### `LMA-06` 接入 `file_picker` 与受管沙盒导入管线 `LocalComicImporter`
- **目标**：支持多选导入 `.cbz` / `.zip` 压缩包或漫画图片文件夹，自动提取元数据与封面。
- **改造内容**：
  1. `apps/app/pubspec.yaml` 引入 `file_picker`（关联 ADR 0009），封装抽象 `ComicFilePicker`；
  2. 实现 `LocalComicImporter` 与 `LocalImportController`：流式分块拷入 `<ApplicationSupport>/local_comics/<bookId>/` → 嗅探每页宽高 → 解析 `ComicInfo.xml`（无 XML 时按目录/文件名启发式归并同名系列与卷号）→ 生成 360px 封面缩略图（连体宽封支持自动裁正封）→ 事务入库并立即清理选择器临时缓存。
- **验收标准**：单测覆盖同名多卷自动归并、正常包与加密/损坏包混合导入容错、临时文件零残留。

---

#### `LMA-07` 解除开屏登录墙、单源隐形/多源分组栏与跨源低调小云标
- **目标**：以最克制的视觉改动落地完整双栖体验。
- **改造内容**：
  1. **解除登录墙**：`router.dart` 移除 `SessionDisconnected -> /connect` 强制拦截，冷启动直达 `/reading`；`/connect` 顶栏增加返回按钮；移除 `SettingsLibrarySection` 在未连服时的隐藏限制；
  2. **单源隐形 / 多源分组导航**：
     - 当系统中仅有「本机」单一源时，书架与收藏页**不渲染源分组切换条**，保持极致干净；
     - 当已添加 ≥ 1 台远程服务器时，书架顶栏下方（窄屏玻璃胶囊条）与平板左侧栏 `ShelfSideRail` 顶部展示清晰的源分组：`[ 本机 ]`、`[ ☁ 服务器名 ]`；切到「本机」时顶栏右侧展示「导入漫画（`+`）」玻璃按钮，切到远程源时展示该服子库筛选与离线状态；
  3. **克制的云端微标與源能力显隐**：
     - 在跨源汇聚视图（首页「正在读」继续卡、最近阅读行、阅读历史行）以及云端系列卡片标题旁，对 `isCloud == true` 渲染 `AppSizes.iconXs`（16dp）、`colorScheme.onSurfaceVariant` 的 `Icons.cloud_outlined` 小图标；
     - 按当前分组 `SourceCapabilities` 控制详情页离线下载按钮与 `OfflineOverlay` 断网胶囊（本机源永不显示下载按钮与断网横幅）；
  4. **设置页「云端同步增强」升级**：将原「服务器」组升级为 **「云端书库与同步（Komga）」**（传达“登录即可流式浏览 NAS 书库并跨设备同步进度与收藏集”），并在「存储」组新增「本地漫画」空间占用行。
- **验收标准**：Widget 测试验证：① 纯本地无服务器时无分组切换条、全功能畅通；② 添加服务器后分组胶囊出现、切换丝滑；③ 首页云端在读书显示小云标且点击直达阅读器。

---

#### `LMA-08` MVP 双语文案、黄金图基线与模拟器端到端验收
- **改造内容**：补齐中英 ARB 文案；更新并新增黄金图基线（纯本地空态引导、纯本地书架、含多源分组栏的书架、跨源「正在读」云微标卡片，覆盖手机 `light` / 平板 `dark` / 墨水屏 `eink`）并用 `read_image` 逐张核查；更新 `AGENTS.md`。
- **验收标准**：`dart run tool/ci.dart check` 全绿；`dart run tool/ci.dart install` 模拟器实操验证纯本地导入阅读/收藏集闭环，以及登录 Komga 后分组切换与首页跨源续读闭环。

---

### 3.3 Batch L2：本地编目精修与外部文件打开

#### `LMA-09` 本地书籍与系列删除（单删 + 批量多选删除）
- **改造内容**：在「本机」分组下，单本菜单、系列菜单与书架/详情多选批量栏开放「从本机删除」（带释放空间提示与二次确认），事务清理 SQLite 记录、进度、本地收藏集引用及沙盒物理文件。

#### `LMA-10` 本地编目编辑与散装单卷合并/拆分系列
- **改造内容**：在「本机」分组开放「编辑信息」面板（改标题、卷号、作者、简介、阅读方向 LTR/RTL/条漫，置 `metadataLocked = true`），书架多选支持「合并为一个系列」，书行支持「拆出为独立系列」。

#### `LMA-11` 本地自定义封面（阅读器设当前页为封面 + 文件选图）
- **改造内容**：「本机」书籍在阅读器 `⋯` 菜单支持「将当前页设为封面」，在编辑面板支持选图换封面。

#### `LMA-12` 系统级外部文件打开导入（Open With & iOS Files.app 共享目录）
- **改造内容**：注册 Android `ACTION_VIEW` / `ACTION_SEND` 与 iOS `CFBundleDocumentTypes` + `UIFileSharingEnabled = true`；外部点击 `.cbz` 选 Yomu 打开时自动入库至「本机」源并直接打开阅读器。
