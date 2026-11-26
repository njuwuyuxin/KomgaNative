# KomgaNative — Agent 工作契约

> 这份文件是给 AI Agent 看的操作手册。改代码前先读它，不要靠猜。

## 项目是什么

Komga（自建漫画服务器）的跨平台原生客户端：iOS / Android / Android 墨水屏，阅读体验优先。
技术选型与理由见 `docs/tech-selection.md`，环境搭建见 `docs/environment-setup.md`。

## 命令（唯一入口）

```bash
dart run tool/ci.dart check      # 全量门禁：格式 + 分析 + 分层 + 全部测试
dart run tool/ci.dart fix        # 自动格式化 + dart fix
dart run tool/ci.dart test       # 只跑测试
dart run tool/ci.dart golden     # 重新生成黄金图基线（Windows）
dart run tool/ci.dart install    # 构建 release 装到模拟器（提交前必须跑，见"标准交付流程"）
dart run tool/emulator.dart      # 启动本地 Android 模拟器（可选，见 docs/environment-setup.md §11）
dart run tool/komga.dart start   # 启停本地 Komga 服务器（可选，联调用；stop / status，见 §12）
```

单包测试（更快，改纯逻辑时优先）：

```bash
dart test packages/yomu_reader
dart test packages/yomu_sync
flutter test apps/app
```

## 仓库结构

```
apps/app                     Flutter 应用 `yomu`（唯一可执行目标：android, ios）
packages/yomu_domain         纯 Dart：通用漫画领域模型（零依赖）
packages/yomu_reader         纯 Dart：分页/双页/缩放/卷页几何计算
packages/yomu_sync           纯 Dart：进度 outbox + 多设备对账
packages/yomu_local_archive  纯 Dart：本地 CBZ/ZIP 随机访问、文件夹扫描、宽高嗅探与 ComicInfo.xml 解析
packages/komga_api           Komga 服务器专属 REST 传输层、错误模型、URL 构造
packages/yomu_design_system  Yomu 设计 token、三套主题、基础组件
packages/yomu_platform       平台能力抽象（设备形态、墨水屏探测、按键、相册存储与外部文件打开）
tool/ci.dart                 统一校验入口
tool/emulator.dart           本地模拟器启动器（可选，见 docs/environment-setup.md §11）
tool/komga.dart              本地 Komga 启停（可选，联调用，见 §12）
docs/                        选型、环境、spec、ADR
```

## 架构不变量（违反即失败，`ci.dart layers` 会拦）

1. `yomu_domain` / `yomu_reader` / `yomu_sync` / `yomu_local_archive` **不得** import flutter / dio / drift / go_router。
2. `apps/app/lib/src/screens/**` 与 `widgets/**` **不得** import `package:komga_api`，只能经 Repository。
3. Widget 里不做网络 I/O，不 `await` 请求；只读 provider 状态 + 派发 intent。
4. 错误统一用 `KomgaError`（`packages/komga_api/lib/src/errors.dart`）或领域内的密封类型，UI 只 `switch`，不允许裸 `catch`。
5. 设计数值只能来自 `design_system` 的 token（`AppSpacing` / `AppRadii` / `AppSizes` / `AppMotion` / `AppMaterial` / `AppShadows` / `AppShapes` / `AppTypography`），禁止魔法数字；毛玻璃与触感反馈只能经 `FrostedSurface` / `AppHaptics`（`ci.dart layers` 会拦）。页面里的玻璃控件只用 `GlassHeaderSliver` / `GlassTopBar` / `GlassSurface` / `GlassIconButton` / `GlassBarAction` / `GlassPillButton` / `GlassSegmentedControl` / `GlassSearchField` / `GlassMenuButton`，不要自己拿 `FrostedSurface` 拼标题栏。说明见 `docs/design-system.md`。
6. 断点判断只在 `WindowSizeClass`（一次性），页面内部不要自己判断"是不是平板"。

## 完成定义（DoD）

- [ ] 新增/修改的纯逻辑有单测；边界值（0、越界、未知、RTL、宽页）覆盖到
- [ ] 新增 UI 有黄金图（`apps/app/test/golden/`），并且**用 `read_image` 自查过**
- [ ] 涉及 API 的变更：新端点先加进 `KomgaUrls`（contract_test 会自动覆盖），解析层用 `test/fixtures/` 里的**真实响应**驱动
- [ ] `dart run tool/ci.dart check` 全绿
- [ ] 相关 `docs/` 段落已更新
- [ ] **提交前**已装到模拟器并实际操作验证：`dart run tool/ci.dart install`（见"装到模拟器"）

