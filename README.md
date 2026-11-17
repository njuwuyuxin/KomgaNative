# KomgaNative

Komga 的跨平台客户端（iOS / Android / Android 墨水屏），阅读体验优先。

> 状态：**M1 进行中**。
> 已完成：M0 骨架（三套主题 + 黄金图闭环）、**服务器连接流程**（密码换 API Key / 直接粘贴 Key / 钥匙串保存 / 路由守卫 / 错误映射）、
> **API 契约验证**（对真实 Komga 1.30.1 实例端到端实测，见 [docs/komga-api-verification.md](docs/komga-api-verification.md)）、
> **反代与 TLS 处理**（`http` 端口自动升级 `https`、证书不受信任时固定指纹 + 用户确认，见 [docs/tls-and-proxy.md](docs/tls-and-proxy.md)）、
> **真实书架**（`/api/v1/series` 分页 + 搜索 + 按库筛选 + 封面 + 下拉刷新 + 空/错态）、
> **系列详情**（`/api/v1/series/{id}` + 书列表 + 点书进阅读器）、
> **阅读器 v2**（单页 / 双页跨页 / 纵向连续三种模式，按系列方向自动选默认值；
> 真实页图、点击翻页、双指缩放、从上次位置继续、进度回写 Komga；墨水屏白底黑字）。
> 已在 **Android 模拟器 + 本机 Komga 实例**上跑通"连接 → 书架 → 系列 → 阅读 → 进度"全链路，
> 并在**一台公网 NAS（openresty 反代 + 证书已过期）**上验证了真实登录路径。
> 待完成：阅读设置持久化（亮度/常亮/快速跳页）、进度 outbox 与多设备对账、Drift 离线缓存、i18n 与中文字体。

## 文档

| 文档 | 内容 |
|---|---|
| [docs/tech-selection.md](docs/tech-selection.md) | 技术选型：候选评分、技术栈、三大子系统设计、AI Agent 工程化、里程碑与风险 |
| [docs/environment-setup.md](docs/environment-setup.md) | 环境搭建与双机切换：免管理员安装、验收标准、踩坑表 |
| [docs/ci.md](docs/ci.md) | GitHub Actions：概念、免费额度与计费倍率、三条流水线、排障 |
| [docs/komga-api-verification.md](docs/komga-api-verification.md) | Komga API 实测记录：复现步骤、证据表、发现的缺陷、仍未验证项 |
| [docs/tls-and-proxy.md](docs/tls-and-proxy.md) | 反代与证书：真实现象（明文 400 / 证书过期）、客户端行为矩阵、复现方式 |
| [docs/adr/0001-certificate-trust.md](docs/adr/0001-certificate-trust.md) | ADR：为什么用 TOFU + 固定指纹，而不是"忽略证书" |
| [AGENTS.md](AGENTS.md) | Agent 工作契约：命令、架构不变量、DoD、反模式 |

## CI

| 流水线 | 触发 | 机器 | 内容 |
|---|---|---|---|
| `ci.yml` | push / PR / 手动 | windows | 全量门禁（含黄金图） |
| `build-android.yml` | main / 手动 | ubuntu | release APK 产物 |
| `build-ios.yml` | push / PR / tag / 手动 | macos | `--no-codesign` 编译验证（public 仓库 macOS 免费） |

## 快速开始

```bash
# 1. 环境（Windows，用户级，无需管理员）
powershell -NoProfile -ExecutionPolicy Bypass -File tool\bootstrap.ps1 -CheckOnly   # 体检
powershell -NoProfile -ExecutionPolicy Bypass -File tool\bootstrap.ps1             # 安装

# 2. 依赖与校验
cd apps/app && flutter pub get && cd ../..
dart run tool/ci.dart check

# 3. 跑起来
cd apps/app && flutter run
```

## 结构

```
apps/app                       Flutter 应用（android / ios）
packages/komga_domain          领域模型（纯 Dart，零依赖）
packages/komga_reader_engine   阅读器几何：适配缩放、平移夹紧、双页/RTL 分组
packages/komga_sync_engine     进度 outbox + 多设备对账决策
packages/komga_api             Komga REST 传输层、错误模型、URL 构造
packages/komga_design_system   token、light/dark/eink 三主题、基础组件
packages/komga_platform        设备形态与墨水屏探测的抽象层
tool/ci.dart                   统一校验入口（check / fix / test / golden）
```

依赖方向由 `dart run tool/ci.dart check` 的 `layers` 步骤强制：
`app → (design_system, platform, api, engines, domain)`；`engines → domain`；`domain → 无`。

## 质量门禁

```bash
dart run tool/ci.dart check    # format + analyze + layers + 全部测试
dart run tool/ci.dart golden   # 重新生成黄金图（仅 Windows，与 CI 一致）
```

