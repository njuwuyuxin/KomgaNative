# 本地漫画导入与本机/Komga 双源并存实施任务书（Phase 1–2 执行蓝图）

> **架构决策依据**：
> - [ADR 0008：开屏免登录本地一等公民与多态数据源并存架构](adr/0008-local-first-multi-source-architecture.md)
> - [ADR 0009：本地漫画导入（`file_picker`）与纯 Dart 随机访问 CBZ/ZIP 引擎](adr/0009-local-comic-import-and-cbz-reader.md)
> **首期聚焦范围（已确认）**：采用 **方案 1A（开屏免登录本机一等公民 + 多态 Repository 本机/Komga 双源平级并存）**，Phase 1 聚焦 **`CBZ / ZIP` 压缩包 + 图片文件夹 + `ComicInfo.xml` 元数据解析**，以最小外部依赖（仅新增 `file_picker`）最快打通新用户留存闭环。
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
| **Batch L0：纯逻辑地基** | 归档引擎、数据源模型与本地目录表就绪（不改现有线上 UI 行为） | `LMA-01` ~ `LMA-03` | 约 4–5 天 | `komga_local_archive` 全边界单测毫秒级全绿；Drift `schemaVersion` 平滑升级单测全绿 |
| **Batch L1：Phase 1 MVP** | 破除开屏登录墙 + 本地 CBZ/ZIP/文件夹导入开读 + 本机/Komga 双源切换 | `LMA-04` ~ `LMA-08` | 约 5–6 天 | **可对外发版获客**：新装直达本机书库 10 秒导入开读；老用户升级无缝留在原 Komga 库且可随时切回本机 |
| **Batch L2：Phase 2 深度编目** | 本地系列合并/编辑/换封面/批量删除 + 本地收藏集与外部文件打开 | `LMA-09` ~ `LMA-12` | 约 5–6 天 | 本地管理体验对齐一线阅读器；本机源同样具备完整的收藏集、阅读列表与系统“用 Yomu 打开”闭环 |

---

## 1. 任务总表与依赖拓扑

| 任务 ID | 所属批次 | 任务名称 | 优先级 | 估时 | 前置依赖 | 状态 |
|---|---|---|---|---|---|---|
| `LMA-01` | Batch L0 | 新建纯 Dart 包 `komga_local_archive`（`RandomAccessByteSource`、魔数嗅探、ZIP/CBZ 按页读取、宽高嗅探、`ComicInfo.xml`、自然排序） | P0 | M | — | [ ] |
| `LMA-02` | Batch L0 | 领域层新增 `CatalogSource` / `SourceCapabilities` 与源持久化状态机（含老用户升级兼容） | P0 | S | — | [ ] |
| `LMA-03` | Batch L0 | 扩展用户库 `komga_native.sqlite` 新增本地目录表，打通 `'local://device'` 纯本地进度落盘 | P0 | M | `LMA-02` | [ ] |
| `LMA-04` | Batch L1 | 实现 `LocalLibraryRepository`、`LocalReaderRepository` 与 `LocalReadStatusRepository` | P0 | M | `LMA-01`, `LMA-03` | [ ] |
| `LMA-05` | Batch L1 | 接入 `file_picker` 与受管沙盒导入管线 `LocalComicImporter`（CBZ/ZIP + 图片文件夹） | P0 | M | `LMA-01`, `LMA-03` | [ ] |
| `LMA-06` | Batch L1 | 解除 `router.dart` 开屏登录墙，完成 5 大顶层 Provider 多态分发与跨源历史阅读 | P0 | M | `LMA-02`, `LMA-04` | [ ] |
| `LMA-07` | Batch L1 | 书架/正在读/详情/设置页接入源切换器与 `SourceCapabilities` 自适应 UI | P0 | M | `LMA-05`, `LMA-06` | [ ] |
| `LMA-08` | Batch L1 | Phase 1 国际化文案、多形态黄金图基线补齐与模拟器端到端验收 | P0 | S–M | `LMA-07` | [ ] |
| `LMA-09` | Batch L2 | 本地书籍/系列单选与多选批量删除（SQLite + 沙盒物理文件 + 存储统计联动） | P1 | M | `LMA-08` | [ ] |
| `LMA-10` | Batch L2 | 本地编目管理：编辑标题/卷号/方向/简介、散装单卷合并与拆分系列、重设封面 | P1 | M | `LMA-09` | [ ] |
| `LMA-11` | Batch L2 | 本地收藏集与阅读列表：扩展本地编目表并实现 `LocalCollectionsRepository` | P1 | M | `LMA-08` | [ ] |
| `LMA-12` | Batch L2 | 系统文件关联（Android Intent / iOS Document Types & Files.app 共享）：外部点击 `.cbz` 直接导入阅读 | P2 | S–M | `LMA-05`, `LMA-08` | [ ] |

