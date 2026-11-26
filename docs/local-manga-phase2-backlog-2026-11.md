# 本地漫画与阅读器增强：二期需求任务书（2026-11）

> **调研依据**：[local-comic-competitor-research-2026-11.md](local-comic-competitor-research-2026-11.md)
> **一期已交付基线**：`LMA-01` ~ `LMA-12`（见 [local-manga-plan-2026-11.md](local-manga-plan-2026-11.md)），已完成本地优先免登录、`SourceRegistry` 多源双栖、纯 Dart `CBZ/ZIP` 随机读取、图片文件夹导入、`ComicInfo.xml` 核心元数据、宽封面自动裁半、本地收藏集/阅读列表、单删/批量删、系列合并/拆分/编辑、当前页设封面与外部文件打开。
> **本文档定位**：剔除一期已完成项后的增量待开发清单（`LMB-01` ~ `LMB-19`），按投入产出比分为 Phase A – D 四阶段推进。
> **工程红线（遵循 `AGENTS.md`）**：非生成生产 `.dart` 文件 ≤ 350 行、单类 ≤ 300 行、零 `dynamic`、零裸 `catch (_)`；纯 Dart 包不引入 Flutter/Dio/Drift；每项完成即跑 `dart run tool/ci.dart check` 并推送远端触发 CI，阶段收口执行全量回归与模拟器实操验证。

---

## 0. 阶段总览与任务总表

| 阶段 | 任务 ID | 需求名称 | 优先级 | 估时 | 状态 |
|---|---|---|---|---|---|
| **Phase A** | `LMB-01` | 宽幅合扫页自动切分（Split Wide Pages，RTL/LTR）+ 竖屏「临时合页」查看跨页 | P1 | M-L | [x] |
| **Phase A** | `LMB-02` | 超高条漫长图（> 4096px）自动分片解码渲染（防 GPU 纹理越界与 OOM） | P1 | M | [x] |
| **Phase A** | `LMB-03` | 漫画图像增强滤镜（对比度 / 去底灰漂白 White Threshold / 去黄 / 灰阶，含墨水屏预设） | P1 | M | [x] |
| **Phase A** | `LMB-04` | 漫画型 `EPUB`（固定版式 / 纯图）支持：`OPF` 元数据、`RTL` 方向、内嵌目录与纯文字拦截 | P1 | M | [ ] |
| **Phase A** | `LMB-05` | 单本书内部多章节目录（EPUB TOC / 子目录 / `ComicInfo` 书签）+ 通用页级书签 | P1 | M | [ ] |
| **Phase A** | `LMB-06` | 老压缩包文件名 `Shift-JIS / GBK` 真转码 + `CBT/TAR` + 嵌套合集包自动拆包 | P1 | M | [ ] |
| **Phase B** | `LMB-07` | 内置局域网 HTTP Wi-Fi 传书服务（浏览器拖拽文件/文件夹 + 进度 + 可选 PIN） | P1 | M-L | [ ] |
| **Phase B** | `LMB-08` | 外部目录原位挂载：Android SAF 持久化树 & iOS Security-Scoped Bookmark（含 `.nomedia` & iCloud 感知） | P1 | L | [ ] |
| **Phase B** | `LMB-09` | 后台增量目录扫描器、iOS `Files.app` 目录自发现与「本地书库管理中心」 | P1 | M-L | [ ] |
| **Phase B** | `LMB-10` | 本地书架「按文件夹树浏览」双模视图 | P1 | M | [ ] |
| **Phase C** | `LMB-11` | 原生 `PDF` 阅读支持（Android `PdfRenderer` + iOS `PDFKit` 按需光栅化 + 缩放高清重绘 + 大纲） | P1 | M-L | [ ] |
| **Phase C** | `LMB-12` | `CBR (RAR4 / RAR5)` 与 `CB7 (7z)` 原生 FFI 解码（含固实包滑动窗口优化） | P1 | L | [ ] |
| **Phase C** | `LMB-13` | 加密压缩包与加密 PDF 密码弹窗、中文密码双编码尝试与钥匙串/常用词典记忆 | P1 | M | [ ] |
| **Phase D** | `LMB-14` | `ComicInfo.xml` 页级指令完善（`DoublePage` / `Delete` / `Translator`）+ 手动屏蔽插播广告页 | P2 | S-M | [ ] |
| **Phase D** | `LMB-15` | 墨水屏每 N 页全刷防残影控制 | P2 | S-M | [ ] |
| **Phase D** | `LMB-16` | 编辑面板相册选图换封面 + 宽封裁半开关 + SQLite FTS5 大库搜索 + AVIF/HEIC/JXL 嗅探 | P2 | M | [ ] |
| **Phase D** | `LMB-17` | `WebDAV` 远程目录挂载与 ZIP Range 流式直读（内外网双地址切换） | P2 | L | [ ] |
| **Phase D** | `LMB-18` | `SMB (v2/v3)` 局域网共享浏览与导入/流式阅读 | P2 | L | [ ] |
| **Phase D** | `LMB-19` | 元数据导出写回 `ComicInfo.xml`、备份协议 v2 与 iPadOS 拖拽导入 | P2 | M | [ ] |

