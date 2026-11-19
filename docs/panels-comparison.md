# KomgaNative × Panels：功能与 UI 细化对比

> **2026-11-19 复评**：本文基线为 `d0c7a1c`，之后 UI 已换成液态玻璃 dock/标题栏，且仓库已补收藏集/阅读列表、分享、下载管理等。完整的两竞品对比（Panels + Aidoku）与最新差距见
> [competitor-research-2026-11.md](competitor-research-2026-11.md)。本文保留作历史记录；文中“P3 未开始”、
> “无 collection 层”等段落已过时，以新文和代码为准。

> 盘点时间：**2026-11-19**。本仓库基线 `d0c7a1c`；Panels 基线 **3.13.x**（iOS / iPadOS / macOS）。
>
> 范围：只比较与 **Komga 场景**相关的部分。Panels 的本地导入、云盘、内置商店、Panels 账号同步
> 只作为背景，不作为"我们要补"的功能。
>
> 证据：Panels 官方指南 / 官网 / 博客 / 社区开发者回复（链接见 §5）；本仓库代码、测试与黄金图。
> Panels 官方文档几乎不描述具体视觉参数（模糊半径、阴影、字号），所以本文只对**有文字依据**的
> 交互与结构下结论；纯观感一律标「待实机核对」，不编造。

## 0. 结论先行

1. **UI 细化计划本身已经做完**：P0 6/6、P1 7/7、P2 8/8、P3 14/14 全部落地。
   所以"还差哪些"的第一个答案就是 P3 清单（§4），而不是从零再列一遍。
2. **阅读器核心体验已经和 Panels 对齐**：浮层毛玻璃 chrome、卷页（双页还铰接书脊）、
   底部缩略图滑条、单色动态背景、双击缩放、书末"下一本"卡片。
3. **真正的差距是"配置深度"和"内容组织"**：
   Panels 有阅读预设 / 按书配置 / 锁定缩放 / 双页分组修正 / 页滤镜 / 收藏集 / 多选 /
   最近阅读 / 键盘与翻页器 / 分享页；我们这些都没有。
4. **不要照搬 Panels 的 OPDS 路径**。我们是 Komga 原生客户端，在四件事上明显更强：
   流式阅读可连续下一本、列表直接显示服务器进度、按系列阅读方向、进度 outbox 可对账。
   这些是为"像 Panels"而牺牲时最不该动的部分。
5. **纯 UI 细节上，我们缺的不是大特效，而是信息密度与状态表达**：设置页、系列详情、
   书架工具条、阅读器快捷控制、空/加载态的骨架，以及触感反馈的覆盖面。

---

## 1. 我们的 UI 细化进度

### 1.1 计划完成度

| 批次 | 内容 | 状态 | 证据 |
|---|---|---|---|
| P0 设计系统地基 | 拆 `reader_screen`、动效/材质/形状/字体 token、`PressableScale` / `AppHaptics` | 6/6 | [design-system.md](design-system.md) |
| P1 阅读器体验 | chrome 动画 + 沉浸、缩略图滑条、适配、方向、动态背景、双击、书末卡片 | 7/7 | [reader.md](reader.md) |
| P2 书架/详情 | 封面质感、Hero、iOS 转场与大标题、详情重做、长按菜单、Reading Now、视图选项、骨架 | 8/8 | [ui-polish-plan.md](ui-polish-plan.md) |
| P3 长尾 | 预设、按系列记忆、横屏自动双页、锁定缩放、双页修正、分享页、沉浸背景、墨水屏探测、键盘/遥控、隐身、下载管理、收藏集/阅读列表、全局搜索、滤镜（全部完成） | **14/14** | §4 |

### 1.2 P2 缩水已清零

P2-2（继续阅读 → 阅读器 Hero）、P2-3（边缘右滑返回）、P2-7（书籍数量/发行日期排序 +
双指捏合调封面）已在 2026-11-19 补齐，落地记录见 `ui-polish-plan.md`。
其中 P2-3 的返回手势是"边缘手势 + 主题侧滑转场"，不是手指跟手的交互式返回。