---

## 2. 数据库表结构与模块拆分设计

### 2.1 `packages/komga_local_archive` 模块拆分（每文件 ≤ 250 行）

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

### 2.2 `komga_native.sqlite` 新增本地目录表（`ProgressDatabase` 升级 `schemaVersion`）

全部归入不可再生用户资产库 `komga_native.sqlite`（不放入可随时清空的 `komga_cache.sqlite`）：

1. **`LocalSeriesRows`（本地系列表）**
   - `id` (`TEXT PRIMARY KEY`)
   - `title` (`TEXT NOT NULL`)
   - `titleSort` (`TEXT NOT NULL`，小写规范化供排序)
   - `summary` (`TEXT NOT NULL DEFAULT ''`)
   - `publisher` (`TEXT NOT NULL DEFAULT ''`)
   - `authorsJson` (`TEXT NOT NULL DEFAULT '[]'`)
   - `tagsJson` (`TEXT NOT NULL DEFAULT '[]'`)
   - `readingDirection` (`TEXT NOT NULL DEFAULT 'unknown'`)
   - `coverBookId` (`TEXT NULL`，默认取首卷，支持指定某卷封面)
   - `customCoverPath` (`TEXT NULL`，用户自定义截取封面时的受管缩略图相对路径)
   - `metadataLocked` (`BOOLEAN NOT NULL DEFAULT 0`，手动编辑后锁定不被后续重扫覆盖)
   - `createdAt` (`DATETIME NOT NULL`)
   - `updatedAt` (`DATETIME NOT NULL`)

2. **`LocalBooksRows`（本地书籍/单卷表）**
   - `id` (`TEXT PRIMARY KEY`)
   - `seriesId` (`TEXT NOT NULL`，关联 `LocalSeriesRows.id`)
   - `name` (`TEXT NOT NULL`)
   - `number` (`TEXT NOT NULL DEFAULT ''`，展示卷号如 `"1"`、`"1.5"`)
   - `numberSort` (`REAL NOT NULL DEFAULT 0`，数值排序键)
   - `pagesCount` (`INTEGER NOT NULL`)
   - `sizeBytes` (`INTEGER NOT NULL`)
   - `storageKind` (`TEXT NOT NULL`，`'zip'` | `'folder'`)
   - `relativePath` (`TEXT NOT NULL`，相对于 `<ApplicationSupport>/local_comics/` 的路径，避免 iOS 沙盒容器 UUID 变化导致绝对路径失效)
   - `coverThumbPath` (`TEXT NULL`，导入时生成的 300px 封面相对路径)
   - `releaseDate` (`DATETIME NULL`)
   - `createdAt` (`DATETIME NOT NULL`)

3. **`LocalPagesRows`（本地书页索引与尺寸表）**
   - 复合主键 `{bookId, pageNumber}`（`pageNumber` 为 **1 基**，与 `PageInfo.number` 一致）
   - `entryName` (`TEXT NOT NULL`)
   - `localHeaderOffset` (`INTEGER NOT NULL DEFAULT 0`，ZIP 局部头偏移，打开阅读器直接跳转而无需重扫 EOCD)
   - `compressedSize` (`INTEGER NOT NULL DEFAULT 0`)
   - `uncompressedSize` (`INTEGER NOT NULL DEFAULT 0`)
   - `compressionMethod` (`INTEGER NOT NULL DEFAULT 0`)
   - `width` (`INTEGER NULL`)
   - `height` (`INTEGER NULL`)
   - `mediaType` (`TEXT NULL`)

4. **Phase 2 扩展表（`LMA-11`）**：`LocalCollectionsRows`（`id`, `name`, `ordered`, `seriesIdsJson`, `createdAt`, `updatedAt`）与 `LocalReadListsRows`（`id`, `name`, `summary`, `ordered`, `bookIdsJson`, `createdAt`, `updatedAt`）。

---

## 3. 逐项任务规格与验收标准

### 3.1 Batch L0：纯逻辑地基

