# KomgaNative

Komga 的跨平台客户端（iOS / Android / Android 墨水屏），阅读体验优先。

> 状态：**M1 进行中**。
> 已完成：M0 骨架（三套主题 + 黄金图闭环）、**服务器连接流程**（密码换 API Key / 直接粘贴 Key / 钥匙串保存 / 路由守卫 / 错误映射）、
> **API 契约验证**（对真实 Komga 1.30.1 实例端到端实测，见 [docs/komga-api-verification.md](docs/komga-api-verification.md)）、
> **真实书架**（`/api/v1/series` 分页 + 搜索 + 按库筛选 + 封面 + 下拉刷新 + 空/错态）、
> **系列详情**（`/api/v1/series/{id}` + 书列表 + 点书进阅读器）。
> 待完成：阅读器接真实书页与进度同步、Drift 离线缓存、i18n 与中文字体。

## 文档

| 文档 | 内容 |
|---|---|
| [docs/tech-selection.md](docs/tech-selection.md) | 技术选型：候选评分、技术栈、三大子系统设计、AI Agent 工程化、里程碑与风险 |
| [docs/environment-setup.md](docs/environment-setup.md) | 环境搭建与双机切换：免管理员安装、验收标准、踩坑表 |
| [docs/ci.md](docs/ci.md) | GitHub Actions：概念、免费额度与计费倍率、三条流水线、排障 |
| [docs/komga-api-verification.md](docs/komga-api-verification.md) | Komga API 实测记录：复现步骤、证据表、发现的缺陷、仍未验证项 |
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

当前基线：**173 个测试**（纯 Dart 96 / Flutter 77），**14 张黄金图**覆盖
书架（手机 light / 平板 dark / 1.3 倍字号 / 墨水屏 / 空态 / 错误态）、系列详情（手机 / 平板 / 墨水屏）、
墨水屏设置、阅读器、连接页（light / eink）、启动页。

其中 `packages/komga_api` 的 55 个测试里包含**两层真值校验**：
`contract_test.dart` 拿官方 OpenAPI 校验客户端会构造的每个 URL；`fixtures_test.dart` 用真实服务器响应驱动解析层。

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

## 已知边界

- **阅读器仍是占位**：能显示真实书名/页数与分页布局，但页图管线、手势、进度回写属于 M2。
- UI 文案暂为英文：i18n（ARB + 中文字体）之后一次性替换，避免现在把 CJK 字体塞进黄金图。
- 自签名证书 TOFU 流程未做（当前用系统信任链）；M1.2 补"指纹确认"页。
- 书架的离线缓存（Drift）未做：断网时只有内存里的当前列表。