### 1.3 P3 状态

P3 的 14 项已全部落地（2026-11-19 收尾）。§4 是下一轮建议，不是 P3 清单；
最新一轮（含 Aidoku）的差距与批次见 [competitor-research-2026-11.md](competitor-research-2026-11.md)。

---

## 2. 功能对比

图例：✅ 对齐 / 🟡 部分 / ❌ 缺 / 🔷 我们更强 / ➖ 不适用 / 🚫 明确不做。

### 2.1 阅读器

| 能力 | Panels 3.13 | KomgaNative | 判断 |
|---|---|---|---|
| 单页 / 双页 / 纵向 | ✅ 三种基础模式免费 [10] | ✅ 单页 / 双页 / 纵向 + 跟随系列 | ✅ |
| 横向连续滚动 | ✅ Continuous + Horizontal [1] | ❌ 只有纵向连续 | 🟡 漫画场景价值低 |
| 自动双页（按屏宽 / 横屏） | ✅ Standard 预设 + "Automatic" [1] | ✅ auto 模式横屏自动双页（P3-3） | ✅ |
| 适配方式 | Fit / Fill / Automatic [1] | contain / cover / fitWidth / fitHeight [reader_prefs.dart](../apps/app/lib/src/data/reader_prefs.dart) | 🟡 无 Automatic |
| 阅读方向 | 全局反转 ⌃R；OPDS 下**不能**按书/系列设 [9][18] | 跟随系列 / LTR / RTL，来自系列元数据 | 🔷 更强 |
| 预设 / 按书配置 | 5 个默认预设，可编辑；当前这本可临时改 [1] | ✅ 预设可保存/应用/删除（P3-1）；✅ 按系列记忆（P3-2） | ✅ |
| 背景 | 黑 / 白 / 动态单色 / 沉浸多色 [1] | 黑 / 白 / 动态单色 / 沉浸双色渐变（P3-7） | ✅ |
| 翻页动画 | Paginated / Continuous / Page curl [1] | 卷页（分页模式）；墨水屏瞬切 | 🟡 无动画选择 |
| 双击缩放 | **未证实**（官方文档未记载） | ✅ 中区双击 2.5×，再双击还原 [reader.md](reader.md) | 不比较 |
| 锁定缩放 | ✅ 放大后横幅可锁 [5] | ✅ 设置开关，翻页保持比例（P3-4） | ✅ |
| 缩略图滑条 | ✅ 底部 carousel [2] | ✅ 按屏分组、懒加载、RTL、拖动触感 | ✅ |
| 缩略图长按 | 分组修正 + 分享 [2] | ✅ 动作面板：分享此页 + 从这一页分组（P3-5/6） | ✅ |
| 双页分组修正 | ✅ "Group from this page on" [2] | ✅ 缩略图网格长按（P3-5，会话内生效） | ✅ 交互一致，未持久化 |
| 页滤镜 | 降噪 / 锐化 / 去边 / 去摩尔纹（Premium）[7] | ✅ 自动去白边（P3-10，纯色边检测）；降噪/锐化未做 | 🟡 |
| 逐格阅读 | Panels View（实验性，Premium）[8] | 🚫 | 🚫 |
| Live Text / 翻译 | 文本与主体检测、端上翻译（Premium）[10] | 🚫 | 🚫 |
| 隐身模式 | 会话隐藏，不进 Reading Now（Premium）[6] | ✅ 本次完全不回写进度（P3-12，语义不同） | ✅ 语义不同 |
| 书末下一本 | ✅ 但 **OPDS 流式不可用** [3] | ✅ 系列内下一本，流式可用 [reader.md](reader.md) | 🔷 更强 |
| 进度写回 | 乐观写入（开发者称失败无恢复）；列表不显示服务器进度 [17] | outbox + 对账；列表叠加本地进度 | 🔷 更强 |
| 阅读会话 / 统计 | 每本记录阅读时长 + 默认预设 [4] | ❌ 只有进度 | ❌ 新-4 |
| 目录 | ✅ TOC（免费）[10] | 🟡 系列书列表在详情页，阅读器内不能换书 | 🟡 |
| 键盘 / 翻页器 / 手柄 | ✅ 键盘、蓝牙翻页器、手柄、Switch Control [9] | ✅ 方向键/PageUp/PageDown/空格/Esc（P3-11）；音量键 Android | ✅ |
| 分享 / 保存页 | ✅ 缩略图长按分享；⌘P 保存 [2][9] | ✅ 长按缩略图分享（P3-6，系统面板可存储） | ✅ |
| 墨水屏 | ❌（iOS 无） | ✅ e-ink 主题 + 白底黑字 + 厂商自动探测（P3-14） | 🔷 独有 |