#### `LMA-01` 新建纯 Dart 包 `packages/komga_local_archive`
- **目标**：在不触碰任何 Flutter / UI 代码的前提下，把 `.cbz/.zip` 随机访问解压、魔数识别、图片文件夹扫描、图片头宽高嗅探、`ComicInfo.xml` 解析与自然排序做成 100% 纯 Dart 可单测引擎。
- **改造内容**：
  1. 在根 `pubspec.yaml` 的 `workspace:` 注册 `packages/komga_local_archive`；
  2. 在 `tool/ci.dart` 的 `_purePackages` 与 `tool/ci_checks.dart` 的 `_productionRoots`、`pureForbidden` 列表中加入 `packages/komga_local_archive`；
  3. 实现 `RandomAccessByteSource`、`sniffContainerMagic`、`ZipDirectory`、`ZipPageReader`、`FolderPageReader`、`ImageDimensions`、`ComicInfoParser` 与 `naturalCompare`。
- **单测边界覆盖（必测）**：
  - 0 页空压缩包、纯非图片文件压缩包（返回 `ArchiveErrorKind.noImages`）；
  - 伪后缀文件（如扩展名为 `.cbr` 但魔数为 `PK\x03\x04` 的 ZIP 包正常解析；真 RAR/7z/PDF 返回明确的不支持容器类型枚举）；
  - 含 `__MACOSX/._01.jpg`、`.DS_Store`、`Thumbs.db` 的 macOS/Windows 打包文件（垃圾条目 100% 过滤）；
  - Stored (`method = 0`) 与 Deflate (`method = 8`) 混合条目随机跳页读取字节逐位一致；
  - 密码加密 ZIP（Bit 0 置位）与截断损坏文件（返回结构化 `ArchiveErrorKind`，零未捕获异常）；
  - 自然排序：`['1.jpg', '10.jpg', '2.jpg', 'p02.png', 'p100.png']` → `['1.jpg', '2.jpg', 'p02.png', '10.jpg', 'p100.png']`；
  - PNG / JPEG（含 EXIF APP1 段在前、`SOF0`/`SOF2` 在后的真实扫描图）/ WebP（VP8/VP8L/VP8X）宽高嗅探精确匹配；
  - `ComicInfo.xml`：带 UTF-8 BOM、XML 实体转义（`&amp;` / `&quot;`）、`Manga="YesAndRightToLeft"` 与缺失字段容错。
- **验收标准**：`dart test packages/komga_local_archive` 1 秒内全绿，`dart run tool/ci.dart check` 全绿。

---

#### `LMA-02` 领域层新增 `CatalogSource` / `SourceCapabilities` 与源状态机
- **目标**：建立独立于远程登录态的书库源模型，确保新用户默认免登录进本机、老用户升级无缝留在已连接的 Komga。
- **改造内容**：
  1. `packages/komga_domain` 新增 `src/catalog_source.dart`（定义 `kLocalScopeKey = 'local://device'`、`CatalogSource`、`LocalCatalogSource`、`KomgaCatalogSource`、`SourceCapabilities`）并导出；
  2. `AppSettings`（`apps/app/lib/src/data/app_settings.dart`）新增可选持久化字段 `activeSourceKey`（`toJson` / `fromJson` 向后兼容旧存档）；
  3. 新增 `apps/app/lib/src/providers/catalog_source_provider.dart`：
     - 管理当前激活的 `CatalogSource` 与全部可选源列表（始终包含排第一的 `LocalCatalogSource` + `serverListProvider` 中的全部已存服务器）；
     - 实现 ADR 0008 的冷启动恢复策略：无 `activeSourceKey` 时若 `ServerStore.load() != null` 自动选中该 Komga 服务器（保护老用户升级体验），否则选中 `LocalCatalogSource`；
     - 连接新 Komga 服务器成功后自动切换至该新服务器；删除当前活动 Komga 服务器时自动平滑回退至 `LocalCatalogSource`。
- **验收标准**：
  - 单测覆盖 4 条核心状态流转：① 全新空存档启动 → `LocalCatalogSource`；② 含旧版已登录 `StoredServer` 但无 `activeSourceKey` 的存档启动 → `KomgaCatalogSource`；③ 在 Komga 源手动切到本机源并重启 → 保持 `LocalCatalogSource`（且原服务器凭据不丢失）；④ 删除当前活动服务器 → 自动回退 `LocalCatalogSource`。

