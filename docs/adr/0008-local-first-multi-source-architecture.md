# ADR 0008：开屏免登录本地一等公民与多态数据源并存架构

- 状态：已采纳
- 日期：2026-11-26
- 相关：`apps/app/lib/src/router.dart`、`apps/app/lib/src/session/`、`apps/app/lib/src/providers/`、`packages/komga_domain`、`docs/local-manga-plan-2026-11.md`

## 背景

当前应用在路由层（`router.dart`）将 `SessionDisconnected` 无条件重定向至 `/connect` 服务器连接页。在真实用户漏斗中，自建 NAS 并部署 Komga 的用户仅占漫画读者群体的极小比例（不足 5%）；绝大多数手机、iPad 与安卓墨水屏用户手里只有本地 `.cbz` / `.zip` 压缩包或图片文件夹。开屏强制要求填写私有服务器地址与凭据，一方面直接将 95%+ 的普通读者拒之门外，另一方面在应用商店审核中极易触发强制登录墙（如 App Store Guideline 2.1 / 4.2）卡点。

与此同时，对于已使用 Komga 的核心用户，本项目的立身之本是 **Komga 原生 REST 深度语义**（`ondeck` 继续阅读、Drift Outbox + `lastModified` 多设备对账、服务端双向收藏集/阅读列表、按系列下发 `readingDirection`、TOFU 自签名证书固定），绝不能为了支持本地漫画而将 Komga 降级为功能受限的通用 OPDS 插件。

## 决策

采用 **「方案 1A：产品心智以本地阅读与管理为默认一等公民，底层基于现有 4 大抽象 Repository 实现本机源与多台 Komga 源平级并存」**：

### 1. 解耦「当前激活书库源 (`CatalogSource`)」与「远程服务器连接态 (`SessionState`)」

在 `packages/komga_domain` 定义纯值对象密封层级：

- `LocalCatalogSource`：内置单例数据源，固定分区键 `scopeKey = 'local://device'`，始终可用、不可删除；
- `KomgaCatalogSource(String serverId)`：对应一台已保存的 Komga 服务器，分区键 `scopeKey = serverId`（即规范化 `baseUrl`）。

**冷启动恢复与老用户零感知升级规则**：
1. 若本地设置已记录用户上次显式切换的 `activeSourceKey`：优先恢复该源（若对应 `StoredServer` 已被移除，自动回退至 `LocalCatalogSource`）；
2. 若尚未记录 `activeSourceKey`（全新安装，或从旧版本升级上来）：
   - 检查 `ServerStore.load()`：若存在已登录的活动 Komga 服务器（**老用户升级**），默认激活对应的 `KomgaCatalogSource`，保证老用户升级后直接回到熟悉的服务器书架，不掉登录、不跳空书架；
   - 若 `ServerStore.load() == null`（**全新安装用户**），默认激活 `LocalCatalogSource`，冷启动在 `/splash` 恢复完成后直达首页 `/reading`（或 `/library`），**彻底取消 `SessionDisconnected -> /connect` 的开屏强制拦截**；`/connect` 退化为可随时进入并返回的普通顶层路由。

### 2. 用 `SourceCapabilities` 声明源能力，禁止在 UI 散落源类型分支

在 `packages/komga_domain` 定义不可变能力描述 `SourceCapabilities`，由当前 `CatalogSource` 派生，UI 组件只读取能力位决定按钮显隐：

| 能力位 | `LocalCatalogSource`（本机书库） | `KomgaCatalogSource`（Komga 服务器） | UI 行为映射 |
|---|---|---|---|
| `canImportLocalFiles` | `true` | `false` | 书架顶栏/空态显示「导入漫画文件 / 文件夹」入口 |
| `canMutateCatalog` | `true` | `false` | 长按菜单与详情页显示「编辑信息 / 合并系列 / 重设封面 / 从设备删除」 |
| `canDownloadOffline` | `false` | `true` | 书行右侧下载按钮、系列「下载全部」菜单、设置页下载策略组 |
| `showsNetworkOfflineBanner` | `false` | `true` | 底部弱网/断网缓存悬浮胶囊 `OfflineOverlay` |
| `syncsProgressRemotely` | `false` | `true` | `ProgressSyncService` 是否向远程队列发起网络 `flush()` |
| `supportsCollections` | Phase 1 `false` → Phase 2 `true` | `true` | 收藏集与阅读列表的新建/编辑/展示 |