> 付费差异：Panels 把 Fill screen / Page curl / 动态背景 / Panels View / 页滤镜等放在 Premium，
> 连接 OPDS（含 Komga）本身也属 Premium [10]；本仓库这些能力全部免费。

### 2.2 书架、组织与搜索

| 能力 | Panels 3.13 | KomgaNative | 判断 |
|---|---|---|---|
| 库 / 系列 / 书层级 | 库 = 文件夹；文件夹 = collections [11] | 书架 = 系列网格 + 库筛选 chips；无 collection 层 | 🟡 少一层组织 |
| 收藏集 | ✅ 免费；OPDS 下只读，不能在服务器侧新建 [11][12][20] | ✅ 只读列表 + 详情（P3-8） | ✅ |
| 阅读列表 | 未证实 | ✅ 只读列表 + 详情（P3-8，真实 fixture） | ✅ |
| 网格 / 列表 | ✅ ⌘1 / ⌘2 [9] | ✅ 网格 / 列表 | ✅ |
| 封面大小 | ✅ ⌘+ / ⌘- [9] | ✅ 小 / 中 / 大三档 | ✅ |
| 排序 | 8 种：Manual / Alphabetically / Creation / File size / Length / Type / Reading progress / Last read [9] | 6 种：标题升 / 标题降 / 最近添加 / 最近阅读 / 书籍数量 / 发行日期 [queries.dart](../packages/komga_domain/lib/src/queries.dart) | 🟡 缺手工/文件大小/类型/长度等；需先确认 Komga 支持 |
| 筛选 | 未证实 | ✅ 阅读状态 3 档 + 按库 | 不比较 |
| 搜索 | 库内免费；跨多库付费；独立 Search tab [9][10] | ✅ 独立 Search tab：系列 + 书，服务端 Lucene 匹配（P3-9） | ✅ |
| 多选 / 批量 | ✅ 全选、标记、删除、移动、分享 [9] | ❌ | ❌ 新-3 |
| 标记已读 / 未读 | ✅ 单本 + 批量 [17] | ✅ 单本 + 整系列 | ✅ |
| 收藏库位置（Favorite locations） | ✅（Premium）[10] | ✅ 服务器列表（等价） | ✅ |
| 最近阅读 | ✅ Recently read [10] | 🟡 Reading Now 只有 ondeck + 最近添加 + 按库 | ❌ 新-4 |
| 最近导入 | ✅（Premium）[10] | 🟡 最近添加（系列级） | 🟡 |
| Reading Now | ✅ 由阅读会话/时长驱动 [4] | ✅ ondeck 大卡 + 最近添加 + 按库货架 | 🟡 无时长/历史 |
| 下载 | ✅ 整系列下载 + Downloads tab [12][10] | ✅ 单本下载 + 管理页/串行队列（P3-13）；整系列仍缺（新-5） | 🟡 新-5 |
| 离线 | ✅ 流式或下载 [13] | ✅ HTTP 缓存 + 整本下载 | ✅ |
| 空间管理 | ✅（Premium）[10] | 🟡 设置页占用 + 清空 | 🟡 |
| 内容锁 | ✅ 密码 / Face ID，文件系统隐藏（Premium）[10] | ❌ | 🚫 / 视需求 |
| 多用户 | ✅ 按 Komga 账号权限 [12] | 🟡 每服务器一条凭据，换用户要重新连 | 🟡 |
| 导入 / 云盘 / 商店 | ✅ | 🚫 / ➖ | 🚫 |