## 标准交付流程（本地绿 → 设备验证 → 提交推送）

功能开发完成后按这个顺序走，**不要跳步、不要换序**：

1. **本地门禁**：`dart run tool/ci.dart check` 全绿（格式 + 分析 + 分层 + 全部测试 + 黄金图）。
2. **设备验证**：`dart run tool/ci.dart install` 装 release 到模拟器，**实际操作本次改动的路径**。
   验证的是"将要提交的那份代码"——装完又改了代码，必须重跑第 1、2 步。
3. **提交**：`git add` 只加与本次任务相关的文件；工作区里无关的未提交改动不要顺手带上，
   确实有依赖就先单独提交并在回复里说明。
4. **推送**：`git push origin main`，触发 GitHub Actions（CI / Android / iOS）。
5. **不等 CI**：推送成功即可结束本轮，汇报"已推送 + 本地/设备验证结论"。CI 是最后的保险，
   红了再单独修（平台/版本差异只有 CI 能暴露），**不要为了等绿而空转**。

## 装到模拟器（提交前，强制）

第 2 步的细节。每次**代码提交前**都要把 release 包装到正在运行的模拟器上，确认不是"测试绿、启动崩"：

```bash
dart run tool/emulator.dart                    # 没启动先启动（见 docs/environment-setup.md §11）
dart run tool/ci.dart install                  # 构建 release、安装并启动
dart run tool/ci.dart install emulator-5554    # 多设备时显式指定
```

- 装的是 **release**（debug 签名）；命令用 `flutter run --release --no-resident`，
  **保留应用数据**（`flutter install` 会先卸载，每次都清掉登录态/缓存，别用）；
- 至少确认能启动、书架能出内容，并**实际操作本次改动的路径**；转场 / 动画 / 骨架这类
  只看启动看不出来，必要时用 `adb shell screencap` 抓帧确认；
- 纯文档提交可以跳过，但要在最终回复里说明"本次未跑设备"；
- 命令实现在 `tool/ci.dart` 的 `installApp`：不要自己拼 `adb install`（adb 的路径由 Flutter 管理）。

## API 真值规则（重要）

假实现（fake）只能证明"我调用了我以为的方法"，**不能**证明这个方法/字段/语义是真实的。
Komga 的真实行为记录在 `docs/komga-api-verification.md`，已知与 OpenAPI 规格不符的地方至少两处
（`BookDto.number` 实际是 int；`readingDirection` 规格无枚举且默认空串）。

- 不允许在代码注释或文档里写"实测/已验证"，**除非**有对应证据（fixture、契约测试、或该文档里的一行记录）。
- 新增端点：先抓真实响应存进 `packages/komga_api/test/fixtures/`，再写解析与测试。
- 官方规格文件：`test/fixtures/openapi-1.30.1.json`，升级 Komga 版本时同步替换。

## 黄金图约定

- 基线平台：**Windows**（与 CI 的 `windows-latest` 一致）。不要在 Linux/macOS 上 `--update-goldens`，否则整套基线作废。
- 命名：`<页面>@<形态>_<主题>[_text<缩放>].png`，例如 `library@tablet_dark.png`。
- 新增页面必须同时补齐：手机 light、平板 dark、墨水屏 eink 三张（除非该页面在墨水屏不可达）。
- **黄金图里不得读系统时钟**（`DateTime.now()`）：基线会随运行日期/时区漂移，本地绿、CI 红且复现不出来。
  需要"今天"的页面把时钟作为参数注入（如 `InsightsScreen(now:)`），测试里传固定值；门禁的 `goldens` 步会拦。

## 反模式

- 不写 `dynamic`，不 `catch (_)`，不 `print`（用 `debugPrint` 或日志抽象）。
- 不为"以后可能用到"提前抽象：抽象只在出现**第三个**调用点时引入。
- 不新增第三方依赖；确需新增，先在 `docs/adr/` 写清楚理由。
- 单文件超过 350 行、单类超过 300 行 → 先拆再写。
- 不要为了让测试通过而改断言；基线变更必须能说出"为什么这次渲染变了"。

