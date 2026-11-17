# KomgaNative

Komga 的跨平台客户端（iOS / Android / Android 墨水屏），阅读体验优先。

> 状态：**M1 收尾 / v1 功能补完中**（阶段计划见 [docs/roadmap.md](docs/roadmap.md)）。
> 已完成：M0 骨架（三套主题 + 黄金图闭环）、**服务器连接流程**（密码换 API Key / 直接粘贴 Key / 钥匙串保存 / 路由守卫 / 错误映射）、
> **API 契约验证**（对真实 Komga 1.30.1 实例端到端实测，见 [docs/komga-api-verification.md](docs/komga-api-verification.md)）、
> **反代与 TLS 处理**（`http` 端口自动升级 `https`、证书不受信任时固定指纹 + 用户确认，见 [docs/tls-and-proxy.md](docs/tls-and-proxy.md)）、
> **真实书架**（`/api/v1/series` 分页 + 搜索 + 按库筛选 + 封面 + 下拉刷新 + 空/错态）、
> **系列详情**（`/api/v1/series/{id}` + 书列表 + 点书进阅读器）、
> **阅读器 v2**（单页 / 双页跨页 / 纵向连续三种模式，按系列方向自动选默认值；
> 真实页图、点击翻页、双指缩放、从上次位置继续、进度回写 Komga；墨水屏白底黑字；
> 阅读设置面板：模式/亮度/常亮/跳页，偏好持久化）、
> **进度 outbox**（Drift 落盘、断网不丢、联网/回前台自动补交、多设备按服务端 `lastModified` 对账）、
> **离线缓存**（书架/封面/页图 GET 响应落盘，断网看到上次的内容并显示离线提示条，见 [docs/offline-cache.md](docs/offline-cache.md)）。
> 已在 **Android 模拟器 + 本机 Komga 实例**上跑通"连接 → 书架 → 系列 → 阅读 → 进度"全链路，
> 并在**一台公网 NAS（openresty 反代 + 证书已过期）**上验证了真实登录路径。
> 待完成：阅读器补完（预取/缩略图导航/整本下载）、继续阅读与筛选、多服务器与存储管理、i18n 与中文字体、形态适配（见 roadmap）。

## 文档

| 文档 | 内容 |
|---|---|
| [docs/tech-selection.md](docs/tech-selection.md) | 技术选型：候选评分、技术栈、三大子系统设计、AI Agent 工程化、里程碑与风险 |
| [docs/environment-setup.md](docs/environment-setup.md) | 环境搭建与双机切换：免管理员安装、验收标准、踩坑表 |
| [docs/ci.md](docs/ci.md) | GitHub Actions：概念、免费额度与计费倍率、三条流水线、排障 |
| [docs/komga-api-verification.md](docs/komga-api-verification.md) | Komga API 实测记录：复现步骤、证据表、发现的缺陷、仍未验证项 |
| [docs/series-queries.md](docs/series-queries.md) | 书架排序与阅读状态筛选的参数验证（真实响应顺序） |
| [docs/tls-and-proxy.md](docs/tls-and-proxy.md) | 反代与证书：真实现象（明文 400 / 证书过期）、客户端行为矩阵、复现方式 |
| [docs/reader.md](docs/reader.md) | 阅读器：三层分工、模式规则、设置与持久化的取舍、常亮通道的实现边界 |
| [docs/adr/0001-certificate-trust.md](docs/adr/0001-certificate-trust.md) | ADR：为什么用 TOFU + 固定指纹，而不是"忽略证书" |
| [docs/adr/0002-progress-outbox-and-drift.md](docs/adr/0002-progress-outbox-and-drift.md) | ADR：进度 outbox 与 Drift 落盘（表结构、seq 回执、对账基准） |
| [docs/offline-cache.md](docs/offline-cache.md) | 离线与缓存：能看什么、容量与淘汰、分区、验证 |
| [docs/adr/0003-http-response-cache.md](docs/adr/0003-http-response-cache.md) | ADR：为什么把缓存钩在传输层、为什么与进度库分文件 |
| [docs/roadmap.md](docs/roadmap.md) | 剩余功能分阶段计划（C–I）与验收口径 |
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