### 2.3 平台与连接

| 能力 | Panels 3.13 | KomgaNative | 判断 |
|---|---|---|---|
| 平台 | iPhone / iPad / Mac [21] | iOS / Android / Android 墨水屏 | 不同定位 |
| Android | ❌ 官方明确未承诺 [14] | ✅ | 🔷 独有 |
| 墨水屏 | ❌ | ✅ | 🔷 独有 |
| 服务器 | OPDS：Komga / Kavita / Calibre / Ubooquity（Premium）[13] | Komga REST 原生 | 我们更深，Panels 更广 |
| 自签名证书 | ✅ 按服务器信任 [12] | ✅ TOFU + 固定指纹 [tls-and-proxy.md](tls-and-proxy.md) | ✅ |
| 反代 / 子路径 | 🟡 用 `/opds` URL | ✅ 子路径 + `http`→`https` 自动升级 | 🔷 更强 |
| 多服务器 | ✅ 多个 OPDS 库（Premium）[10] | ✅ 多服务器切换/删除 | ✅ |
| 进度真值 | Panels 会话为准，乐观写回 [17] | Komga 服务端 + 本地 outbox 对账 | 🔷 更强 |
| 账号 | Panels 账号（Google/Apple，可选）[4] | 无账号，只用 Komga API Key | 不同 |
| 主题 | 多套主题 + 图标（部分付费）[10] | Light / Dark / E-ink | 🟡 |
| 语言 | 11 种 [21] | English / 中文；数据层文案仍硬编码 | 🟡 [i18n.md](i18n.md) |
| 键盘快捷键 | ✅ 全 App + 阅读器 [9] | ❌ | ❌ P3-11 |
| 无障碍 | Switch Control / Voice Control [16] | 语义树 + Android 音量键；无人工走读 | 🟡 [a11y-and-input.md](a11y-and-input.md) |
| 折叠屏 / iPhone Duo | ✅ 3.13.10 [15] | ❓ Flutter 自适应，未验证 | 视需求 |

### 2.4 我们领先、且不应为了"像 Panels"而削弱的能力

| 能力 | 我们的实现 | Panels 在 Komga/OPDS 下的限制 |
|---|---|---|
| 流式阅读连续下一本 | 系列书列表 + `pushReplacement`（[reader.md](reader.md)） | Continue reading 在 OPDS 流式下**不可用** [3] |
| 列表直接显示服务器进度 | 书架/详情叠加服务端 + 本地 outbox 进度 | 列表只读 OPDS feed，不逐本查进度 [17] |
| 按系列阅读方向 | 从 Komga `metadata.readingDirection` 派生点击区/箭头/卷页 | OPDS 不表达方向，只能全局默认 [18] |
| 进度不丢 | Drift outbox + seq 回执 + `lastModified` 对账（ADR 0002） | 乐观写入，失败无恢复，Panels 会话才是真值 [17] |
| 离线缓存 | HTTP 层分区缓存 + 整本下载（ADR 0003） | 只有"下载到本地"这一条路径 |
| 墨水屏 | 零动画/零阴影/纯黑白 + 阅读器白底 | 无 |
| Android | 原生客户端 + 音量键翻页 | 未承诺 Android [14] |
| 双页卷页 | 铰接书脊、纸背是下一屏那页（`page_curl.frag`） | 有 Page curl，但无公开的双页书脊模型说明 |

---

## 3. UI 细节对比

### 3.1 有官方依据的交互 / 结构差异

