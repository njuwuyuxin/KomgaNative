# ADR 0009：本地漫画导入（`file_picker`）与纯 Dart 随机访问 CBZ/ZIP 引擎

- 状态：已采纳
- 日期：2026-11-26
- 相关：`packages/yomu_local_archive`、`packages/yomu_platform`、`apps/app/lib/src/data/local/`、ADR 0006、ADR 0008

## 背景

根据 ADR 0008，Phase 1 本地书库需优先支持漫画读者最主流的离线载体：**`.cbz` / `.zip` 压缩包**与**图片文件夹**，并解析内嵌的 **`ComicInfo.xml`** 标准元数据（系列名、卷号、作者、简介、标签、日漫右翻 `Manga` 方向）。

在移动端与安卓墨水屏设备上落地本地漫画读取，面临三个核心工程挑战：

1. **超大压缩包内存峰值（OOM 风险）**：单卷高清扫描版或合集 `.cbz` 常达 300 MB – 1.2 GB。若使用常规解压库将整个压缩包读入内存或整包解压到磁盘，不仅导入极慢、双倍消耗闪存，在 2–3 GB RAM 的墨水屏设备上还会直接触发 OOM 崩溃。
2. **移动端外部文件权限生命周期**：iOS 的文档选择器默认把选中文件拷贝到系统临时目录（随时可能被系统回收），Android 的 SAF URI 跨进程重启后若未持久化授权或源文件被移动就会失效。
3. **双页与条漫排版的页面宽高预知需求**：`komga_reader_engine` 计算双页跨页配对（宽页 `aspectRatio > 1.2` 独占一屏）与条漫滚动高度时依赖 `PageInfo(width, height)`；若导入时全量解码几百张大图测宽高会严重阻塞导入速度，若不测宽高则打开阅读器时双页分组会跳变。

同时，`AGENTS.md` 规定：**严格克制新增第三方依赖，确需引入必须经过 ADR 论证。**

## 决策

### 1. 仅引入一个第三方插件依赖：`file_picker`

引入 **`file_picker`** 用于唤起各平台原生系统文件/目录选择器（iOS `UIDocumentPickerViewController`、Android Storage Access Framework `ACTION_OPEN_DOCUMENT` / `ACTION_OPEN_DOCUMENT_TREE`）：

- **引入理由**：与 ADR 0006（`share_plus`）一致，本仓库在 Windows 环境开发、iOS 构建依赖云端 CI，不应手写未经本地编译和真机调测的 iOS Swift/ObjC 原生文件选择通道；`file_picker` 是 Flutter 生态最成熟的文件与目录选择方案，无需申请宽泛的 `MANAGE_EXTERNAL_STORAGE` 敏感权限即可合规通过 Play Store 与 App Store 审核。
- **测试隔离**：通过抽象接口 `ComicFilePicker` 封装文件/目录选择结果，业务层与 Widget 测试注入内存假实现，不直接耦合插件静态调用。

### 2. 新建零外部依赖的纯 Dart 包 `packages/yomu_local_archive`（面向 `RandomAccessByteSource` 抽象）

对于 `.cbz` / `.zip` 解析、`ComicInfo.xml` 解析与图片尺寸提取，**不引入任何第三方 pub 依赖**，全部在新建纯 Dart 包 `packages/yomu_local_archive` 中基于抽象随机字节源接口 `RandomAccessByteSource`（`length()` + `readRange(offset, count)`）与 Dart SDK 标准库（`dart:typed_data`、`dart:convert`、原生 `ZLibCodec`）实现：

1. **面向 `RandomAccessByteSource` 的 \(O(1)\) 随机访问 ZIP 中央目录读取器与文件头魔数嗅探**：
   - **文件头魔数嗅探（Magic Bytes Sniffing）**：先读取前 16 字节校验真实容器（`50 4B 03 04` ZIP、`52 61 72 21` RAR4/RAR5、`37 7A BC AF` 7z、`%PDF`），即使民间资源将 `.zip` 误改后缀为 `.cbr` 也能按真实格式打开，若是 RAR/7z/PDF 则返回明确的结构化格式提示而非报文件损坏；
   - 打开或导入 `.cbz` / `.zip` 时，仅通过 `readRange` 读取末尾最多 `65,557` 字节定位 **EOCD（End of Central Directory，同时兼容 64 位超 4 GB 的 ZIP64 EOCD Locator/Record）**，仅将中央目录索引表（通常仅 10–50 KB）解析为内存条目列表；
   - **非 UTF-8 文件名容错**：当 ZIP 条目未置位 UTF-8 标志（Bit 11）且字节序列非合法 UTF-8 时，回退解码日文 `Shift-JIS` / 中文 `GBK` 文件名（或通过平台字符集桥接），防止老扫描包章节乱序；
   - 阅读器请求第 `page` 页（1 基）时，按该页条目记录的 `localHeaderOffset` 执行单次 `readRange` 读取压缩块：
     - **Stored（`method == 0`，90%+ 的 CBZ 采用无压缩封装 JPEG/WebP）**：直接切片返回 `Uint8List`，零 CPU 开销；
     - **Deflate（`method == 8`）**：调用 Dart VM 内置的 C++ 原生 `ZLibCodec(raw: true).decode(compressedBytes)`，速度显著快于纯 Dart 实现的 `package:archive` 解码器，且**内存峰值严格等于单页体积（1–3 MB）**；
     - **异常防护**：若检测到加密位（General Purpose Bit 0）或非标准压缩算法（如 Deflate64/LZMA/BZip2），明确抛出密封类型 `ArchiveException(ArchiveErrorKind.encrypted | unsupportedCompression)`，由数据层映射为用户可读提示，严禁裸抛崩溃；
   - **字节源多态扩展性**：单测直接传 `MemoryByteSource(Uint8List)` 无需落盘临时文件；沙盒文件传 `FileByteSource(RandomAccessFile)`；后续扩展 Android SAF 原位目录挂载（`ParcelFileDescriptor`）或 WebDAV `Range` 流式直读时，仅需新增一个 `RandomAccessByteSource` 实现，归档解析引擎 **0 行改动**。