当前基线：**256 个测试**（纯 Dart 139 / Flutter 117），**21 张黄金图**覆盖
书架（手机 light / 平板 dark / 1.3 倍字号 / 墨水屏 / 空态 / 错误态）、系列详情（手机 / 平板 / 墨水屏）、
阅读器（单页 dark+eink、双页 dark+eink、纵向 dark）、墨水屏设置、连接页（light / eink）、
证书面板（手机 / 平板 / 墨水屏）、启动页。

其中 `packages/komga_api` 的 80 个测试里包含**两层真值校验**：
`contract_test.dart` 拿官方 OpenAPI 校验客户端会构造的每个 URL；`fixtures_test.dart` 用真实服务器响应驱动解析层。
反代与证书的异常形态同样用**真实抓包**（`test/fixtures/proxy-400-plain-http.html`）和真实异常类型驱动（`errors_test.dart`）。
阅读器的几何（单页适配、双页分组、纵向偏移/页码映射）在 `packages/komga_reader_engine` 里是纯函数，32 个用例表驱动覆盖。

## 连接流程（已可用）

1. 输入服务器地址（支持反代子路径，如 `https://host/komga`）；
2. **Account 模式**：邮箱 + 密码 → 客户端自动调 `POST /api/v2/users/me/api-keys` 创建一把名为
   `KomgaNative` 的 Key → 只把 Key 存进 Keychain/Keystore，**不保存密码**；
3. **API Key 模式**：在 Komga 后台建好 Key 直接粘贴（适合开了双步验证）；
4. 连接失败按类型给不同建议（401 → 检查凭据；网络错误 → 检查地址/同网段；非 Komga 响应 → 检查反代）。

## 书架（已可用）

数据流：`LibraryScreen`（只画状态）← `ShelfController`（分页/搜索/筛选/竞态）← `LibraryRepository`（唯一碰网络的地方）← `KomgaSession`。

- 分页 + 滚到底自动预取（距底 600px，太晚会有"卡一下"的体感）；
- 搜索 350ms 防抖；按库筛选；下拉刷新（空态/错误态也能拉）；
- 封面走 `/series/{id}/thumbnail`，字节进 48 张的 LRU 缓存，失败只显示占位图**不影响整页**；
- 错误按语义分四类（凭据失效 → Sign out / 网络 / 服务端 / 协议），失败不清空已有内容；
- 请求带 generation 号，快速切库/边搜边刷新时旧响应不会覆盖新结果；
- 网格按"最大列宽 190"自适应：手机 2 列、平板 5 列、墨水屏 4 列，不用断点写死。

## 系列详情（已可用）

- 头部：封面 + 标题 + "N of M read" + 进度条 + 阅读方向（来自 `metadata.readingDirection`）；
- 书列表：封图、`#卷号 · 书名`、页数、已读完打勾；点一本书进阅读器（把已抓到的 `Book` 一起带过去，省一次请求）；
- 一次要 100 本（多数系列够用）；真超过 100 本时底部明说 "Showing 100 of N"，**不装作全都在**；
- 空系列、加载失败（可重试）、下拉刷新与书架同一套语义。

## 阅读器 v2（已可用）

三种模式，顶栏右侧的菜单随时切换，**切完页码不丢**：

| 模式 | 行为 |
|---|---|
| 单页 | 一屏一页；点击左右三分之一翻页，中间收起/显示顶栏底栏 |
| 双页 | 封面单独一屏；普通页两两成屏；宽页（跨页大图）单独成屏；左右顺序按阅读方向（RTL 时后一页在左） |
| 纵向连续 | 条漫/竖向作品；页图按宽度铺满、连续排列，滚动位置实时换算成页码 |

- **默认模式跟随系列元数据**：`readingDirection` 是 `WEBTOON` / `VERTICAL` 就直接进纵向连续，其余先单页；
  双页是用户主动选的（Komga 的元数据表达不了"双页"）。
- **真实页图**：`/books/{id}/pages` 拿尺寸 → 引擎算布局 → `/books/{id}/pages/{n}?zero_based=false` 取图；
- **缩放**：单页/双页支持双指缩放 1×–4× 与放大后拖动，缩回自动归位；纵向模式交给滚动，不叠加缩放；
- **接着读**：用服务端 `readProgress.page` 恢复位置；纵向模式滚动到对应偏移；
- **进度回写**：翻页后 600ms 防抖 PATCH；到最后一页置 `completed`，切后台立刻 flush；
  双页的"最后一屏含末页"也算读完（否则系列进度永远差一页）；
- **墨水屏**：阅读区改白底黑字（黑底会触发整屏全刷），顶栏/底栏/错误页同一套配色；
- 页列表失败 → 整页错误 + 重试；单页失败 → 页内提示 + 重试，**页码与翻页仍可用**。