当前基线：**369 个测试**（纯 Dart 169 / Flutter 200），**27 张黄金图**覆盖
书架（手机 light / 平板 dark / 1.3 倍字号 / 墨水屏 / 空态 / 错误态 / **离线态**）、系列详情（手机 / 平板 / 墨水屏）、
阅读器（单页 dark+eink、双页 dark+eink、纵向 dark、设置面板 dark+eink）、墨水屏设置（含存储占用）、连接页（light / eink）、
证书面板（手机 / 平板 / 墨水屏）、启动页。

其中 `packages/komga_api` 的 95 个测试里包含**两层真值校验**：
`contract_test.dart` 拿官方 OpenAPI 校验客户端会构造的每个 URL；`fixtures_test.dart` 用真实服务器响应驱动解析层。
反代与证书的异常形态同样用**真实抓包**（`test/fixtures/proxy-400-plain-http.html`）和真实异常类型驱动（`errors_test.dart`）；
离线缓存的回退决策由 11 个用例覆盖（命中/未命中/404/401/5xx/缓存自身故障）。
阅读器的几何（单页适配、双页分组、纵向偏移/页码映射）在 `packages/komga_reader_engine` 里是纯函数，32 个用例表驱动覆盖。

## 连接流程（已可用）

1. 输入服务器地址（支持反代子路径，如 `https://host/komga`）；
2. **Account 模式**：邮箱 + 密码 → 客户端自动调 `POST /api/v2/users/me/api-keys` 创建一把名为
   `KomgaNative` 的 Key → 只把 Key 存进 Keychain/Keystore，**不保存密码**；
3. **API Key 模式**：在 Komga 后台建好 Key 直接粘贴（适合开了双步验证）；
4. 连接失败按类型给不同建议（401 → 检查凭据；网络错误 → 检查地址/同网段；非 Komga 响应 → 检查反代）。

## 书架（已可用）

数据流：`LibraryScreen`（只画状态）← `ShelfController`（分页/搜索/筛选/竞态）← `LibraryRepository`（唯一碰网络的地方）← `KomgaSession`。

- **继续阅读**：书架顶部一行 ondeck（读过没读完的书），读完会自动消失；点击带着系列阅读方向直接进阅读器；
- **排序与筛选**：标题 A-Z/Z-A、最近添加、最近阅读；阅读状态（未读/在读/已读）。
  取值只列已对真实 Komga 1.30.1 验证过的（见 [docs/series-queries.md](docs/series-queries.md)）；
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

### 阅读设置

顶栏右侧按钮打开面板，四项设置都即时生效：

| 设置 | 说明 |
|---|---|
| 阅读模式 | 跟随书 / 单页 / 双页 / 纵向；**持久化**，下次打开新书沿用 |
| 亮度 | 阅读区盖一层黑遮罩（下限 20%，不会全黑），不吃点击，翻页照常 |
| 常亮 | 进阅读器置真、退出置假（Android `FLAG_KEEP_SCREEN_ON`，见 [docs/reader.md](docs/reader.md)） |
| 跳页 | 拖到目标页松手才跳；纵向模式滚到对应偏移 |

偏好存在 secure storage（`komganative.reader.v1`），不是 Drift：几个字段不需要查询能力，
Drift 留给书架/页图缓存与进度 outbox。坏存档一律回默认值。

## 进度：先落盘，再补交

翻页不再直连 PATCH：先写本地 Drift（`local_progress`），再尽力上传。
断网、切后台、服务端 5xx 都不会丢这一页。

- **合并**：同一本书只保留最新一条（翻页很密，堆队列没有意义）；
- **回执**：提交成功要 `seq` 匹配才清空——提交期间又翻页时，新进度必须留下；
- **补交时机**：启动、**会话恢复/重新登录后**、回到前台、下次翻页（真机踩到过"启动时会话还没恢复"的时序坑）；
- **对账**：只信服务端 `lastModified`，不用设备墙钟；`decideSync` 决定"推送/采纳/忽略"，
  采纳时写回本地；服务端把进度删了（标记未读）本地也清空；
- **本地优先展示**：书架与阅读器 resume 都会叠加本地未提交进度，
  所以"断网读完 → 重新打开"看到的是自己读到的那一页，不是服务端的旧值；
- **401/403**：保留队列但本轮停手，重新登录后再补交。

