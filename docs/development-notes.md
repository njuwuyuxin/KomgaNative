# 开发过程记录与工程说明

> 本文档收纳原根 `README.md` 中的开发过程记录、M1/v1 阶段验证归档、内部实现说明与全量设计文档索引，供贡献者与维护者查阅。
> 面向用户的项目功能、连接与部署说明请见 [README.md](../README.md)（[English](../README.en.md)）。

---

## 1. 迭代历程概览

| 阶段 | 核心内容 | 详细记录 |
|---|---|---|
| **M0 – M1 / v1（2026-11-17）** | 三主题与黄金图基线、连接与 TOFU 证书固定、书架与系列详情、阅读器三模式、进度 Outbox、离线缓存、整本下载、多服务器、i18n、无障碍与平板两栏 | [roadmap.md](roadmap.md) · [CHANGELOG.md](../CHANGELOG.md) |
| **UI 精致化（2026-11-19）** | 对标 Panels 的 P0–P3 批次：设计系统与液态玻璃、动态/沉浸背景、阅读预设、按系列设置覆盖、锁定缩放、手动双页分组、翻页卷曲着色器、收藏集与阅读列表、全局搜索、自动去白边、墨水屏自动探测、隐身模式 | [ui-polish-plan.md](ui-polish-plan.md) · [panels-comparison.md](panels-comparison.md) |
| **需求收敛 W0–W6（2026-11-20）** | 42 项体验与正确性需求全部落地：页码滑杆与目录、AA 快捷设置、点击区预设、条漫自动滚动、书架/系列多选批量与置顶、收藏集管理、下载队列持久化与策略、阅读会话历史与 12 周统计热力图、平板书架两栏与默认排版、数据层错误本地化、偏好导出导入 | [requirements-plan-2026-11.md](requirements-plan-2026-11.md) · [requirements-progress-2026-11.md](requirements-progress-2026-11.md) |
| **架构治理 `ARC-01` ~ `ARC-12`** | 多服务器复合主键隔离、用户库与可再生缓存库物理分离、整本下载页图与被动浏览 LRU 解耦、按限界上下文拆分 Repository、统一共享连接池、`ReaderConfig` 纯值对象化、超长文件/类拆分与 `tool/ci.dart` 代码规范门禁加固 | [architecture-review-remediation-plan-2026-11.md](architecture-review-remediation-plan-2026-11.md) |

---

## 2. 内部架构与实现备忘

### 2.1 数据流与存储分区

- **UI 与网络隔离**：`screens/` 与 `widgets/` 不直接依赖 `komga_api` 或 `dio`，只读取 Riverpod 状态与派发意图；网络访问集中在 `apps/app/lib/src/data/` 的各限界上下文 Repository（`LibraryRepository`、`CollectionsRepository`、`ReadStatusRepository`、`ReaderRepository`），共享统一的 `komgaSessionProvider` 连接池。
- **双库物理分离（Drift）**：
  - 用户资产库 `komga_native.sqlite`：存放本地进度 Outbox（`local_progress`）、系列置顶、阅读会话历史，清空缓存不会误删用户数据。
  - 可再生缓存库 `komga_cache.sqlite`：存放 HTTP GET 响应缓存与下载队列；整本下载页图采用 `pinned` 保护，避免被被动浏览的 256 MB LRU 缓存淘汰。
- **多服务器隔离**：进度、已下载书籍、下载队列、置顶系列、阅读历史与按系列阅读覆盖均按规范化服务器 `serverKey` 分区隔离。
- **轻量偏好存储**：阅读器偏好（`ReaderConfig` 快照、预设、按系列覆盖、按书双页分组）与应用设置保存在 `flutter_secure_storage` JSON 中，逐字段容错，坏存档自动回落默认值。

### 2.2 进度 Outbox 与多设备对账

- 翻页不直接依赖即时网络请求：先落本地 Drift `local_progress`，同书合并只保留最新一条，再防抖异步提交。
- 回执校验 `seq`：提交期间继续翻页时不会误清较新的本地进度。
- 补交时机覆盖冷启动、会话恢复/重新登录、应用回前台与后续翻页；遇到 `401/403` 暂停本轮并保留队列，遇到不可重试的 `404/400` 跳过坏项避免队头阻塞。
- 对账以服务端 `lastModified` 为准（不依赖客户端本地墙钟），由纯函数 `decideSync` 决定推送、采纳或忽略；展示层叠加本地未提交进度。详见 [ADR 0002](adr/0002-progress-outbox-and-drift.md)。

### 2.3 传输层离线缓存