---

#### `LMA-03` 扩展 `komga_native.sqlite` 本地目录表与纯本地进度落盘
- **目标**：在用户数据库中落地 `LocalSeriesRows` / `LocalBooksRows` / `LocalPagesRows` 及响应式查询流，并让 `ProgressSyncService` 原生兼容 `'local://device'`。
- **改造内容**：
  1. 新增 `apps/app/lib/src/data/local/local_tables.dart` 与 `local_catalog_dao.dart`（拆独立 DAO 文件守住 350 行红线），接入 `ProgressDatabase` 并递增 `schemaVersion`（补齐 `onUpgrade` `m.createTable`）；
  2. 实现分页查询、关键词搜索（匹配系列名/书名/作者/标签）、全部 `SeriesSort` 排序、`SeriesReadStatus` 阅读状态筛选（与同库 `LocalProgress(scope: 'local://device')` 聚合计算 `booksReadCount`）以及本地 `ondeck`（在读书优先 + 同系列下一卷未读兜底）；
  3. 调整 `ProgressSyncService`：当 `scope == kLocalScopeKey` 时，`save()` 直接落盘最新页码与 `completed`（`pendingSeq = null`），跳过远程 HTTP 冲洗循环。
- **验收标准**：
  - 数据库迁移单测：从当前线上 `ProgressDatabase` 升级后，既有服务器进度、置顶与阅读历史 100% 完好，新增三张本地表正常读写；
  - 本地查询单测：本地系列在翻页阅读、标为已读/未读后，`booksReadCount`、`SeriesReadStatus` 与本地 `ondeck` 返回结果完全准确。

---

### 3.2 Batch L1：Phase 1 MVP（破除登录墙 + 导入开读闭环）

#### `LMA-04` 实现本地 `LibraryRepository` / `ReaderRepository` / `ReadStatusRepository`
- **目标**：将本地 SQLite 目录与 `komga_local_archive` 封装成标准仓库接口实现，无缝对接现有书架与阅读器。
- **改造内容**：
  1. `LocalLibraryRepository`：实现 `libraries()`、`series()`、`seriesById()`、`book()`、`searchBooks()`、`books()`、`ondeck()`、`seriesCover()`、`bookCover()`（磁盘 300px 缩略图 + 内存 `ByteLruCache`）；
  2. `LocalReaderRepository`：实现 `book()`、`pages()`（从 `LocalPagesRows` 秒返含精确宽高的 `PageInfo` 列表）、`pageImage()`（经 `ZipPageReader` / `FolderPageReader` 单页读取 + 64 页内存 `ByteLruCache` + 同页并发请求合并 `_inFlight`）、`pageThumbnail()`；
  3. `LocalReadStatusRepository`：实现 `setSeriesRead()` 与 `setBookRead()`，直接更新 `LocalProgress(scope: 'local://device')` 并触发书架原地刷新。
- **验收标准**：仓库契约单测覆盖空库、多卷系列、翻页缓存合并、物理文件缺失时映射为可读 `ShelfFailure`（零未处理 `FileSystemException`）。

---

#### `LMA-05` 接入 `file_picker` 与受管沙盒导入管线 `LocalComicImporter`
- **目标**：支持一键选择单个或多个 `.cbz` / `.zip` 文件或整个漫画图片文件夹，流式入库并生成封面缩略图。
- **改造内容**：
  1. 在 `apps/app/pubspec.yaml` 引入 `file_picker`（关联 ADR 0009）；定义抽象 `ComicFilePicker` 接口与默认插件实现；
  2. 实现 `LocalComicImporter` + Riverpod 状态控制器 `LocalImportController`（暴露导入进度：`totalFiles`、`completedFiles`、`currentFileName`、`failures`）：
     - 流式分块拷贝文件至 `<ApplicationSupport>/local_comics/<bookId>/` 受管相对路径；
     - 调用 `komga_local_archive` 校验归档、嗅探每页宽高、解析 `ComicInfo.xml`（无 XML 时用文件名/父目录启发式提取系列名与卷号）；
     - 使用 `dart:ui` `instantiateImageCodec(targetWidth: 360)` 解码封面页（若为 `w/h > 1.35` 连体宽封皮，支持按阅读方向裁半面正封）落盘；
     - 事务写入 `LocalSeriesRows`（同名系列自动归并追加分卷）、`LocalBooksRows` 与 `LocalPagesRows`；
     - 导入完成后立即清理 `file_picker` 系统临时目录缓存副本，防止双倍占用用户存储。