2. **图片文件头极速宽高嗅探（Image Header Sniffing）**：
   - 导入扫描每页时，仅读取每张图片前 **64–512 字节**（不解码像素位图！），纯二进制解析 **PNG (`IHDR`)**、**JPEG (`SOF0`–`SOF15` 段扫描)**、**WebP (`VP8 ` / `VP8L` / `VP8X`)**、**GIF** 与 **AVIF (`ispe` box)** 头部宽高；
   - 200 页漫画可在数十毫秒内提取全部精确 `width` 与 `height` 持久化到 `LocalPagesRows`，确保双页自动跨页与条漫高度计算在进入阅读器首帧即 100% 精准；仅对第 1 页解码生成一张 300px 封面缩略图落盘。
3. **零依赖轻量 `ComicInfo.xml` 解析与自然文件名排序（Natural Sort）**：
   - `ComicInfo.xml` 结构扁平固定（通常 < 4 KB），内置轻量状态机解析器提取 `<Series>`、`<Title>`、`<Number>`、`<Summary>`、`<Writer>`、`<Penciller>`、`<Publisher>`、`<Year>/<Month>/<Day>`、`<Tags>`、`<Genre>` 与 `<Manga>`（将 `YesAndRightToLeft` / `Yes` 映射为 `ReadingDirection.rightToLeft`），正确处理 UTF-8 BOM、CDATA 与标准 XML 字符实体转义；
   - 页条目排序统一采用跨平台确定性的**自然排序（Natural Sort）**，保证 `page_2.jpg` 排在 `page_10.jpg` 之前，且自动忽略 `__MACOSX/`、`Thumbs.db`、`.DS_Store` 等打包垃圾文件。

### 3. 应用沙盒受管存储模型（Managed Sandbox Copy）

- 导入 `.cbz` / `.zip` 或图片文件夹时，统一以流式分块拷贝（避免整文件进内存）转入 `<ApplicationSupportDirectory>/local_comics/<bookId>/` 受管目录（`.cbz/.zip` 保持单文件原样存放不拆散成零碎小文件；图片文件夹存为受管子目录或打包存储），并在入库完成后立即调用 `FilePicker.platform.clearTemporaryFiles()`（或删除源临时缓存副本），杜绝双倍占用系统空间；
- 用户在应用内删除本地书籍时，同步清理 SQLite 记录、封面缩略图与 `local_comics/<bookId>/` 目录，空间回收确定可控，且完全不受系统清理缓存、重启后 SAF URI 权限丢失或外部文件改名影响。

## 备选方案与否决理由

| 备选方案 | 否决理由 |
|---|---|
| 引入 `package:archive` 直接 `ZipDecoder().decodeBytes` | 会将整个压缩包字节读入 Dart 堆内存或全量构建解压树，数百 MB 合集 `.cbz` 在移动端/墨水屏极易 OOM；且 Dart VM 已自带 C 级 `ZLibCodec`，无需重复引入第三方压缩库。 |
| 导入时把 `.cbz` 全量解压成散装图片文件存盘 | 一本 200 页漫画制造 200 个小文件，导入慢、IOPS 高、文件系统簇碎片浪费空间；保留原 `.cbz` 配合中央目录偏移随机读，打开与删除都是单文件级操作。 |
| 不拷贝进沙盒，只保存外部文件路径 / SAF URI | iOS 文档选择器临时副本会被系统随时清除（若做 Security-Scoped Bookmark 则需维护原生 Swift 插件）；Android SAF `ContentResolver` 无法对 `.cbz` 做高效的 `RandomAccessFile` 随机偏移跳转，仍需落盘缓冲。受管目录在双端最稳健一致。 |
| Phase 1 同步引入 PDF (`pdfrx`) 与 RAR/CBR 原生库 | PDF 与 RAR（UnRAR 许可限制及 C++ FFI 编译体积）会显著增加双端构建复杂度与 APK/IPA 包体大小；先以纯 Dart 把漫画圈占比超 85% 的 CBZ/ZIP + 文件夹做到极致，PDF/EPUB 留待后续独立迭代评审。 |

## 后果

- 全仓仅新增 **1 个** 第三方插件依赖（`file_picker`），核心归档引擎 `packages/yomu_local_archive` 保持 100% 纯 Dart，毫秒级跑完 `dart test`，并纳入 `tool/ci_checks.dart` 的纯逻辑包门禁（禁止依赖 `flutter` / `dio` / `drift` / `go_router`，单文件 ≤ 350 行、单类 ≤ 300 行）。
- 代价是应用沙盒会持有一份漫画文件副本（与主流 iOS/Android 本地阅读器 Panels、Aidoku 一致），因此必须在设置页「存储」分组清晰展示「本地漫画占用」并提供单本/批量删除以释放空间。