---

## 1. Phase A 详细规格（优先实施）

### `LMB-01` 宽幅合扫页自动切分（Split Wide Pages）+ 竖屏「临时合页」
- **纯逻辑层（`packages/yomu_reader`）**：
  - 定义 `WidePageSplitMode { off, autoPortrait, always }`（与 `ReaderConfig` 值对象同步序列化/恢复/预设快照/按系列覆盖）；
  - 定义 `PageHalf { full, left, right }` 与单页/纵向切分后的帧项 `SplitPageFrame(pageIndex, pageNumber, half)`；
  - 宽页判定复用现有 `aspect > wideRatio`（默认 `1.2`）：在单页翻页模式开启切分时，每张宽图无损展开为两个连续帧（`RTL` 先 `right` 后 `left`，`LTR` 先 `left` 后 `right`），进度上报与底部滑杆始终映射回 1 基物理页码 `pageNumber`；
  - 支持单帧「临时合页」状态：针对某个宽页 `pageIndex` 临时切回 `PageHalf.full` 展示完整跨页，翻离该物理页后自动清除临时合页状态。
- **渲染与交互层（`apps/app`）**：
  - `ReaderPageView` / `ReaderImage` 支持按 `PageHalf` 使用 `Align` / `ClipRect` / `CustomPaint` 零拷贝裁取半幅（叠加自动去纯色白边）；
  - 当当前展示帧为半幅（`left` 或 `right`）时，屏幕底部安全区角落渲染克制的玻璃微胶囊「合页」按钮（墨水屏走纯黑白描边样式），点击即时切换为整幅跨页预览（支持双指缩放），再次点击或翻离该页自动恢复切分；
  - `ReaderSettingsSheet`（`AA` 面板）增加「宽页自动切分」选项（关闭 / 竖屏自动 / 始终），同步中英双语 ARB。
- **验收**：`yomu_reader` 单测覆盖 0 页、单页、宽页 RTL/LTR 切分顺序、物理页码互转、边界索引与临时合页切换；`apps/app` 单测验证设置持久化、渲染裁半与临时合页交互。

### `LMB-02` 超高条漫长图（> 4096px）自动分片解码渲染
- **纯逻辑层（`packages/yomu_reader`）**：
  - 新增 `TallImageTile` 与 `computeTallImageTiles({width, height, maxTileHeight = 2048, triggerHeight = 4096})`：仅当 `height > triggerHeight` 时按 `maxTileHeight` 切为连续无缝像素区间 `[srcTop, srcBottom)`，并给出每片逻辑宽高比。
- **渲染层（`apps/app`）**：
  - 在条漫纵向视图（`ReaderVerticalView` / `VerticalPageSlot`）检测页面高度超出阈值时，展开为由多个视口裁剪子片组成的无缝纵向列（或按 `ui.Image` 分片绘制 `Canvas.drawImageRect` 零像素接缝，并结合超大图安全解码尺寸防止超出 GPU 纹理上限），释放时严格 `dispose`。
- **验收**：纯逻辑单测覆盖普通图（不切分）、恰好等于阈值、4097px、16000px 巨图零缝隙覆盖；Widget 测试验证 `800 × 12000` 超长图可正常渲染且不抛异常。

### `LMB-03` 漫画图像增强滤镜（对比度 / 去底灰漂白 / 灰阶）
- **纯逻辑层（`packages/yomu_reader`）**：
  - 定义 `ReaderImageFilterPreset { none, einkCrisp, vintageDeYellow, grayscale, custom }` 与值对象 `ReaderImageFilter`（含 `preset`、`contrast` `1.0..2.0`、`whiteThreshold` `200..255`、`grayscale` 布尔）以及纯数学 `buildImageFilterMatrix(ReaderImageFilter)` 生成 4×5 颜色矩阵（可单测验证浅灰底 `RGB(235,232,225)` 漂白为纯白 `RGB(255,255,255)`，黑色墨线保持纯黑）；
  - 集成进 `ReaderConfig` 与持久化/预设体系。
- **UI 层（`apps/app`）**：
  - 在阅读器页图绘制层叠加 `ColorFiltered(colorFilter: ColorFilter.matrix(...))`（`preset == none` 时零额外开销）；
  - 在 `ReaderSettingsSheet` 新增「画面增强」分段与自定义对比度/去底灰滑杆，墨水屏设备额外突出「墨水屏清晰增强」一键预设。