- **验收标准**：
  - 导入单测：导入同一系列的 `Vol.1.cbz` 与 `Vol.2.cbz` 自动归入同一个 2 本书的系列；导入含 1 个正常 `.cbz` + 1 个加密 `.zip` 时，正常书成功入库且返回 1 条加密失败摘要，沙盒无残留半截文件。

---

#### `LMA-06` 解除 `router.dart` 开屏登录墙与顶层 Provider 多态接线
- **目标**：打通全应用免登录启动与本机/Komga 毫秒级热切换。
- **改造内容**：
  1. 修改 `apps/app/lib/src/router.dart` 与 `router_provider.dart`：
     - 仅在初始化恢复中停留 `/splash`；恢复完成后无论是否配置过 Komga 服务器，均放行进入主壳 `/reading`；
     - `/connect` 改为普通可导航路由（顶部增加返回按钮，随时可退回本机书库；连接成功后自动切源并回到主壳）；
  2. 修改 `library_providers.dart`、`reader_providers.dart`、`collections_providers.dart`、`pinned_series_provider.dart`、`progress_providers.dart`：
     - `activeServerKeyProvider` 返回当前 `CatalogSource.scopeKey`（本机为 `'local://device'`）；
     - 各 Repository Provider 根据当前 `CatalogSource` 动态分发至 `Local*Repository` 或 `Komga*Repository`；
     - 移除 `SettingsLibrarySection` 中“未连接服务器时隐藏书架设置分组”的限制，使网格/封面大小设置对本机书库同样生效；
  3. 跨源历史跳转：`HistoryScreen` 点击历史记录时，若记录 `scope` 与当前激活源不同且目标源存在，自动切换激活源后打开阅读器。
- **验收标准**：
  - 路由与多源隔离集成测试：全新安装冷启动直达主界面 → 导入本地书翻到第 5 页 → 连接测试 Komga 服务器（切到服务器书架）→ 切回「本机书库」（本地书仍在第 5 页）→ 退出/删除服务器 → 本地书与阅读统计毫发无损。

---

#### `LMA-07` 书架 / 正在读 / 系列详情 / 设置页源切换与能力自适应 UI
- **目标**：让界面对纯本地新用户零违和感，同时让双修用户在「本机」与「Komga」间切换自如。
- **改造内容（严格使用 `komga_design_system` 既有玻璃组件）**：
  1. **源切换与导入动作**：
     - 书架顶栏（`ShelfHeaderBar`）与平板侧栏（`ShelfSideRail`）接入轻量源切换菜单胶囊（展示当前源名称，下拉可秒切「本机书库 / 已存 Komga 服务器 / + 连接新服务器」）；`capabilities.canImportLocalFiles` 为真时展示「导入（`+`）」玻璃按钮（含「导入 CBZ/ZIP 文件」「导入漫画文件夹」）；
  2. **零门槛首屏空态（Onboarding Empty State）**：
     - 本机书库为空时，`ReadingNowScreen` 与 `LibraryScreen` 展示清爽引导卡：主按钮「导入本地漫画」，次级按钮「连接 Komga 服务器」；导入进行中显示非模态进度胶囊；
  3. **按 `SourceCapabilities` 收敛无关控件**：
     - `!capabilities.showsNetworkOfflineBanner` 时不渲染 `OfflineOverlay`；
     - `!capabilities.canDownloadOffline` 时隐藏书行与系列详情的离线下载按钮及设置页下载策略组；
  4. **设置页升级**：
     - 「服务器」分组升级为「书库来源」，首行常驻「本机书库」，下方列出已保存的 Komga 服务器与「添加 Komga 服务器」；
     - 「存储」分组新增「本地漫画」占用统计行（已导入本数与沙盒文件总体积）。
- **验收标准**：Widget 测试逐一断言本机源与 Komga 源下导入按钮、下载按钮、离线横幅、书架设置组、存储统计行的显隐切换与交互回调。

---