| 维度 | Panels（依据） | KomgaNative（代码/基线） | 差距 |
|---|---|---|---|
| 主导航 | Library / Reading Now / **Search** / Settings 四个 tab；iPad 有侧边栏 [9][21] | 手机：悬浮玻璃胶囊（正在读 / 书架 / 设置）+ 右侧搜索圆球（iOS 26 液态玻璃）；平板用 `NavigationRail` | ✅ |
| 库层级 | Content → library → collections [11] | 书架 = 系列网格 + 库 chips | 少一层"库/收藏集"浏览 |
| 阅读器 chrome | `"..."` 菜单（Configure reader / Image filters）+ 底部 carousel + Live Text 按钮 [1][2][8] | 顶栏：返回 / 书名 / 页码 / 网格 / 设置；底栏箭头 + 缩略图滑条 | 信息架构不同；少配置/滤镜入口 |
| 阅读设置 | Presets 列表 + 完整配置页（Page transition / Scroll direction / Pages / Fitting / Background）[1] | 底部面板：预设 / 按系列 / 模式 / 适配 / 方向 / 背景 / 亮度 / 常亮 / 锁定缩放 / 跳页 | 结构接近，缺按书临时配置 |
| 缩略图 | 长按可分组修正、分享 [2] | 点击跳页；拖动触感；网格面板看全部 | 缺长按动作 |
| 动态背景 | 单色 + Immersive 多色 [1] | 单色 + 450ms 交叉渐变 [reader.md](reader.md) | 缺多色 |
| 缩放 | Lock zoom 横幅，点一下锁定 [5] | 双击 2.5×；设置里"锁定缩放"翻页保持比例（P3-4） | 对齐功能，交互形态不同 |
| 平板 | iPad 侧边栏；设置挂在头像上 [21] | NavigationRail；设置是 tab；系列详情两栏 | 结构接近，缺书架两栏/分屏 |
| 主题 | 多主题 + 自定义图标（Premium）[10] | Light / Dark / E-ink | 缺主题体系 |
| 语言 | 11 种 [21] | English / 中文；数据层硬编码 | 缺 |
| 输入 | 键盘 / 蓝牙翻页器 / 手柄 / Switch Control [9] | Android 音量键 | 缺 |
| 即时反馈 | 锁定缩放横幅、Live Text 按钮等 | 触感只有 3 处调用；无横幅类反馈 | 缺 |

> 视觉层的"毛玻璃厚度、阴影、字号、转场曲线"：Panels 官方没有文字描述，本仓库也没有
> iPhone/iPad 实机截图。**这一块不做打分**，见 §3.3。

### 3.2 我们自己的 UI 粗糙点（本轮盘点）

这些不依赖 Panels，是从代码和黄金图里看出来的：

| 位置 | 现象 | 证据 | 建议 |
|---|---|---|---|
| 设置页 | `letterSpacing: 1.2` 是魔法数字；版本号硬编码 `0.1.0 (v1)`；没有下载管理/隐私/诊断入口；`Clear` 只是文字按钮 | `settings_screen.dart:176,262` | 收进 token；版本读 `package_info`；补 About / Storage 子页 |
| Reading Now | 货架没有骨架：数据没回来时整块消失再出现；继续阅读主按钮在浅色底上偏灰 | `reading_now_screen.dart`、`reading_now@phone_light.png` | 加骨架/`PhaseFade`；核对按钮对比度 |
| 系列详情 | 头部背景是 72%→94% surface 遮罩，模糊封面被压得很淡；短简介也显示"Show more"；标签只取 4 个且无 `+N` | `series_header.dart:150-155,251,316` | 调渐变；按行数决定按钮；标签溢出提示 |
| 书架 | 顶栏 4 个图标（排序/筛选/视图/搜索）在窄屏偏挤；筛选生效无 badge/计数；无多选 | `library_screen.dart:85-94` | 合并 overflow 或加 badge；长按多选 |
| 阅读器 chrome | 模式图标语义弱；亮度/背景要进设置面板；没有页码进度条 | `reader_chrome.dart:186`、`reader@phone_dark.png` | 加 quick actions + 顶部进度条 |
| 阅读设置 | 单列 radio 很长，小屏要滚很久；没有"重置"；预设/按系列已经补上 | `reader_settings_sheet.dart` | 分组折叠/重置 |
| 下载 | 只有书行右侧按钮；无管理页/队列/系列下载；下载完成无全局提示 | `download_service.dart`、`book_download_button.dart` | 新-5 |
| 触感 | 只有缩略图拖动、两个长按菜单；翻页、双击、标记已读成功都没有反馈 | `grep AppHaptics`（4 处，含总开关） | 新-7 |
| 转场 | 边缘右滑返回已补（24px 手势条，非跟手）；阅读器进入/退出无自定义转场 | `edge_swipe_back.dart`、P2-3 进度 | 跟手动画仍是缺口 |
| 平板 | 书架没有两栏/分屏；阅读器双页要手动选 | `adaptive_shell.dart`、`reader_prefs.dart` | 新-9 / P3-3 |
| 文案 / 字体 | 数据层错误文案不随语言切换；中文金图只覆盖连接页 | [i18n.md](i18n.md) | 新-10 |
| 无障碍 | 语义测试只到语义树；无 TalkBack / VoiceOver 人工走查；Dynamic Type 只有 1.3× 两张 | [a11y-and-input.md](a11y-and-input.md) | 新-11 |