- 缓存钩在 `KomgaSession` 的 GET 通道，成功即落盘，仅在网络故障或 `5xx` 时回退缓存并展示离线提示；`401/403/404` 如实报错不回退。
- JSON 响应按每服务器 400 条独立裁剪，不参与图片 256 MB 字节淘汰。详见 [offline-cache.md](offline-cache.md) 与 [ADR 0003](adr/0003-http-response-cache.md)。

### 2.4 质量门禁与测试体系

所有本地与 CI 校验统一经由 `tool/ci.dart` 执行：

```bash
dart run tool/ci.dart check    # codegen + format + analyze + layers + goldens + 全部测试
dart run tool/ci.dart fix      # 自动格式化 + dart fix --apply
dart run tool/ci.dart golden   # 重新生成黄金图基线（仅 Windows，与 CI runner 一致）
dart run tool/ci.dart install  # 构建 release 装到模拟器并启动（保留应用数据）
```

- **分层与规范门禁**（`ci.dart layers`）：纯逻辑包零 Flutter/Dio/Drift/GoRouter 依赖；UI 层禁止直接 import `komga_api` 或直接使用 `BackdropFilter` / `HapticFeedback`；非生成生产文件 `≤ 350` 行、单类 `≤ 300` 行、零裸 `catch (_)`。
- **API 真值校验**：`packages/komga_api` 同时通过 OpenAPI 规格契约测试（`contract_test.dart`）与真实 Komga 1.30.1 响应 fixture（`fixtures_test.dart`）校验 URL 与解析层，详见 [komga-api-verification.md](komga-api-verification.md)。
- **黄金图确定性**：基线平台固定为 Windows（与 GitHub Actions `windows-latest` 一致），测试中禁止直接读取系统时钟（`DateTime.now()`），中文排版通过测试专用 Noto Sans SC 子集字体回归（见 [ADR 0004](adr/0004-cjk-font.md)）。
- **Release APK 权限备忘**：Android release 构建仅合并 `apps/app/android/app/src/main/AndroidManifest.xml` 中的权限（不包含 `src/debug`）；`INTERNET` 权限已由 `apps/app/test/platform/android_manifest_test.dart` 钉住，必要时也可用 `aapt2 dump permissions app-release.apk` 复核。

---

## 3. v1 / M1 阶段模拟器实测归档（2026-11-17）

在 `kn_api36`（Android 16 / API 36）上针对本机 `komga-1.30.1` 实例及公网 openresty 反代 NAS 完成的端到端实测记录：

| 验证项 | 结果 |
|---|---|
| 密码换 API Key（含撞 `ERR_1034` 后自动重试） | ✅ 服务端出现 `KomgaNative 2026-11-17T11:13:07Z` |
| 会话持久化（杀进程重启） | ✅ 直接进书架，不再要求登录 |
| 书架：真实系列 + 真实封面 + 分页 | ✅ 5 个系列，`0/1`、`2/2` 徽标正确 |
| 系列详情：书列表 + 阅读方向 | ✅ 显示 `Reads right to left` |
| 阅读器：真实页图 + RTL 翻页 | ✅ 点左侧前进，页码 `1/8 → 2/8` |
| 进度回写 + 最后一页 `completed` | ✅ 服务端 `page=8 completed=true`，系列 `1/2` |
| 返回后刷新进度 | ✅ 初测发现不刷新，修复后复测通过（返回后 `2 of 2`、徽标 `2/2`） |
| 返回书架不跳回顶部 | ✅ 改为 `refreshInPlace` 后复测通过 |
| 真实 NAS（openresty 反代，证书 2026-07-19 过期） | ✅ `http://…:4433` 遇 400 自动升级 `https` → 弹证书面板 → 确认后登录成功（见 [tls-and-proxy.md](tls-and-proxy.md)） |
| 同一台 NAS 续期证书后 | ✅ 严格校验直接通过，不再弹面板 |
| 双页跨页（RTL 系列，3 页真实书） | ✅ 顶栏 `2–3 / 3`；P3 在左、P2 在右 |
| 双页读完写回 | ✅ 服务端 `"page":3,"completed":true`（最后一屏含末页即标完成） |
| 纵向连续 + 滚动跟随页码 | ✅ 滚动后 `2 / 3 → 3 / 3`，并按页写回进度 |
| 墨水屏阅读器 | ✅ 白底黑字（顶栏/底栏/页码同套配色），避免黑底全刷 |
| 阅读设置：亮度 | ✅ 调至 20% 后整页变暗，杀进程重启后持久化生效 |
| 阅读设置：常亮 | ✅ 打开后 `dumpsys window` 出现 `fl=KEEP_SCREEN_ON`，关闭即消失 |
| 进度 Outbox：离线翻页与冷启动补交 | ✅ 离线翻页落盘后强杀重启，联网后自动补交并更新服务端 `lastModified` |