表结构、为什么合一张表、为什么 PATCH 成功后要把服务端基准置空，见
[ADR 0002](docs/adr/0002-progress-outbox-and-drift.md)。

## 离线：看过的东西还能看

缓存钩在 `KomgaSession` 的 GET 上（不是每个 Repository 各写一遍）：成功写盘，
**网络类失败 / 5xx** 才回退；404/401/403 不回退——资源被删或登录失效时要如实报错。
细节与取舍见 [docs/offline-cache.md](docs/offline-cache.md)、[ADR 0003](docs/adr/0003-http-response-cache.md)。

- 缓存什么：系列列表、系列详情、书列表、页列表、页图、封面；
- 容量：图片 256 MB 按 LRU 淘汰；JSON 每服务器 400 条按最久未用裁剪，**不参与字节淘汰**
  （它很小，却是"书能不能打开"的前提）；
- 分区：按服务器 `baseUrl`，多服务器不串数据；查询串进缓存键，搜索/分页互不覆盖；
- 提示：传输层观测到失败就显示「Offline · showing saved content」，任意请求成功（含进度 PATCH）后自动消失；
- **整本下载**：系列详情每本书右侧 ⬇ 按钮，显示进度、可取消、可删除；下载完断网可整本读，
  设置页能看到已下载数量与体积；
- 管理：设置 → Storage 看占用、一键清空（只清缓存，不动进度）。

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
**装的是 release APK 时**，还要确认它带 `INTERNET` 权限（`aapt2 dump permissions app-release.apk`）：
漏了这条权限，系统会拒绝所有 socket，界面只有"无法连接到 xxx"，而同一台手机的浏览器却能打开——
debug 包（模拟器 / `flutter run`）自带这条权限，所以这个坑只在真机 release 包上暴露。
权限声明在 `apps/app/android/app/src/main/AndroidManifest.xml`，由 `test/platform/android_manifest_test.dart` 钉住。

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
| 同一台 NAS 续期证书后 | ✅ 无 `-k` 的严格校验通过（`ssl_verify=0`、返回 401 而非握手失败），不再弹面板——指纹固定只在"证书变了"时才拦 |
| 双页跨页（RTL 系列，3 页真实书） | ✅ 顶栏 `2–3 / 3`；P3 在左、P2 在右（日漫右起） |
| 双页读完写回 | ✅ 服务端 `"page":3,"completed":true`（最后一屏含末页也标完成） |
| 纵向连续 + 滚动跟随页码 | ✅ 滚动后 `2 / 3 → 3 / 3`，并按页写回进度 |
| 墨水屏阅读器 | ✅ 白底黑字（顶栏/底栏/页码同套配色），不再黑底全刷 |
| 阅读设置：亮度 | ✅ 拖到 20% 后整页变暗；**杀进程重启后仍是 20%**（存档生效） |
| 阅读设置：常亮 | ✅ 打开后 `dumpsys window` 出现 `fl=KEEP_SCREEN_ON`，关掉即消失 |
| 进度 outbox：离线翻页 | ✅ 停掉服务端翻到第 4 页 → 杀进程 → 服务端仍是第 3 页 |
| 进度 outbox：冷启动补交 | ✅ 重启 App 后服务端变成 `page:4, completed:true`（`lastModified` 是新时间） |
| 进度 outbox：积压补交 | ✅ 修 bug 前积压的第 2 页，冷启动后被自动补交 |

## 已知边界

- **离线只覆盖"看过的东西"**：没访问过的页断网仍打不开（整本下载属于阶段 D）；
  离线时也不做凭据校验——登录态失效要联网才会发现；
- **常亮只在 Android 生效**：iOS 侧通道没实现（`MissingPluginException` 静默降级为"不常亮"），
  没有 macOS 环境验证，宁可留空也不写没跑过的 `AppDelegate`；
- **亮度是应用内遮罩**，不改系统亮度（那需要新插件），夜里够用但不是系统级调光；
- **阅读偏好是全局的**，不按书记忆（系列的条漫/竖向已由元数据兜住，双页是个人习惯）；
- UI 文案暂为英文：i18n（ARB + 中文字体）之后一次性替换，避免现在把 CJK 字体塞进黄金图。
- 证书信任是**按叶证书指纹固定**：服务器续期后需要再确认一次（有意为之，不是 bug）；
  不做自签名 CA 链校验与双向 TLS。