## 连接到你的 Komga（NAS）

1. 地址填 `http://<NAS 局域网 IP>:<端口>`，例如 `http://192.168.1.10:25600`（也支持 `https://` 与反代子路径 `https://host/komga`）；
2. **内网 http 是支持的**：Android 已放行明文（`usesCleartextTraffic`），iOS 已配 ATS 例外；
   只有"公网地址 + 明文 http"才会弹红色警告——局域网不会；
3. **端口其实只开 HTTPS 也没关系**：反代会回 `400 The plain HTTP request was sent to HTTPS port`，
   客户端识别到这条就把协议自动换成 `https://` 重试，成功后保存的是能用的那个地址；
4. **证书过期/自签名**：会弹一个面板列出证书的 CN、颁发者、到期日和 SHA-256 指纹，
   点 `Connect anyway` 才继续。确认后只固定这一张证书——以后换证书会再问一次，不会静默放行；
5. 用邮箱 + 密码登录：客户端会调 `POST /api/v2/users/me/api-keys` 建一把 comment 形如
   `KomgaNative <UTC 时间戳>` 的 Key（同账号重名会被服务端拒绝，撞上会自动换一个重试）；
6. 之后**只保存 Key**（Keychain / Keystore），不再保存密码；可以在 Komga 后台随时吊销这把 Key；
7. 也可以直接用 API Key 模式：Komga → 账号设置 → API keys 里建一把粘进来。

排障：连不上先确认手机与 NAS 同一网段、端口没被防火墙挡、`http://` 与端口写全；
若地址被反代改写成网页，会提示"响应无法识别"；若提示"证书不受信任"，先核对面板里的指纹
（`sha256sum` 或浏览器里能看到同一张证书），确认是自己服务器再点继续。

## 模拟器实测记录（2026-11-17）

在 `kn_api36`（Android 16 / API 36）上，对着本机 `komga-1.30.1` 真实实例走了一遍：

| 验证项 | 结果 |
|---|---|
| 密码换 API Key（含撞 `ERR_1034` 后自动重试） | ✅ 服务端出现 `KomgaNative 2026-11-17T11:13:07Z` |
| 会话持久化（杀进程重启） | ✅ 直接进书架，不再要求登录 |
| 书架：真实系列 + 真实封面 + 分页 | ✅ 5 个系列，`0/1`、`2/2` 徽标正确 |
| 系列详情：书列表 + 阅读方向 | ✅ 显示 `Reads right to left` |
| 阅读器：真实页图 + RTL 翻页 | ✅ 点左侧前进，页码 `1/8 → 2/8` |
| 进度回写 + 最后一页 `completed` | ✅ 服务端 `page=8 completed=true`，系列 `1/2` |
| 返回后刷新进度 | ⚠️ 初次实测**不刷新**（仍显示 `0 of 2`），已修复并复测通过（返回后 `2 of 2`、徽标 `2/2`） |
| 返回书架不跳回顶部 | ⚠️ 第一版修复把列表重置导致跳顶，改为 `refreshInPlace` 后复测通过 |
| 真实 NAS（openresty 反代，证书 2026-07-19 过期） | ✅ 首次 `http://…:4433` 被反代回 400 → 自动升级 `https` → 弹出证书面板 → `Connect anyway` 后登录成功（见 [docs/tls-and-proxy.md](docs/tls-and-proxy.md)） |
| 双页跨页（RTL 系列，3 页真实书） | ✅ 顶栏 `2–3 / 3`；P3 在左、P2 在右（日漫右起） |
| 双页读完写回 | ✅ 服务端 `"page":3,"completed":true`（最后一屏含末页也标完成） |
| 纵向连续 + 滚动跟随页码 | ✅ 滚动后 `2 / 3 → 3 / 3`，并按页写回进度 |
| 墨水屏阅读器 | ✅ 白底黑字（顶栏/底栏/页码同套配色），不再黑底全刷 |

## 已知边界

- **阅读模式不持久化**：关掉阅读器再打开会回到"按系列方向的默认模式"，
  用户手动选的模式只在本次阅读内有效；等阅读设置面板（亮度/常亮/跳页）一起做持久化；
- **进度回写是直接 PATCH**：`sync_engine` 的 outbox/多设备对账要等 Drift 落地后接入（断网时进度会丢）；
- UI 文案暂为英文：i18n（ARB + 中文字体）之后一次性替换，避免现在把 CJK 字体塞进黄金图。
- 证书信任是**按叶证书指纹固定**：服务器续期后需要再确认一次（有意为之，不是 bug）；
  不做自签名 CA 链校验与双向 TLS。
- 书架的离线缓存（Drift）未做：断网时只有内存里的当前列表。