## CI

三条 workflow 在 `.github/workflows/`，说明见 `docs/ci.md`：

- `ci.yml`（Windows）：每次 push/PR 跑全量门禁。**本地绿 ≠ CI 绿**（平台 / Flutter 版本差异只会在 CI 暴露），
  但它**不阻塞交付**：本地检查 + 设备验证通过就提交推送，**不必等结果**；CI 红了再单独修。
- `build-android.yml`（Ubuntu）：main 分支 / 手动，产出 release APK；
- `build-ios.yml`（macOS）：push / PR / tag / 手动，编译验证（public 仓库 macOS 免费；转私有需去掉 push/PR 触发）。

改 workflow 后请同步更新 `docs/ci.md` 的流水线表。

## 当前阶段

核心功能、架构治理（`ARC-01` ~ `ARC-12`）与本地/多源双栖演进（`LMA-01` ~ `LMA-12`）已完成：
- **本地优先免登录与多源双栖架构（ADR 0008 / 0009）**：取消开屏强制登录墙，冷启动免登录直达主界面；通过 `SourceRegistry`（`sourceKey` 插件注册表）实现「编目按源清晰分组（单源时隐藏分组栏）+ 首页正在读/阅读器/历史热力图跨源无感汇聚（云端项配低调小云标）」，支持 `CBZ/ZIP` 与图片文件夹流式入库、本地收藏集/阅读列表、本地系列合并/拆分/元数据编辑/自定义封面以及系统外部文件「用 Yomu 打开」。
- **连接与多服务器隔离**：连接流程、TOFU 自签名证书固定（`lib/src/session/`）、统一共享 `komgaSessionProvider` 连接池；本地进度、已下载书籍、下载队列、置顶系列、阅读历史与阅读器按系列覆盖全面按 `sourceKey / serverKey` 复合主键分区物理隔离。
- **数据层与离线能力**：按限界上下文拆分为 `LibraryRepository`、`CollectionsRepository`、`ReadStatusRepository`、`ReaderRepository`；用户资产库 `komga_native.sqlite`（本地进度 Outbox、系列置顶、阅读会话统计）与可再生缓存库 `komga_cache.sqlite`（HTTP 响应缓存、整本下载 `pinned` 页图保护与 256 MB 被动浏览 LRU 淘汰）物理分离。
- **阅读器与 UI**：单页 / 双页 / 条漫纵向滚动与自动滚动、卷页着色器、纯配置值对象 `ReaderConfig`（预设快照与按系列覆盖零漂移）、平板双栏自适应（`WindowSizeClass` 唯一出口）、中英双语 i18n 与 CJK 字体测试回退、阅读统计热力图。
- **自动化门禁（`tool/ci.dart`）**：代码生成 + 格式检查 + 静态分析 + 分层与代码规模红线（非生成生产文件 ≤ 350 行、单类 ≤ 300 行、零裸 `catch (_)`）+ 黄金图确定性检查 + 全量单测与黄金图基线。

接服务器时注意：网络访问只能出现在 `lib/src/data/` 的 Repository 层，screen/widget 里禁止 `dio` 与直接读写 Store。
新增 API 调用时同步在 `test/support/` 补假实现，保持"可离线测试"；
但**假实现不等于验证**，端点行为必须按上面"API 真值规则"落到 fixture 与契约测试里。

书架与列表层的既有约定（改动前先看）：
- UI 只认 `ShelfFailure`（`lib/src/data/shelf_failure.dart`），不认 `KomgaError`；
- 封面失败必须返回 `null`，绝不让装饰性资源打断整页；
- 失败时**不清空**已有内容（刷新/翻页失败保留旧列表并在局部提示）；
- 新的列表/分页逻辑一律走 `ShelfController` 或通用增量分页器 `PagedListController<T>`（内置 `_generation` 竞态保护与 `page` 递增），不要在页面里自己发请求或用增大 `size` 重拉第 0 页；
- **不要用 `switch (asyncValue) { AsyncError() => … }` 做错误分支**：Riverpod 3 首次加载失败给的是
  `AsyncLoading` + `hasError`（`test/providers/async_value_behavior_test.dart` 钉住了这个行为），
  一律按 `hasError` / `value` 判断。