#### `LMA-08` Phase 1 国际化、黄金图基线与模拟器端到端交付验证
- **目标**：补齐中英双语 ARB、更新并新增 Windows 黄金图基线，在 Android 模拟器上实操真 `.cbz` 导入阅读。
- **改造内容**：
  1. 补齐 `app_en.arb` 与 `app_zh.arb` 中全部本地书库、导入进度、错误提示与源切换文案；
  2. 更新受开屏/顶栏微调影响的既有黄金图，新增本机空态引导与本机书架黄金图（手机 `light`、平板 `dark`、墨水屏 `eink`），逐张用 `read_image` 检视排版与 1.3× 字号；
  3. 更新 `AGENTS.md`「当前阶段」架构说明。
- **验收标准**：
  - `dart run tool/ci.dart check` 全绿；
  - `dart run tool/ci.dart install` 装 Release 包到模拟器，零服务器配置下直接导入测试 `.cbz` 漫画（含 RTL `ComicInfo.xml` 与双页宽图），实测封面、双页卷页翻页、退出重进页码恢复、阅读历史与热力图全链路通过。

---

### 3.3 Batch L2：Phase 2 本地书库深度编目管理

#### `LMA-09` 本地书籍与系列删除（单删 + 批量多选删除）
- **改造内容**：在 `LocalCatalogDao` 实现事务性删除书籍/系列记录及关联 `LocalProgress` / `PinnedSeriesRows`，并清理沙盒 `local_comics/<bookId>` 与封面缩略图；书架多选批量栏与系列详情菜单在 `capabilities.canMutateCatalog` 为真时提供「从本机删除」（带空间释放量提示与二次确认）。
- **验收标准**：单删、删空整个系列、多选批量删除后，书架即时更新、沙盒零孤儿文件残留、存储统计实时扣减。

#### `LMA-10` 本地系列编目：元数据编辑、散装单卷合并/拆分与自定义封面
- **改造内容**：
  1. 新增 `LocalMetadataSheet`：修改系列标题、简介、作者、标签、阅读方向（LTR / RTL / 条漫）及单本书标题与卷号 `number`（置 `metadataLocked = true`）；
  2. 书架多选支持将多个散装单卷「合并为一个系列」，系列详情书行支持「拆出为独立系列」；
  3. 阅读器菜单与编辑面板支持「将当前页设为书籍/系列封面」。
- **验收标准**：导入 3 个散装 `.cbz` 合并为同一系列并设卷号 `1, 2, 3` 与 `RTL` 方向，阅读器右翻与书末「下一本」连续跳转完全准确。

#### `LMA-11` 本地收藏集与阅读列表（`LocalCollectionsRepository`）
- **改造内容**：`ProgressDatabase` 新增 `LocalCollectionsRows` 与 `LocalReadListsRows`，实现完整 `LocalCollectionsRepository` 并开启 `LocalCatalogSource` 的 `supportsCollections = true`，使本机源在「收藏」Tab、封面拼贴、新建/编辑与跨系列阅读列表上与 Komga 源体验一致。
- **验收标准**：在本机源创建收藏集与跨系列阅读列表，重启后持久化保留，且切到 Komga 源时互不混杂。

#### `LMA-12` 系统级外部文件打开导入与 iOS「文件」App 共享目录
- **改造内容**：Android `AndroidManifest.xml` 注册 `.cbz` / `.zip` 的 `ACTION_VIEW` 与 `ACTION_SEND`；iOS `Info.plist` 配置 `CFBundleDocumentTypes` 与 `UIFileSharingEnabled = true`；外部点击 `.cbz` 选择用 Yomu 打开时自动入库并直达阅读器。
- **验收标准**：在模拟器系统「文件」App 中点击 `.cbz` 选择 Yomu 打开，自动完成入库并进入阅读器第 1 页。

---

## 4. 后续按需扩展插槽（Phase 3+，不阻塞首期交付）

完成 `LMA-01` ~ `LMA-12` 后，基于已抽象的 `RandomAccessByteSource` 与 `CatalogSource` 接口，后续可按真实用户反馈以独立 ADR 增量接入：
- **进阶容器与协议**：固定版式纯图 `EPUB`、系统原生 `PDF` 按需光栅化（Android `PdfRenderer` / iOS `PDFKit`）、局域网内置 HTTP Wi-Fi 拖拽传书（`dart:io` `HttpServer` 零依赖）、Android SAF 外部大目录零拷贝原位挂载、以及通用只读 OPDS / WebDAV 源；
- **本地扫图阅读增强**：竖屏宽幅合扫页自动切分（Split Wide Pages + 临时合页查看）、墨水屏去底灰漂白对比度滤镜、超长条漫分片纹理渲染。