### 3. 复用现有 4 大抽象 Repository 多态分发，保持 Komga 原生通路零退化

`ARC-09` 已将应用数据访问收敛为四个纯领域接口：`LibraryRepository`、`ReaderRepository`、`ReadStatusRepository`、`CollectionsRepository`。

- 当激活源为 `KomgaCatalogSource` 时，四个顶层 Provider 继续注入 `Komga*Repository`（共享 `komgaSessionProvider` 连接池、HTTP 缓存与进度对账），现有 Komga 能力 **0 退化**；
- 当激活源为 `LocalCatalogSource` 时，四个顶层 Provider 注入新增的 `Local*Repository`，直接读写本地 SQLite 目录表与本地归档文件，**不再调用 `requireKomgaSession`**；
- 阅读器（`ReaderScreen` 及全部 25+ 个子组件）、书架网格/列表、搜索页、历史页、统计热力图面向上述抽象接口编程，无需感知页图 `Uint8List` 来自 HTTP 还是本地 `.cbz`。

### 4. 复用 `ARC-07` 的 `scope` 复合主键实现用户资产天然隔离

`komga_native.sqlite` 中的 `LocalProgress({scope, bookId})`、`PinnedSeriesRows({serverId, seriesId})`、`ReadingSessions(scope, ...)`，以及 `ReaderPrefs` 的 `seriesOverrides` 与 `spreadFrom` 均已按字符串 `scope` 分区：

- 将 `activeServerKeyProvider` 统一升级为返回当前激活源的 `scopeKey`（本机源恒为 `'local://device'`，不再返回空串 `''`）；
- 本地漫画的阅读页码保存、系列置顶、阅读会话记录、Insights 热力图、按系列阅读器配置覆盖与双页分组起点 **100% 自动生效**，且与任意 Komga 服务器的数据严格物理隔离；
- `ProgressSyncService` 在 `scope == 'local://device'` 时直接将进度落盘至 `LocalProgress`（`pendingSeq = null`），跳过远程 HTTP 上传循环。

## 备选方案与否决理由

| 备选方案 | 否决理由 |
|---|---|
| **方案 2：保持 Komga 核心，仅在未连接时提供互斥「离线本地模式」** | 1. **互斥断层致命伤**：用户先在离线模式导入阅读 20 本本地书，后续一旦连接 Komga 服务器，本地书架即被隐藏/不可见，查看本地文件还需先退出服务器登录；<br>2. **主流用户二等公民体验**：95% 纯本地用户长期面对“离线受限”心智与残缺编目（无法合并散装单卷、无本地收藏集）；<br>3. **节省工期极有限**：文件选择、沙盒持久化、CBZ 流式读取、`ComicInfo.xml` 解析与本地目录表在方案 2 中一分省不掉，仅省约 25% UI 工作量，日后改并存还需二次返工。 |
| **方案 1B：按通用图源阅读器推倒重写，将 Komga 降级为 OPDS 插件并全量同步至本地主表** | 1. **自毁核心差异化壁垒**：降级 OPDS 会丢失按系列下发阅读方向、流式下一本、服务端双向收藏集与 `lastModified` 精确对账；<br>2. **大库性能灾难**：自建 Komga 常含数千系列、数万册书，强行全量拉取落入本地目录表会导致首次连接漫长卡顿与删改同步风暴；<br>3. **回归面过大**：波及 140+ 存量文件与 70+ 测试文件。 |

## 后果

- 全仓约 **87% 的现有生产文件无需修改**；核心改造集中在路由守卫、源状态机、5 个顶层仓库 Provider 分发与约 14 个源能力自适应 UI 文件。
- 本机书库与 1..N 台 Komga 服务器平级并存，为未来按需扩展只读 OPDS / Kavita / WebDAV 数据源预留了现成的 `CatalogSource + Repository` 插槽，而无需再次改动 UI 层。
- 本地目录编目表（`LocalSeriesRows` / `LocalBooksRows` / `LocalPagesRows`）写入不可再生的用户资产库 `komga_native.sqlite`（通过 Drift `schemaVersion` 平滑迁移），保证清空浏览缓存（`komga_cache.sqlite`）绝不误伤用户导入的本地书库。