> 后续 W0–W6 与 `ARC-01` ~ `ARC-12` 的逐项设备验证记录详见 [requirements-progress-2026-11.md](requirements-progress-2026-11.md)。

---

## 4. 历史阶段性边界演进对照

原 M1 README 中列出的部分限制已在后续迭代中解决，特此归档对照：

| 原 M1 阶段记录项 | 当前状态 | 说明 |
|---|---|---|
| 离线仅覆盖浏览过的内容（整本下载未做） | **已解决** | 已支持单本/批量整本下载、持久化队列与离线阅读 |
| 阅读偏好仅为全局 | **已解决** | 已支持按系列覆盖设置、阅读预设与按书双页分组 |
| 数据层错误文案未本地化 | **已解决** | `ShelfFailureKind` 与连接错误已全部接入中英 l10n |
| 中文字体子集未做（中文黄金图为方块） | **已解决** | 测试环境已接入 Noto Sans SC 子集字体并产出中文黄金图（[ADR 0004](adr/0004-cjk-font.md)） |
| Android 音量键全 Activity 消费 | **已解决** | 已改为仅在阅读器激活期间消费（见 [a11y-and-input.md](a11y-and-input.md)） |
| iOS 常亮与音量键翻页 | **仍为平台边界** | 仅 Android 生效，iOS 侧静默降级 |
| 墨水屏对比度/灰度选项 | **仍为已知边界** | 固定高对比度 e-ink 主题，无运行时曲线调节 |
| 应用内亮度遮罩 / 叶证书指纹固定 | **有意设计边界** | 详见 [reader.md](reader.md) 与 [ADR 0001](adr/0001-certificate-trust.md) |

---

## 5. 完整文档索引

### 架构与设计
- [tech-selection.md](tech-selection.md) — 技术选型、子系统设计与工程化原则
- [design-system.md](design-system.md) — 设计 Token、三套主题与玻璃组件规范
- [reader.md](reader.md) — 阅读器分层架构、翻页动画、动态背景与设置持久化
- [offline-cache.md](offline-cache.md) — 离线缓存策略、容量淘汰与多服务器分区
- [tls-and-proxy.md](tls-and-proxy.md) — 反向代理自动升级与自签名/过期证书处理
- [i18n.md](i18n.md) — 国际化 ARB 组织与生成流程
- [a11y-and-input.md](a11y-and-input.md) — 无障碍语义、音量键翻页、平板两栏与高刷适配

### 工程、环境与 API 实测
- [environment-setup.md](environment-setup.md) — Windows 免管理员环境搭建与双机同步
- [ci.md](ci.md) — GitHub Actions 三条流水线、Artifact 获取与排障
- [komga-api-verification.md](komga-api-verification.md) — Komga 1.30.1 REST API 真值实测记录
- [series-queries.md](series-queries.md) — 书架与系列排序/筛选参数真值验证
- [AGENTS.md](../AGENTS.md) — 仓库工程规范、架构不变量与交付流程

### 架构决策记录（ADR）
- [ADR 0001](adr/0001-certificate-trust.md) — TOFU 叶证书指纹固定策略
- [ADR 0002](adr/0002-progress-outbox-and-drift.md) — 进度 Outbox 与 Drift 落盘设计
- [ADR 0003](adr/0003-http-response-cache.md) — 传输层 HTTP 缓存与双库分离
- [ADR 0004](adr/0004-cjk-font.md) — App 系统字体与黄金图 CJK 字体子集
- [ADR 0005](adr/0005-per-series-reader-settings.md) — 按系列阅读设置存储方案
- [ADR 0006](adr/0006-share-page-with-share-plus.md) — 单页分享依赖选型（`share_plus`）
- [ADR 0007](adr/0007-package-info.md) — 运行时版本号读取（`package_info_plus`）

### 规划与复盘档案
- [roadmap.md](roadmap.md) — v1 阶段路线图
- [ui-polish-plan.md](ui-polish-plan.md) · [panels-comparison.md](panels-comparison.md) · [competitor-research-2026-11.md](competitor-research-2026-11.md) — UI 打磨与竞品对比
- [requirements-plan-2026-11.md](requirements-plan-2026-11.md) · [requirements-progress-2026-11.md](requirements-progress-2026-11.md) — 需求收敛清单与进度
- [architecture-review-remediation-plan-2026-11.md](architecture-review-remediation-plan-2026-11.md) — 架构评审与治理修复计划