### 3.3 视觉质感对照的现状

Panels 的"高级感"在 `ui-polish-plan.md` 里总结为三点：克制、连续性、阅读器里的贴心细节。
我们的 P0–P2 已经把**可工程化的部分**补上了（token、毛玻璃、squircle 封面、Hero、
iOS 转场、大标题、骨架微光、卷页）。目前缺的是两件事：

1. **实机参照**：`docs/assets/panels-ref/` 目录还不存在。要判断"我们的头部遮罩是不是太灰""按钮对比度够不够"，
   必须在 iPhone/iPad 上截 Panels 的对应页面存进来，否则只是印象之争。
2. **信息密度**：Panels 的界面元素更少，但每个元素承担的信息更多（预设、阅读会话、最近阅读）。
   我们目前是"元素少 + 信息也少"，所以看起来更空。这一条靠 §4 的新-1/2/4/6 解决，不是靠加装饰。

---

## 4. 还差什么：优先级与批次建议

> 成本是粗估：S ≈ 半天–1 天，M ≈ 2–3 天，L ≈ 一周以上（以当前单人 + Agent 的节奏）。
> 所有 UI 类改动仍要过 `dart run tool/ci.dart check`、补黄金图，并装到模拟器实际走查。

### 4.1 第 6 批：低成本、高感知（建议先做）

| 编号 | 内容 | 为什么现在做 | 成本 | 依赖 |
|---|---|---|---|---|
| 新-1 | 设置页信息架构（版本来源、下载管理、隐私/诊断） | 设置页是"关于这个 App"的门面，现在太像占位 | S | 无 |
| 新-7 | 触感补全（翻页/双击/标记已读成功） | 已有 `AppHaptics` 与总开关，只差调用点 | S | 无 |
| 新-8 | 视觉修正（Reading Now 对比度、系列头部遮罩、标签溢出、简介按钮） | 黄金图里能直接看到；不改结构 | S | 需重生成对应基线 |
| 新-2 | 系列书列表排序/筛选（已读、卷号、添加时间） | 长系列找"下一本未读"很费劲 | M | 新查询参数需真实 Komga 验证 |
| 新-5 | 系列级"下载全部" | 管理页与串行队列已由 P3-13 做完；只差一次把系列内未下载的书入队 | S–M | 下载队列 |

### 4.2 第 7 批：中等工程，明显对标 Panels

| 编号 | 内容 | 为什么 | 成本 |
|---|---|---|---|
| 新-3 | 书架多选与批量操作 | 补"标记/下载/删缓存"的效率 | M |
| 新-4 | 最近阅读 / 阅读历史 | Reading Now 现在只有 ondeck + 最近添加 | M |
| 新-6 | 阅读器快捷控制（亮度/背景/方向 + 页码进度条） | 少一次进面板；对标 Panels 的即时反馈 | S–M |
| 新-9 | 平板书架/书列表两栏 | iPad 上目前只是"放大的手机 + 侧栏" | M–L |

### 4.3 第 8 批 / 视需求