- **验收**：矩阵数学单测全绿（含边界值 clamping）；Widget 测试验证预设切换与应用矩阵。

### `LMB-04` 漫画型 `EPUB`（固定版式 / 纯图）支持
- **纯逻辑层（`packages/yomu_local_archive`）**：
  - 新增 `ArchiveErrorKind.textOnlyEpub` 与 `ContainerMagic.epub`（通过检查 ZIP 首个条目 `mimetype == application/epub+zip` 区分普通 ZIP 与 EPUB）；
  - 实现 `EpubComicReader`（实现 `ComicArchiveReader` 接口）：解析 `META-INF/container.xml` → `content.opf`（提取 `dc:title`、`dc:creator`、`dc:publisher`、`dc:description`、`dc:subject`、`belongs-to-collection`、`group-position`、`<spine page-progression-direction="rtl|ltr">`）；遍历 spine XHTML/SVG 提取主图 `<img>` / `<image xlink:href>` 按阅读顺序映射为 `ArchivePageEntry`；
  - 解析 `toc.ncx` 与 EPUB3 `nav.xhtml` 产出 `List<ArchiveChapter>`（章节名 + 1 基起始页码）；
  - 当整本 EPUB 有效图片页 < 3 且存在显著正文文字时，抛出 `ArchiveException(ArchiveErrorKind.textOnlyEpub)`。
- **应用层（`apps/app`）**：
  - 扩展 `LocalComicImporter`、`LocalReaderRepository`、`ComicFilePicker`（允许 `.epub`）、Android/iOS 文件关联支持 `.epub`，并落库章节目录。
- **验收**：内存构造固定版式 RTL 日漫 EPUB、EPUB2 (`toc.ncx`)、EPUB3 (`nav.xhtml`) 与纯文字小说 EPUB 四类单测全绿。

### `LMB-05` 单本书内部多章节目录 + 通用页级书签
- **数据层（`yomu_domain` + `apps/app`）**：
  - `yomu_domain` 新增 `BookChapter(title, startPage)` 与 `PageBookmark(scope, bookId, page, note, createdAt)`；
  - `ProgressDatabase` 升级 schema：新增 `LocalBookChaptersRows`（存 EPUB TOC / ZIP 多级子目录 / `ComicInfo` `Bookmark` 提取出的章节）与通用 `PageBookmarksRows`（本地与 Komga 远程书均可打书签）；
  - `yomu_local_archive` 的 `ZipComicReader` / `FolderComicReader` 在包含多级子目录或 `ComicInfo.xml` `Bookmark` 时自动生成 `chapters`。
- **UI 层（`apps/app`）**：
  - 升级 `ReaderTocSheet` 为「本卷章节与书签」+「系列各卷」分段视图（单本无章节且无书签时自动隐藏分段保持简洁）；
  - 阅读器顶栏 `⋯` 菜单新增「添加/移除当前页书签」并带状态反馈。
- **验收**：数据库迁移单测、章节提取单测、书签增删持久化与阅读器 TOC 跳转 Widget 测试全绿。

### `LMB-06` 老压缩包文件名 `Shift-JIS / GBK` 真转码 + `CBT/TAR` + 嵌套合集包自动拆包
- **纯逻辑层（`packages/yomu_local_archive`）**：
  - `sniffContainerMagic` 补齐 `ContainerMagic.tar`（偏移 257 `ustar`）；
  - 实现纯 Dart `TarComicReader`（按 512 字节头偏移索引，零全量解压）；
  - 实现无外部依赖的 `GBK` / `Shift-JIS` 常见字符解码器（或平台原生 Charset 回退桥 + 纯 Dart 编码探测，确保纯 Dart 单测可验证中文/日文非 UTF-8 ZIP 路径正确解码）；
  - 新增 `inspectNestedArchives` 辅助函数：检测 ZIP 内无直接图片但含多个子 `.cbz/.zip/.epub/.cbt` 时识别为嵌套合集包。
- **应用层（`apps/app`）**：
  - `LocalComicImporter` 识别嵌套合集包时，自动流式拆出子归档并归入以合集包名为标题的同一本地系列，清理外层临时包。
- **验收**：单测覆盖 TAR/CBT 随机跳页、Shift-JIS/GBK 非 UTF-8 文件名解码、嵌套 3 卷合集包自动拆包归系列。

---

## 2. 明确不做（保持产品边界）
- 纯文字流式电子书排版引擎（小说 EPUB / TXT / AZW3 重排）
- 第三方盗版在线图源爬虫 / WASM 插件源
- 国内商业网盘私有 SDK 直连（优先通过系统文件 App / WebDAV 标准协议接入）
- 端侧 AI 超分辨率实时推理（高发热、大体积模型）
- DRM 破解