| 编号 | 内容 | 备注 |
|---|---|---|
| 新-10 | 数据层文案 i18n + 中文黄金图扩展 | 见 [i18n.md](i18n.md) |
| 新-11 | TalkBack / VoiceOver 人工走查 + Dynamic Type | 验证项，不是新功能 |
| 新-12 | iOS 平台缺口：常亮、音量键、ProMotion | 没有 macOS 环境，需真机验证 |

### 4.4 明确不做

| 需求 | 理由 |
|---|---|
| 逐格阅读（Panels View / Dual View） | 需要 ML 模型；Panels 打磨多年仍标实验性；与 Komga 场景无关 |
| Live Text / 实时翻译 / 主体抠图 | 依赖平台 ML，只有 iOS 有 |
| 内容锁（Face ID） | 与自建服务器场景关系弱；Komga 用账号权限 |
| 本地导入、网盘、内置商店 | 不在 Komga 客户端定位内 |
| 可替换 App 图标、付费主题 | 收益低 |
| Panels 账号同步 | Komga 服务端就是真值源，多一层账号只会造成两份进度 |

---

## 5. 来源

**Panels 官方**

1. [Reader presets and configurations](https://guides.panels.app/read-content/reader-configurations)
2. [Page thumbnails and double page grouping](https://guides.panels.app/read-content/double-page-grouping)
3. [Continue reading](https://guides.panels.app/read-content/continue-reading)
4. [Reading progress and sync](https://guides.panels.app/read-content/reading-sessions)
5. [Lock zoom](https://guides.panels.app/read-content/lock-zoom)
6. [Incognito mode](https://guides.panels.app/read-content/incognito-mode)
7. [Image filters](https://guides.panels.app/read-content/image-filters)
8. [Panels View](https://guides.panels.app/read-content/panels-view)
9. [Keyboard shortcuts](https://guides.panels.app/remotes-and-controllers/keyboard-shortcuts)
10. [What is Panels Premium](https://guides.panels.app/premium/what-is-panels-premium)
11. [How libraries work](https://guides.panels.app/libraries/how-libraries-work)
12. [Panels for Komga](https://www.panels.app/komga-ios-app)
13. [OPDS client](https://www.panels.app/opds-client)
14. [Panels on Android](https://www.panels.app/android)
15. [Panels now fully supports iPhone Duo（含 Panels 4 预告）](https://www.panels.app/blog/iphoneduo)
16. [Accessibility options](https://guides.panels.app/remotes-and-controllers/accessibility-options)

**Panels 社区（开发者回复，证据强度低于官方文档）**

17. [Komga reading progress sync：乐观写入、列表不显示服务器进度](https://community.panels.app/t/komga-reading-progress-sync/1714)
18. [OPDS 无法按书设置阅读方向](https://community.panels.app/t/is-it-possible-to-set-the-reading-direction-on-multiple-comics-on-opds/2428)
19. [流式 OPDS 下无法推导"下一本"](https://community.panels.app/t/suggestion-auto-open-next-in-library/1774/19)
20. [OPDS 下收藏集只读（collection 缩略图讨论）](https://community.panels.app/t/info-request-opds-collection-thumbnails/2536)

**产品页**

21. [App Store 商品数据（含版本说明与语言列表）](https://itunes.apple.com/lookup?id=1236567663&country=us)

**本仓库**

- [ui-polish-plan.md](ui-polish-plan.md)：P0–P3 的原始需求、落地记录与偏差
- [design-system.md](design-system.md)：token 与组件
- [reader.md](reader.md)：阅读器行为、手势、预取、卷页
- [a11y-and-input.md](a11y-and-input.md)：语义、音量键、平板两栏、墨水屏边界
- [i18n.md](i18n.md)：语言设置与"数据层文案未本地化"的边界
- [series-queries.md](series-queries.md)：排序/阅读状态的真实服务端验证

> 维护提示：Panels 的版本与功能会变（Panels 4 已预告但截至 2026-11 尚未发布）。
> 更新本文时请先改 §0 的结论，再改表格；不要把"未发布"的功能算进当前差距。
