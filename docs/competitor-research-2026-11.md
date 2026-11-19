# KomgaNative × Panels × Aidoku：2026-11 竞品与差距全面调研

> **盘点时间**：2026-11-19。
> **本仓库基线**：HEAD `bffa164`（含 2026-11-19 的系列详情去标题、玻璃菜单阴影修正）。
> **Panels 基线**：**3.13.11**（2026-11-11，App Store 美区）。Panels 4 截至本文尚未发布，不计入现状。
> **Aidoku 基线**：**v0.9 (build 4)**（2026-10-16，GitHub Releases）；iOS/iPadOS 15+、macOS Catalyst；GPL-3.0。
> **范围**：只比较与 **Komga 场景**相关的部分。本地导入、内置商店、WASM 图源生态、Panels 账号同步只作为背景，不作为“我们要补”的功能。
> **证据**：官方指南 / 仓库源码 / App Store 与官网截图；本仓库代码、测试与黄金图。纯观感结论标「主观」，无法从代码证明的标「未核实」。

---

## 0. 结论先行

1. **阅读核心已经不比 Panels 差**：浮层 chrome、卷页（双页还有书脊）、预设、按系列记忆、锁定缩放、双击缩放、双页分组修正、隐身模式、书末下一本，这些 P1–P3 的能力都在，且部分（按系列方向、流式下一本、进度 outbox）是 Panels 在 OPDS 下结构上做不到的。
2. **真正的差距在三件事：阅读器“仪表盘”、书架“运营能力”、阅读“时间维度”。**
   - 仪表盘：页码滑杆 / 剩余页数、目录、快捷设置、点击区、自动滚动。
   - 运营：多选批量、系列级下载全部、筛选组合、置顶、搜索历史/ facets。
   - 时间维度：阅读历史、阅读时长、统计。Panels 和 Aidoku 都有 session；我们只有“读到第几页”。
3. **Aidoku 是功能广度标杆，不是 UI 标杆**：内置 Komga/Kavita/Suwayomi/本地四个 source，41 个本地化目录，History/Insights、8 种排序、丰富筛选、下载队列、备份、通知。但它把 Komga 降格为“一个 source”，没有服务端收藏集/阅读列表，进度靠本地 CoreData + Komga tracker，不是服务端权威 + outbox。
4. **Panels 是体验标杆，不是功能清单**：它的“高级感”来自克制的层级、内容优先、每本书的会话与预设；Panels View / Live Text / 页滤镜属于“可以欣赏但不必追”的深水区。
5. **我们最该补的不是大特效，而是信息密度与状态表达**：继续阅读卡没有系列名、系列书行没有页码进度、搜索空态只有一行提示、收藏集只有文字行、设置页只有四组。竞品的共同点是“界面元素更少，但每个元素承担的信息更多”。
6. **我们自己的实现还有 6 个会直接打脸的坑**：自动探测到墨水屏但阅读器仍黑底、主题/墨水屏/书架视图不持久化、从搜索/阅读列表进阅读器丢系列方向、预设应用漏还原锁定缩放/去白边、下载队列只在内存、正在读加载中先闪“空态”。这些不修，谈对标没有意义。
7. **不能为了“像 Panels”牺牲的四件事**：服务端收藏集/阅读列表、进度 outbox + 对账、按系列完整配置、Android/墨水屏。这四件是 Komga 原生客户端的立身之本。

> **实施计划**：45 项需求的优先级、估时、验收与迭代排期见
> [requirements-plan-2026-11.md](requirements-plan-2026-11.md)。

---

## 1. 三家现在分别是什么

| 维度 | Panels 3.13.11 | Aidoku v0.9 (4) | KomgaNative（我们） |
|---|---|---|---|
| 定位 | 商业 iOS 漫画阅读器，设计驱动，本地 + OPDS | 免费开源 iOS 漫画阅读器，source 聚合器 | Komga 原生客户端，阅读体验 + 自建库场景 |
| 平台 | iPhone / iPad / Mac | iPhone / iPad / Mac（Catalyst） | iOS / Android / Android 墨水屏 |
| 内容来源 | 本地文件、iCloud/网盘、OPDS（Komga/Kavita 等）、商店 | 内置 Komga/Kavita/Suwayomi/本地；WASM 外部图源 | 只连 Komga REST |
| Komga 接入 | OPDS，Premium；进度用 Komga 私有 API 回写 | 内置 source，basic auth + mirror；Komga tracker 回写进度 | 原生 REST；服务端为真值 |
| 收费/分发 | 免费下载，Premium 订阅/买断；App Store | 免费；无 App Store，TestFlight/AltStore/ipa | 免费；自建/侧载，未上架 |
| 最新版本 | 3.13.11（2026-11-11） | v0.9-4（2026-10-16） | `ba7cb05` + 本地改动 |
| 一句话 | 把“读一本漫画”做到最舒服 | 把“管理很多漫画”做到最全 | 把“自己的 Komga”接得最深 |

**对比较的含义**：不要拿 Panels 的功能清单逐项打勾，也不要拿 Aidoku 的 source 生态当路线图。对标顺序应该是：

1. **Panels**：层级、留白、内容优先、会话/预设的“质感”。
2. **Aidoku**：阅读器可操作性、书架批量操作、历史/统计、设置深度。
3. **我们**：服务端语义、离线/进度正确性、Android/墨水屏差异化。

---

## 2. 功能差距总表

图例：✅ 对齐 / 🟡 部分 / ❌ 缺 / 🔷 我们更强 / ➖ 不适用 / 🚫 明确不做。

### 2.1 书架、组织与发现

| 能力 | Panels 3.13.11 | Aidoku v0.9 | 我们 | 判断 |
|---|---|---|---|---|
| 库 / 系列 / 书层级 | 文件夹即 collection，库=本地/云/OPDS | source → 系列 → 章节；本地 categories | 书架=系列网格 + 库 chips；收藏集/阅读列表独立 | 🟡 我们少“本地分组” |
| 收藏集 / 阅读列表 | 本地文件夹；OPDS 下只读 | 本地 categories / filter groups；源码未见服务端收藏集入口 | ✅ 服务端收藏集 + 阅读列表（只读） | 🔷 服务端原生；🟡 不能建/改 |
| 网格 / 列表 | ✅ 网格/列表，可自定义外观 | ✅ 网格/列表，行数 1–15 | ✅ 网格/列表 + 3 档封面 + 双指捏合 | ✅ |
| 排序 | 8 种（手动/字母/创建/大小/长度/类型/进度/最近读） | 8 种（标题/最近读/最近打开/最近更新/添加/最新章/未读章/总章） | 6 种（标题升/降、最近添加、最近阅读、书籍数、发行日期） | 🟡 缺“进度/未读章/最近打开” |
| 筛选 | 自定义库；统一筛选器未查到 | 阅读状态/类型/分类/语言/标签/出版商/年龄分级 + 保存筛选组 | 阅读状态 3 档 + 按库 | 🟡 缺标签/作者/类型/保存组合 |
| 多选 / 批量 | ✅ 全选、批量标记、移动、分享 | ✅ 两指拖拽多选、批量标记/下载 | ❌ 只有单项长按菜单 | ❌ 共同差距 |
| 标记已读/未读 | ✅ 单本 + 批量 | ✅ 单章/全部/“之前所有章” | ✅ 单本 + 整系列 | ✅ 基本对齐 |
| 置顶 / 收藏 | ✅ Favorite locations（Premium） | ✅ pin 未读/有更新 | ❌ | ❌ 低成本可补 |
| 继续阅读 / 最近 | ✅ Reading Now 由 session 驱动 | ✅ Keep Reading + Recently Added | ✅ ondeck 大卡 + 最近添加 + 按库 | ✅ 形态对齐，信息更少 |
| 阅读历史 | 有 session，未查到独立 History 页 | ✅ 独立 History tab（按天分组、搜索、清空、锁） | ❌ | ❌ vs Aidoku |
| 阅读统计 | 3.13 无统计页；4.0 预告 insights | ✅ Insights：连续天数、热力图、章节统计 | ❌ | ❌ vs Aidoku |
| 更新检查 / 新章通知 | OPDS 下无 | ✅ 间隔、跳过规则、后台刷新、通知 | ❌ | ❌ 视需求 |
| 内容锁 | ✅ 密码/Face ID（Premium） | ✅ 书库/历史锁 | ❌ | ➖ 自建库场景弱 |
| 备份 / 恢复 | iCloud/账号同步 | ✅ `.aib` 单文件备份/恢复 | ❌ 只依赖服务端 | ❌ 本地预设/覆盖会丢 |
| 本地化 | 12 种（App Store 列表） | **41 个本地化目录** | English / 中文 2 种 | ❌ 差距明显 |

### 2.2 阅读器

| 能力 | Panels 3.13.11 | Aidoku v0.9 | 我们 | 判断 |
|---|---|---|---|---|
| 阅读模式 | 单页/双页/纵向/横向/逐格 | RTL/LTR/纵向/webtoon/带间隙连续 + Automatic | 单页/双页/纵向 + auto 横屏双页 | 🟡 缺横向连续/webtoon 连续 |
| 适配 | Fit / Fill / Automatic | 源码未见用户可选 fit（固定适应屏幕） | contain/cover/fitWidth/fitHeight | 🔷 比 Aidoku 强；🟡 缺 Automatic |
| 阅读方向 | OPDS 下只能全局反转，不能按书写回 | 按 manga 记忆 + 自动读取 Komga `readingDirection` | 跟随系列 + 按系列覆盖 | ✅ 与 Aidoku 对齐；🔷 强于 Panels |
| 预设 / 按书配置 | 5 个预设 + 当前书临时改 | 全局 + 每本 manga 的阅读模式 | 预设 + 按系列完整覆盖 | 🔷 我们的覆盖粒度更细 |
| 锁定缩放 | ✅ 放大后横幅锁定 | 源码未见锁定项；可关双击 | ✅ 设置开关 + 翻页保持 | 🔷 |
| 双击缩放 | 官方未记载（未证实） | ✅ 可关 | ✅ 中区 2.5× | ✅ |
| 页码滑杆 / 剩余页 | 缩略图 + “Page 12 of 26” | ✅ 滑杆 + “18 of 211 / 193 pages left” | ❌ 只有顶/底页码文字 | ❌ 共同差距 |
| 缩略图 | ✅ 底部 carousel，长按分组/分享 | ❌ 无缩略图条（用滑杆/章节列表） | ✅ 按屏分组、懒加载、RTL、长按分享/分组 | ✅/🔷 |
| 双页分组修正 | ✅ 长按缩略图“从这页起分组” | ✅ page offset / split wide images | ✅ 会话内修正，不持久化 | 🟡 缺持久化 |
| 目录 / 阅读器内换章 | ✅ TOC | ✅ 章节列表 | ❌ 只能退出到系列 | ❌ 共同差距 |
| 翻页动画 | Paginated / Continuous / Page curl | 开关（animate transitions） | 卷页/平移/瞬切；400ms 硬编码 | ✅/🟡 缺选择 |
| 背景 / 亮度 | 黑/白/动态/沉浸；无独立亮度（未查到） | system/auto/white/black；源码未见应用内亮度 | 黑/白/动态/沉浸 + 应用内亮度遮罩 | 🔷 |
| 点击区 | 键盘/翻页器/手柄；点击区配置未查到 | ✅ 5 种预设 + 反转 + 可关双击 | 固定左 1/3、中 1/3、右 1/3 | ❌ vs Aidoku |
| 自动滚动 / 无限滚动 | 连续模式；无自动滚动 | ✅ webtoon 自动滚动 + 速度/停靠 + 无限滚动 | ❌ | ❌ vs Aidoku |
| 页滤镜 | 降噪/锐化/去边/去摩尔纹（Premium） | 裁边/降采样/超分（实验） | 自动去白边 | 🟡 |
| Live Text / OCR / 翻译 | ✅（Premium） | ✅ Live Text + 词典/OCR（iOS 18+） | ❌ | 🚫 不优先 |
| 逐格阅读 | ✅ Panels View（Premium/实验） | ❌ | ❌ | 🚫 |
| 隐身模式 | ✅ 会话隐藏 | ✅ 全局开关 | ✅ 不回写进度 | ✅ 语义不同 |
| 书末下一本 | OPDS 流式不可用 | 章节列表切下一章 | ✅ 流式下一本 | 🔷 vs Panels |
| 墨水屏 | ❌ | ❌ | ✅ 白底黑字 + 零动画 + 自动探测 | 🔷 独有 |
| 键盘 / 翻页器 / 音量键 | ✅ 键盘/翻页器/手柄 | ✅ 键盘 | 🟡 阅读器内键盘 + Android 音量键 | 🟡 缺全局/手柄 |

### 2.3 搜索、下载与离线

| 能力 | Panels 3.13.11 | Aidoku v0.9 | 我们 | 判断 |
|---|---|---|---|---|
| 全局搜索 | ✅ 本库免费，跨库 Premium | ✅ 多 source 聚合 | ✅ 系列 + 书，服务端 Lucene | ✅ 基本对齐 |
| 搜索历史 | 未查到 | ✅ 最近搜索、清空、滑动删除 | ❌ | ❌ vs Aidoku |
| 搜索筛选 | 库范围 | ✅ 类型/状态/标签/出版商/语言/年龄分级 | ❌ | ❌ |
| 分页 / 加载更多 | ✅ | ✅ | ❌ 固定 20 条，静默截断 | ❌ |
| 单本下载 | ✅ 下载/流式 | ✅ | ✅ 进度/取消/删除/管理页 | ✅ |
| 系列级下载 | OPDS 批量不支持 | ✅ 全部/未读 N 章/多选 | ❌ | ❌ vs Aidoku |
| 下载队列 | ✅ Downloads | ✅ 队列、失败页重试、后台 | 🟡 串行队列仅在内存 | 🟡 |
| 仅 Wi-Fi / 读完删除 / 压缩 / 并行 | 未查到 | ✅ 全部 | ❌ | ❌ |
| 离线书架 | 下载内容 + 本地库 | 本地 CoreData + 下载 | ✅ HTTP 缓存 + 离线提示 + 下载 | ✅/🔷 |
| 断网冷启动 | 本地库可用 | 本地库可用 | ✅ 缓存书架/封面/页图 | ✅ |

### 2.4 进度、设置与平台

| 能力 | Panels 3.13.11 | Aidoku v0.9 | 我们 | 判断 |
|---|---|---|---|---|
| 进度真值 | 会话/乐观写回 | 本地 CoreData + Komga tracker | 服务端 + Drift outbox + `lastModified` 对账 | 🔷 |
| 列表显示服务端进度 | ❌ 只读 OPDS feed | ✅ 章节行（tracker）；书架网格未核实 | 🟡 只有继续阅读卡；书行不显示页码 | 🟡 |
| 跨设备 | Panels 账号 / iCloud | iCloud（实验性，长期不稳） | Komga 服务端 | 🔷 |
| 阅读会话 / 时长 | ✅ 每本记录时长 + 默认预设 | ✅ Insights 统计 | ❌ | ❌ |
| 设置深度 | 多主题/预设/下载/空间/隐私/购买 | 极深（Appearance/Library/Reader/Dictionary/Tracking/iCloud/Advanced/Downloads/Backups） | 4 组：外观/服务器/存储/关于 | ❌ |
| 主题 | 多套主题 + 图标（部分 Premium） | Light/Dark/System + 布局 | Light/Dark/E-ink | 🟡 数量少，E-ink 独有 |
| 语言 | 12 种 | 41 个本地化目录 | 2 种 | ❌ |
| 无障碍 | Switch/Voice Control | 系统级 | 语义树 + 48pt；无人工走查 | 🟡 |
| 动态字体 | 系统级 | 系统级 | 只有 1.3× 两张金图 | 🟡 |
| 平板 | iPad 侧栏 + 头像设置 | iPad 多窗口 + pillarbox（侧栏未核实） | NavigationRail 5 项；系列详情两栏 | 🟡 书架仍单栏 |
| 通知 | 无 | ✅ 新章通知 + 后台刷新 | ❌ | ❌ 视需求 |
| 自签名 / 反代 | 首次信任；外网必须 HTTPS | 未核实 | ✅ TOFU + 子路径 + http→https | 🔷 |
| Android / 墨水屏 | ❌ | ❌ | ✅ | 🔷 独有 |

### 2.5 我们领先、且不应被“对标”削弱的

| 能力 | 我们的实现 | 竞品在 Komga 场景下的限制 |
|---|---|---|
| 服务端收藏集 / 阅读列表 | 收藏集/阅读列表 + 详情（只读） | Panels OPDS 只读；Aidoku 用本地 categories，不映射服务端 |
| 进度不丢 | outbox + seq 回执 + `lastModified` 对账 | Panels 乐观写回；Aidoku 本地 + tracker 单向 |
| 按系列完整配置 | 模式/适配/方向/背景/亮度/常亮/锁定/去白边都可覆盖 | Panels 只按书临时改；Aidoku 主要按 manga 记阅读模式 |
| 流式下一本 | 系列内直接下一本，流式可用 | Panels OPDS 流式不可用 |
| 双页卷页 | 铰接书脊、纸背是下一屏 | Panels 有 page curl，但无双页书脊模型公开说明 |
| 离线书架 | HTTP 缓存 + 下载 + 离线提示 | Panels 下载；Aidoku 下载 + 本地 CoreData 库 |
| Android / 墨水屏 | 原生 + 音量键 + 白底黑字 | 两者都没有 |
| 自签名 / 子路径 | TOFU + 子路径 + 自动升级 | Panels 依赖系统信任；Aidoku 未核实 |

---

## 3. UI 逐屏对比

### 3.1 一眼看：同一套“四格 + 搜索球”，语义不同

| 屏幕 | Panels | Aidoku | 我们 |
|---|---|---|---|
| 主导航 | Reading Now / Library / Store / Settings + 搜索 | Library / Browse / History / Settings + 搜索 | Reading / Library / Saved / Settings + 搜索 |
| 首页 | 大封面 “Pick Up Where You Left Off” | source 首页：Keep Reading + Recently Added | 继续阅读卡 + 最近添加 + 按库货架 |
| 书架 | 大标题 “On My iPhone” + 网格/列表 + 进度 % | 大标题 “Library” + 搜索 + 网格/列表 + 未读角标 | 无标题；搜索 + 3 个动作 + 库 chips + 网格 |
| 详情 | 封面/元数据/章节/操作 | 封面/元数据/章节列表/多选/下载/追踪 | 封面/简介/标签 + 书列表 + 单本下载 |
| 阅读器 | 顶部 X + 菜单；底部缩略图 + 阅读时长 | 顶部 X + 章节列表 + AA；底部滑杆 + 剩余页 | 顶部 5 个可点区域；底部缩略图 + 箭头 + 页码 |
| 设置 | 分组多、购买/主题/存储 | 极深、分组页 | 4 组、扁平 |
| 搜索 | 独立 tab，库范围 | 搜索 tab + 历史 + facets | 搜索 tab，空态只有图标 |

**判断**：导航外形已经对齐（都是 iOS 26 悬浮玻璃 dock + 搜索球），差距在**每个 tab 承载的信息量**和**页面标题层级**。我们把一个 tab 给了“收藏”，却没有给“历史”；竞品把 tab 给了 Browse/Store/History，都是“内容发现/回访”入口。

### 3.2 首页 / Reading Now：我们最像竞品，也最缺“上下文”

**Panels**：Reading Now 是一张接近全屏的封面卡，标题和“Pick Up Where You Left Off”压在封面底部，下面是下一本的层叠卡；信息极简，但“这是哪本、读到哪、下一步点哪”一眼可见 [P1]。

**Aidoku**：Komga source 首页是“Keep Reading”横滑 + “Recently Added Books” + “Recently Added Series”，顶部还有 Home/Comics/eBooks 分段（按 Komga 库）[A3]。它把“首页”做成了一个可横滑的内容流，而不是一张卡 + 三条货架。

**我们**：继续阅读卡 = 小封面 + “Pick up where you left off” + **`book.name`（样例是 “Vol. 1”）** + `p. 5 / 12` + 按钮；下面是 Recently added、按库货架 [reading_now_screen.dart:130](../apps/app/lib/src/screens/reading_now_screen.dart#L130)、[reading_now@phone_light.png](../apps/app/test/golden/goldens/reading_now@phone_light.png)。

具体差距：

1. **没有系列名**。`book.name` 是 “Vol. 1”，用户看不出这是《Frieren》。竞品都会把 series 标题放在第一行。这是 P0 级信息缺失。
2. **没有阅读时长 / 上次阅读时间**。Panels 在阅读器里直接显示 “Time reading 15:08”；Aidoku 有 Insights。我们只有页码。
3. **没有“最近阅读”**。只有 Komga `ondeck` 第一条 + 最近添加；看过的书不会回到首页。
4. **加载态会闪空卡**。`ondeck.value ?? []` 先渲染 “Nothing in progress”，数据回来再跳 [reading_now_screen.dart:36](../apps/app/lib/src/screens/reading_now_screen.dart#L36)。竞品用 skeleton/shimmer。
5. **没有分段/作用域**。Aidoku 可按 Komga 库切换 Home/Comics/eBooks；我们靠下面的按库货架，首屏信息密度低。
6. **卡片是“玻璃盒”**。Panels 是封面满出血，Aidoku 是封面网格；我们的小封面 + 白卡 + 按钮，视觉上更像“设置卡片”而不是“继续读”。

**改法（按优先级）**：

- P0：第一行放系列名，第二行 `Vol. 1 · p. 5/12`；封面用系列封面；空态只在确认无数据后出现，加载中上骨架。
- P1：卡片改封面满出血或 16:10 大图，文字压底部渐变；加“上次阅读 2 小时前”/“本次 12 分钟”。
- P1：加一条“最近阅读”横滑（本地 session 或 Komga `readProgress.readDate` 排序的 books）。
- P2：顶部按库分段（All / 库名），替代“每个库一条货架”的长页面。

### 3.3 书架：我们的玻璃有三层，竞品只有一层

**竞品**：

- Panels：大标题 “On My iPhone” + 右上省略号；网格/列表里每本显示进度百分比；底部 tab [P1]。
- Aidoku：大标题 “Library” + 搜索框 + 铃铛/省略号；封面底部渐变压书名，左上角未读角标 [A3][A10]。

**我们**：无标题；第一行是搜索胶囊 + 右侧“排序/筛选/视图”三颗图标组成的第二个胶囊；第二行是库 chips 第三个胶囊；下面是两列封面 + 进度徽标 + 底部细进度线 [library@phone_light.png](../apps/app/test/golden/goldens/library@phone_light.png)、[design-system.md:104](design-system.md)。

具体差距：

1. **没有页面标题**。`design-system.md` 明确写了“书架没有标题文字，只留搜索框 + 右侧三颗动作”。这在视觉上更干净，但用户失去“我在哪”的锚点；竞品都保留大标题。**这是设计取舍，不是 bug**，但建议至少加一个可折叠的 “Library / 书架” 小标题或结果计数。
2. **三层玻璃 + 三套阴影**。搜索、动作、chips 各自是独立玻璃岛，浅色底上看起来像三张贴纸；竞品是“一个搜索框 + 一个省略号”或“标题 + 一个筛选按钮”。玻璃应该只用在“浮在内容上”的 chrome，而不是每个控件都包一层。
3. **筛选项只有图标，没有状态**。筛选生效后没有 badge/计数/当前条件 chips；竞品把筛选放在菜单里并显示选中项。
4. **没有未读角标/置顶**。Aidoku 封面左上角有未读数；Panels 有进度 %。我们只有“已读/总数”徽标和细线。
5. **没有多选**。长按只出“标记已读/未读/详情”单项菜单 [series_shelf_tile.dart:210](../apps/app/lib/src/widgets/series_shelf_tile.dart#L210)；竞品都有多选/批量。
6. **进度语义弱**。徽标 `5/12` 是“已读 5 本”；但用户更想知道“读到第几页/还剩多少”。可以保留徽标，另加一条“当前书页码”或“未读 7 本”。

**改法**：

- P0：加标题/计数（可滚动折叠）；筛选按钮加 active badge；筛选生效时在 chips 行显示当前条件。
- P1：把“排序/筛选/视图”三颗图标合并成一颗“筛选与视图”菜单 + 一颗排序，减少一个玻璃岛；或者保留三颗但去掉外层胶囊阴影，让它们成为一条 toolbar。
- P1：封面左上角加未读角标；支持置顶。
- P1：长按进入多选模式，底部出现批量条（标记/下载/删缓存）。
- P2：列表模式显示“p. 5/12”而不是只有页数。

### 3.4 系列详情：头部够好，书列表太“生”

**我们**：头部 = 封面 + 标题 + 进度条 + Continue 主按钮 + 作者/出版社/年份 + 简介（4 行折叠）+ 标签（最多 4 个）；下面是书行：封面 + `#1 · Vol. 1` + `19 pages` / `Read · 20 pages` + 下载按钮 + 箭头 [series@phone_light.png](../apps/app/test/golden/goldens/series@phone_light.png)、[series_header.dart:211](../apps/app/lib/src/widgets/series_header.dart#L211)。

**竞品**：

- Aidoku 详情页有完整的章节列表头：排序、筛选（语言/扫描组）、章节标题显示模式、下载全部/未读 N 章、多选、标记“之前所有章”、追踪、分享、封面全屏 [A12]。
- Panels 详情页以封面/元数据/操作为主；阅读方向的反转在阅读器内做，OPDS 下不能按书写回。

具体差距：

1. **书行不显示“读到第几页”**。`SeriesBookRow` 的 subtitle 只有 `19 pages` 或 `Read · 20 pages`，没有 `p. 5/12` [series_book_row.dart:33](../apps/app/lib/src/widgets/series_book_row.dart#L33)。这是列表层最明显的“进度不可见”。
2. **没有章节排序/筛选**。长系列找“下一本未读”只能滚；竞品有升/降序、已读/未读、语言、扫描组。
3. **没有多选/批量**。只能单本下载、单本长按标记；竞品可批量下载/标记。
4. **没有“下载全部/下载未读”**。书行右侧只有单本下载按钮；Aidoku 有整套菜单。
5. **简介按钮始终显示**。`Show more` 不管文字长短都出现；标签 `take(4)` 没有 `+N` [series_header.dart:249](../apps/app/lib/src/widgets/series_header.dart#L249)。
6. **书列表没有“当前阅读位置”标记**。Aidoku 章节行有 page、未读/已读、下载状态。

**改法**：

- P0：subtitle 改成 `p. 5/12 · 24 pages`；完成态 `Read · 24 pages`。
- P1：书列表头加“排序（卷号/添加时间）+ 筛选（未读/在读/已读）+ 多选”；批量条支持标记/下载/删缓存。
- P1：右上更多菜单加“下载全部 / 下载未读 N 本 / 标记之前所有为已读”。
- P2：简介按实际行数决定是否显示按钮；标签溢出显示 `+N`；加“分享系列”。

### 3.5 阅读器：我们的控件比竞品多，但信息比竞品少

**竞品**：

- Panels：顶部 `X` + 一个 `...` 菜单（Presets / Configure Reader / Image Filters / Enable Incognito / Reverse Reading Direction / Reader Settings）；底部缩略图 + “Time reading 15:08” + “Page 12 of 26” [P1]。
- Aidoku：顶部 `X` + 章节列表 + 标题 + `AA` + Live Text 按钮；底部页码滑杆 + “18 of 211” + “193 pages left” [A3][A5]。

**我们**：顶部 = 返回 + 标题 + `1 / 3` + 隐身 + 网格 + 模式；底部 = 缩略图条 + 左箭头 + `Page 1` + 右箭头 [reader@phone_dark.png](../apps/app/test/golden/goldens/reader@phone_dark.png)、[reader_chrome.dart:184](../apps/app/lib/src/widgets/reader_chrome.dart#L184)。

具体差距：

1. **没有页码滑杆 / 剩余页数**。我们有缩略图，但快速跳转要拖动一条很长的条；竞品的滑杆是“当前页 + 总量 + 还剩多少”的三合一。
2. **没有目录 / 章节列表**。长系列里换下一本必须退出阅读器；竞品都能在阅读器内切章。
3. **顶部图标太多**：返回、页码、隐身、网格、模式，五个可点区域挤在一行；Panels 把配置收进一个菜单，Aidoku 用 `AA` 收设置。我们的“模式图标”语义也弱（用户不知道 `crop_portrait` 是单页）。
4. **页码重复**：顶部 `1/3`、底部 `Page 1`，同一信息出现两次；底部还有缩略图，信息密度分配不合理。
5. **没有阅读时间**。Panels 直接显示本次阅读时长；我们可以先不显示，但建议在 chrome 里留一个“本次 12 分钟”的位置，为后续 session 做铺垫。
6. **没有点击区配置 / 自动滚动**。固定 1/3 分区对单手/左手用户不友好；条漫没有自动滚动 [reader_zoom.dart:109](../apps/app/lib/src/widgets/reader_zoom.dart#L109)。
7. **没有快捷设置（AA）**。调亮度/背景必须打开整个设置面板；竞品在阅读器内一步可达。

**改法**：

- P1：底部改成“滑杆 + `12 / 26 · 14 left`”，缩略图条保留但可折叠；删除底部的重复页码。
- P1：顶栏把“网格/模式/隐身”收进一个 `...` 菜单；保留 `X`、标题、`AA`（阅读设置）、目录。
- P1：加章节列表（阅读器内换书/换章）。
- P2：加点击区预设（左/右/中/边缘）+ 反转；加自动滚动（仅条漫）。
- P2：加“本次阅读时长”（等 session 模型落地）。

### 3.6 阅读设置：单列长表 vs 分组页

**我们**：底部 sheet 单列：预设 / 按系列记忆 / 模式 / 适配 / 方向 / 背景 / 亮度 / 常亮 / 锁定缩放 / 去白边 / 跳页 [reader_settings@phone_dark.png](../apps/app/test/golden/goldens/reader_settings@phone_dark.png)、[reader_settings_sheet.dart:188](../apps/app/lib/src/widgets/reader_settings_sheet.dart#L188)。

**竞品**：Panels 是 Presets + 独立 Configure Reader 页；Aidoku 是分组页（General / Tap Zones / Upscaling / Paged / Webtoon / Text Reader / Dictionary），按当前模式条件显示 [A4][A6]。

具体差距：

1. **小屏要滚很久**，没有分组折叠，也没有“重置”。
2. **没有预览**。适配方式只有文字；Panels 把 Configure Reader 拆成独立页，我们可以用 4 个小的页面 fit 示意图把“填满/适应/宽/高”讲清楚。
3. **没有动画选择**。只有卷页/平移/瞬切，且 400ms 硬编码 [page_curl.dart:17](../apps/app/lib/src/widgets/page_curl.dart#L17)。
4. **没有点击区/自动滚动**（见 3.5）。
5. **预设的应用不完整**：全局应用漏还原 `lockZoom`/`trimBorders`，系列应用却还原 [reader_prefs_provider.dart:105](../apps/app/lib/src/providers/reader_prefs_provider.dart#L105)。这是 bug，不是设计。

**改法**：

- P1：分成“页面 / 布局 / 颜色 / 交互”四组，顶部放当前模式摘要；加“重置本组”。
- P1：适配方式改成 4 个带示意图的分段卡；背景/亮度合并成一组。
- P1：修预设应用；动画选择放进“页面”组。
- P2：点击区、自动滚动、阅读方向锁定。

### 3.7 搜索：空态只有一行字，竞品有“最近搜索”

**我们**：空态 = 放大镜 + “Search series, books, authors…”，下面全空 [search@phone_light.png](../apps/app/test/golden/goldens/search@phone_light.png)。结果 = 系列 section + 书 section，固定 20 条，无筛选、无历史、无“还有更多” [search_screen.dart:84](../apps/app/lib/src/screens/search_screen.dart#L84)。

**竞品**：

- Aidoku：空态有 “No recent searches” 说明；有历史时显示 Recently Searched + Clear + 滑动删除；搜索有类型/状态/标签/出版商/语言/年龄分级筛选 [A4]。
- Panels：有独立 Search tab；本库搜索免费、跨库搜索 Premium [P10]。

具体差距：

1. 没有最近搜索（本地存最近 10 条即可）。
2. 没有 facets（标签/作者/状态/语言）；服务端支持 `search` + 条件，但 UI 没接。
3. 没有分页/加载更多，第 21 条起静默消失。
4. 空态没有“建议/热门标签/最近添加”，首屏信息量为零。
5. 结果行没有系列名（书结果只显示书名），和继续阅读卡同一个问题。

**改法**：

- P0：最近搜索（本地）+ 清空；空态显示最近搜索/最近阅读。
- P1：结果分页/无限滚动 + 总数；书结果显示 `系列名 · Vol. x`。
- P1：筛选 chips：已读状态、标签、作者（先做服务端已验证的字段）。
- P2：搜索作用域（当前库/全部库）。

### 3.8 收藏集 / 阅读列表：服务端原生，但 UI 像“设置列表”

**我们**：分段控件 Collections / Read lists；下面是白卡行：图标 + 名称 + “2 series” + 箭头；没有封面、没有简介、没有排序/搜索；固定 20 条 [collections@phone_light.png](../apps/app/test/golden/goldens/collections@phone_light.png)、[collections_screen.dart:96](../apps/app/lib/src/screens/collections_screen.dart#L96)。

**竞品**：

- Panels：collection = 文件夹，有封面/颜色/标志，网格展示 [P11]。
- Aidoku：categories 有封面网格、未读角标、筛选组 [A4]。

具体差距：

1. 视觉上无法“一眼认出”收藏集；封面马赛克是最低成本的身份表达。
2. 不能排序/搜索；收藏集多了以后很难找。
3. 不能新建/编辑/删除（Komga API 支持，我们只读）。
4. 没有“全部标记已读/下载全部”等批量动作。
5. 没有描述/最后更新时间。

**改法**：

- P0：每个收藏集显示 2–4 张系列封面拼贴 + 数量；没有封面时用首字母色块。
- P1：搜索/排序（名称/最近更新）；分页。
- P1：服务端 API 支持时加“新建/编辑/删除”；否则明确“只读”并给服务器端入口提示。
- P2：收藏集详情加批量标记/下载。

### 3.9 设置 / 下载：够用，但不像“一个成熟 App 的设置”

**我们**：4 组：Appearance（主题/语言/墨水屏/触感）、Servers、Storage（缓存/下载）、About（版本硬编码 `0.1.0 (v1)` / 许可）[settings@eink.png](../apps/app/test/golden/goldens/settings@eink.png)、[settings_screen.dart:196](../apps/app/lib/src/screens/settings_screen.dart#L196)。

**竞品**：

- Panels：Appearance/Reader/Library/Downloads/Storage/Privacy/Purchases/About 等。
- Aidoku：Appearance/Library/Reader/Dictionaries/Tracking/iCloud/Advanced/About/Insights/Source Lists/Backups/Downloads [A4]。

具体差距：

1. 版本号硬编码；没有构建号/提交号。
2. 没有“阅读默认值”入口（只能进阅读器改）。
3. 没有“阅读历史/统计”入口。
4. 没有“备份/导出本地设置”（预设、按系列覆盖、书架视图）。换机/重装会丢。
5. 没有“高级/诊断/日志”（出问题只能看系统日志）。
6. 下载页只有列表 + 删除；没有队列控制、仅 Wi-Fi、读完删除、压缩、并行。
7. 主题/墨水屏开关不持久化（见 §4），设置页看起来有，重启就回默认。

**改法**：

- P0：版本读 `package_info_plus`；主题/墨水屏持久化。
- P1：加 Reader / Library / Downloads 三个子页；阅读默认值从阅读器面板“提升”到设置。
- P1：本地设置导出/导入（JSON 即可）；预设/覆盖/视图选项。
- P2：下载设置（仅 Wi-Fi、读完删除、队列并发）；诊断日志。

### 3.10 视觉语言：我们的“液态玻璃”有点用力过猛（主观）

**做得好的**：

- 有明确的材质语言：`GlassOptics` / 折射 / 高光 / 选中嵌入胶囊，比 Material 默认的“半透明白条”高级。
- 底部 dock 的选中胶囊弹簧、搜索球、按压缩放，手感方向是对的。
- 卷页、封面 squircle、Hero、e-ink 的纸底墨边，都是加分项。

**问题（从黄金图看，主观）**：

1. **玻璃层级太多**：书架顶部三层（搜索 / 动作 / chips），下载页是“返回圆球 + 标题胶囊”，搜索页是“搜索胶囊里再套输入框”。竞品的 chrome 通常只有一层；玻璃越少，内容越突出。
2. **阴影太重**：浅色模式下每组玻璃都有明显下投影，叠加后像“贴纸”。可以只给 dock 和浮层菜单阴影，页面内 toolbar 用无阴影的磨砂/半透明底。
3. **标题被拿掉后，页面没有“名字”**：书架、正在读、收藏都没有标题；竞品都有大标题。建议至少保留一个可折叠的 section header，或在 dock 选中项上给出页面名。
4. **信息密度低**：搜索空态、收藏集、继续阅读卡都是“一个大容器 + 一行字”。竞品用封面、角标、进度、时间把同样的空间填满。
5. **字体层级偏弱**：继续阅读卡的 “Pick up…” 很小，书名是 `headline`，进度是 `bodySmall`；竞品把书名/章节名做得更重，进度用等宽数字。

**建议**：

- 一次只保留一层玻璃 chrome；页面内 toolbar 用 `surface` + 细分隔线，不用独立阴影。
- 恢复“页面标题”层级：大标题（可折叠）或顶部 section header；不要把标题塞进胶囊。
- 用封面/角标/进度/时间提升密度，而不是加更多装饰。
- 浅色模式降低 `AppShadows.floating` 的透明度/半径；e-ink 保持现在的墨边。
- 先做一次实机截图对照（`docs/assets/` 目前没有 Panels/Aidoku 参照图）；黄金图用的测试字体和假封面会放大“空”的感觉。

### 3.11 平板 / 墨水屏

**平板**：

- 我们：`NavigationRail` 5 项；系列详情 ≥1024 两栏；书架仍是单栏网格（只是列数变多）[adaptive_shell.dart:108](../apps/app/lib/src/widgets/adaptive_shell.dart#L108)。
- 竞品：Panels iPad 侧栏 + 头像进设置；Aidoku iPad 多窗口 + pillarbox（侧栏未核实）。它们的“书架/详情”在 iPad 上不是放大的手机。
- 差距：书架没有“库/收藏列表 + 内容”两栏；阅读器没有专门的 iPad 双页/单页布局切换（我们有 auto 横屏双页，方向是对的）。
- 建议：P2 做书架两栏（左库/收藏，右系列网格）；阅读器设置里给 iPad 一个“默认双页”开关。

**墨水屏**：

- 我们独有：e-ink 主题、白底黑字、零动画、零阴影、自动探测。
- 但自动探测只作用于全局主题，**阅读器只读 `forceEink`**：自动探测到的 Boox 仍会用黑底/深色 chrome/卷页 [app.dart:27](../apps/app/lib/src/app.dart#L27)、[reader_screen.dart:341](../apps/app/lib/src/screens/reader_screen.dart#L341)。这是 P0。
- 竞品都没有墨水屏；这是我们最稳的差异化，先把“探测 → 阅读器”打通，再谈对比度/灰度。

---

## 4. 我们自己的实现缺口（不是竞品差距，是 bug / 半成品）

> 这些是“文档说有、代码没做到”或“代码做了、状态没保住”的项。先修这些，再谈功能对标。

| # | 问题 | 证据 | 影响 |
|---|---|---|---|
| B1 | 自动探测墨水屏不作用于阅读器 | `app.dart:27` 用 `forceEink` 或 `detected`；`reader_screen.dart:341` 只用 `forceEink` | 自动探测机型仍黑底、深色 chrome、卷页、动态背景 |
| B2 | 主题 / 强制墨水屏不持久化 | `settings_store.dart:10-20` 只存语言/触感 | 重启回默认；设置页开关像假的 |
| B3 | 书架排序/筛选/视图/封面档位不持久化 | `library_providers.dart:272-280` 每次 build 默认 State | 每次冷启动都要重设 |
| B4 | 从搜索/阅读列表进阅读器丢系列方向 | `search_screen.dart:142`、`readlist_detail_screen.dart:77` 只传 `ReaderArgs(book)` | RTL 书按 LTR 打开，点击区/箭头全反 |
| B5 | 预设“全局应用”漏还原 `lockZoom`/`trimBorders` | `reader_prefs_provider.dart:105-113` | 应用预设后锁定缩放/去白边可能丢 |
| B6 | 正在读加载中先闪空态 | `reading_now_screen.dart:36,64-67` | 每次进首页闪一下 “Nothing in progress” |
| B7 | 下载队列只在内存 | `download_providers.dart:94-97` | 杀进程后“排队中”消失，已下载记录还在 |
| B8 | 搜索/收藏集/阅读列表固定 20 条 | `library_repository.dart:33-60`、`collections_screen.dart:96` | 第 21 条起静默消失，用户不知道还有更多 |
| B9 | 版本号硬编码 | `settings_screen.dart:199-211` | 发布后版本信息不可信 |
| B10 | 书行不显示页码进度 | `series_book_row.dart:33-39` | 系列里看不出“这本读到哪” |
| B11 | 继续阅读卡没有系列名 | `reading_now_screen.dart:191-203`（`book.name` = “Vol. 1”） | 用户不知道在读哪本 |
| B12 | 简介按钮/标签溢出 | `series_header.dart:249,314-323` | 短简介也显示 Show more；标签 4 个后无 +N |
| B13 | 下载页/设置页没有队列表述 | `downloads_screen.dart:88-187` | 只能看单本进度，不能暂停/重排/全局完成提示 |
| B14 | 代码规模超标 | `reader_screen.dart` 487 行、`library_providers.dart` 364 行；`reader_settings_sheet.dart` 350 行（压线） | 违反 350 行约定，后续改动风险高 |

> 文档债务：`panels-comparison.md` 里“P3 14/14”与“P3 未开始”自相矛盾；“列表直接显示服务器进度”只对继续阅读卡成立；“触感只有 3 处”已过时。本文以代码为准，旧文保留作历史。

---

## 5. 优先级与路线图

> 成本是粗估：S ≈ 半天–1 天，M ≈ 2–3 天，L ≈ 一周以上（单人 + Agent 节奏）。
> 每项都要过 `dart run tool/ci.dart check`、补黄金图、装模拟器走查。

### 5.1 第 0 批：正确性（先修，1–2 天）

| 编号 | 内容 | 依据 | 成本 | 验收 |
|---|---|---|---|---|
| F1 | 墨水屏探测接入阅读器 | B1 | S | 自动探测机型阅读器白底/零动画 |
| F2 | 主题/墨水屏持久化 | B2 | S | 重启后主题/开关保持 |
| F3 | 书架视图/排序/筛选持久化 | B3 | S | 冷启动保持上次选择 |
| F4 | 搜索/阅读列表传系列方向 | B4 | S | RTL 书从任意入口打开方向正确 |
| F5 | 预设应用补齐 `lockZoom`/`trimBorders` | B5 | S | 应用预设后两项一致 |
| F6 | 正在读骨架 + 不闪空态 | B6 | S | 加载中不出现空卡 |
| F7 | 下载队列落盘 | B7 | M | 杀进程后队列恢复或明确取消 |
| F8 | 书行显示页码进度 | B10 | S | `p. 5/12 · 24 pages` |
| F9 | 继续阅读卡显示系列名 | B11 | S | 首行系列名，次行卷/页 |
| F10 | 版本读 `package_info` | B9 | S | 设置页版本=构建版本 |

### 5.2 第 1 批：信息密度与阅读器（约 1 周）

| 编号 | 内容 | 竞品依据 | 成本 |
|---|---|---|---|
| U1 | 书架标题/计数 + 筛选 active badge + 当前条件 chips | Panels/Aidoku 大标题 + 筛选状态 | S–M |
| U2 | 合并书架顶部三颗图标为一颗“筛选与视图” + 一颗排序 | Panels 省略号 / Aidoku 筛选 | S |
| U3 | 封面左上未读角标 + 置顶 | Aidoku 未读角标 / pin | M |
| U4 | 继续阅读卡改封面满出血 + 系列名 + 时间/页码 | Panels Reading Now | M |
| U5 | 阅读器底部页码滑杆 + “N left” + 去重页码 | Aidoku `ReaderSliderView` | M |
| U6 | 阅读器内章节列表（TOC）+ 切章 | Panels TOC / Aidoku chapter list | M |
| U7 | 顶栏收成 `X / 标题 / AA / ...`，隐身/网格/模式进菜单 | Panels 菜单 / Aidoku AA | S–M |
| U8 | 阅读设置分组 + 重置 + 适配示意图 | Panels Configure Reader / Aidoku 分组 | M |
| U9 | 收藏集封面拼贴 + 搜索/排序 | Panels collection covers | M |
| U10 | 搜索空态最近搜索 + 结果分页 | Aidoku recent searches | S–M |

### 5.3 第 2 批：书架运营与搜索（约 1 周）

| 编号 | 内容 | 竞品依据 | 成本 |
|---|---|---|---|
| L1 | 系列书列表排序/筛选（卷号、未读/在读/已读） | Aidoku 章节筛选/排序 | M |
| L2 | 系列多选 + 批量标记/下载/删缓存 | Aidoku 章节多选 | M |
| L3 | 系列级“下载全部 / 下载未读 N 本” | Aidoku download menu | S–M |
| L4 | 书架多选 + 批量操作 | Aidoku/Panels 多选 | M |
| L5 | 筛选组合保存（filter groups） | Aidoku Filter Groups | M |
| L6 | 搜索 facets（状态/标签/作者）+ 总数 | Aidoku 搜索筛选 | M |
| L7 | 下载设置：仅 Wi-Fi/读完删除/并发 | Aidoku 下载设置 | S–M |
| L8 | 收藏集新建/编辑（若 Komga API 验证通过） | Panels 文件夹/Aidoku categories | M |

### 5.4 第 3 批：时间维度与设置（1–2 周）

| 编号 | 内容 | 竞品依据 | 成本 |
|---|---|---|---|
| H1 | 阅读 session 数据模型（开始/结束/时长/页码） | Panels sessions / Aidoku Insights | M |
| H2 | History 页或“正在读”里的最近阅读段 | Aidoku History tab | M |
| H3 | Insights（连续天数/热力图/章节数） | Aidoku Insights | M–L |
| H4 | 设置 IA：Reader/Library/Downloads/History/About 子页 | Panels/Aidoku | M |
| H5 | 本地设置导出/导入（预设/覆盖/视图） | Aidoku `.aib` | S–M |
| H6 | 点击区预设 + 反转 | Aidoku Tap Zones | M |
| H7 | 条漫自动滚动（速度/停靠） | Aidoku Auto Scroll | M |
| H8 | 翻页动画选择（卷页/平移/淡入/瞬切） | Panels/Aidoku | S |
| H9 | i18n 扩展（至少日/繁中/西/法） | Panels 12 / Aidoku 41 | L（社区） |
| H10 | TalkBack/VoiceOver 走查 + Dynamic Type 2.0× | 竞品系统级 | M |

### 5.5 明确不做（或暂缓）

| 需求 | 理由 |
|---|---|
| WASM 外部图源生态 / 内置商店 | 版权、审核、维护三重风险；与“自建 Komga 客户端”定位冲突 |
| 本地导入 / 网盘 / 云盘 | 不是 Komga 场景；Panels/Aidoku 的广度优势，不追 |
| Panels View / 逐格阅读 | 需要 ML 模型；Panels 多年仍标实验；与 Komga 场景弱相关 |
| Live Text / OCR 词典 / 实时翻译 | 平台 ML 依赖强；优先做阅读体验而非学习工具 |
| AniList/MAL 追踪 | Komga 用户的核心追踪就是 Komga 本身；多一层追踪是负担 |
| Panels 账号 / iCloud 同步 | 服务端就是真值源；多一层同步只会产生两份进度 |
| 内容锁（Face ID） | 自建服务器有账号权限；需求弱 |
| 可替换图标 / 付费主题 | 收益低；先把层级和密度做好 |
| 新章通知（暂缓） | Komga 无 push；要轮询 + 后台任务，收益/成本比低，等用户明确要求 |

---

## 6. 如果要只做 5 件事

1. **修 B1–B6**（墨水屏/持久化/方向/预设/空态）：让现有功能可信。
2. **书行显示页码 + 继续卡显示系列名**：让“读到哪”在列表层可见。
3. **系列书列表的排序/筛选/多选/下载全部**：把“找下一本”闭环。
4. **阅读器底部页码滑杆 + 章节列表 + AA 快捷设置**：把阅读器从“能读”做到“顺手”。
5. **History/session**：先落数据模型，再做 History 页；Insights 后置。

这 5 件做完，我们在“日常使用”上会非常接近 Panels；在“功能广度”上仍不如 Aidoku，但那是 source 聚合器的广度，不是 Komga 客户端的必答题。

---

## 7. 证据与来源

### 7.1 Panels

- [P1] App Store 商品页（3.13.11、截图、语言列表）：<https://apps.apple.com/us/app/panels-comic-reader/id1236567663>
- [P2] Panels 博客（iPhone Duo、Panels 4 预告）：<https://www.panels.app/blog/iphoneduo>
- [P3] Reader presets and configurations：<https://guides.panels.app/read-content/reader-configurations>
- [P4] Reading sessions：<https://guides.panels.app/read-content/reading-sessions>
- [P5] Double page grouping：<https://guides.panels.app/read-content/double-page-grouping>
- [P6] Lock zoom：<https://guides.panels.app/read-content/lock-zoom>
- [P7] Incognito：<https://guides.panels.app/read-content/incognito-mode>
- [P8] Image filters：<https://guides.panels.app/read-content/image-filters>
- [P9] Panels View：<https://guides.panels.app/read-content/panels-view>
- [P10] Premium：<https://guides.panels.app/premium/what-is-panels-premium>
- [P11] Libraries：<https://guides.panels.app/libraries/how-libraries-work>
- [P12] Panels for Komga：<https://www.panels.app/komga-ios-app>
- [P13] Keyboard shortcuts：<https://guides.panels.app/remotes-and-controllers/keyboard-shortcuts>
- [P14] Accessibility：<https://guides.panels.app/remotes-and-controllers/accessibility-options>
- [P15] Continue reading：<https://guides.panels.app/read-content/continue-reading>
- [P16] Komga progress sync（社区，开发者回复）：<https://community.panels.app/t/komga-reading-progress-sync/1714>
- [P17] OPDS 阅读方向（社区）：<https://community.panels.app/t/is-it-possible-to-set-the-reading-direction-on-multiple-comics-on-opds/2428>
- [P18] Live Text：<https://guides.panels.app/read-content/live-text>

### 7.2 Aidoku

- [A1] 仓库与 README：<https://github.com/Aidoku/Aidoku>
- [A2] Releases（v0.9-4 / v0.9 / v0.8.x）：<https://github.com/Aidoku/Aidoku/releases>、<https://aidoku.app/release-notes/>
- [A3] 官网与官方截图：<https://aidoku.app>、<https://aidoku.app/images/library.png>、<https://aidoku.app/images/source.png>、<https://aidoku.app/images/reader.png>
- [A4] Settings.swift（设置项全量）：<https://github.com/Aidoku/Aidoku/blob/main/Aidoku/Features/Settings/Settings.swift>
- [A5] ReaderToolbarView.swift（滑杆/页码/剩余页）：<https://github.com/Aidoku/Aidoku/blob/main/Aidoku/Features/Reader/Toolbar/ReaderToolbarView.swift>
- [A6] ReaderSettingsView.swift（按 manga 阅读模式/分页/webtoon）：<https://github.com/Aidoku/Aidoku/blob/main/Aidoku/Features/Reader/ReaderSettingsView.swift>
- [A7] Komga source（listings/筛选/分页）：<https://github.com/Aidoku/Aidoku/blob/main/Aidoku/Core/Sources/BuiltIn/Komga/KomgaSource.swift>
- [A8] Komga models（`readingDirection` → viewer）：<https://github.com/Aidoku/Aidoku/blob/main/Aidoku/Core/Sources/BuiltIn/Komga/KomgaModels.swift>
- [A9] Komga tracker（进度回写）：<https://github.com/Aidoku/Aidoku/blob/main/Aidoku/Core/Tracking/Trackers/komga/KomgaTracker.swift>
- [A10] TabBarController.swift（4 tab + search，large titles）：<https://github.com/Aidoku/Aidoku/blob/main/Aidoku/App/Root/TabBarController.swift>
- [A11] LibraryViewModel.swift（8 种排序/categories/pin）：<https://github.com/Aidoku/Aidoku/blob/main/Aidoku/Features/Library/LibraryViewModel.swift>
- [A12] MangaView.swift（章节多选/下载全部/tracker）：<https://github.com/Aidoku/Aidoku/blob/main/Aidoku/Features/Manga/MangaView.swift>
- [A13] HistoryView.swift：<https://github.com/Aidoku/Aidoku/blob/main/Aidoku/Features/History/HistoryView.swift>
- [A14] InsightsView.swift：<https://github.com/Aidoku/Aidoku/blob/main/Aidoku/Features/Settings/Insights/InsightsView.swift>
- [A15] FAQ（分发/iCloud/安装）：<https://aidoku.app/help/faq/>
- [A16] iCloud sync issue #111：<https://github.com/Aidoku/Aidoku/issues/111>
- [A17] Komga 问题 #454：<https://github.com/Aidoku/Aidoku/issues/454>

### 7.3 本仓库

- [R1] 导航与分支：[adaptive_shell.dart](../apps/app/lib/src/widgets/adaptive_shell.dart)
- [R2] 正在读：[reading_now_screen.dart](../apps/app/lib/src/screens/reading_now_screen.dart)
- [R3] 书架：[library_screen.dart](../apps/app/lib/src/screens/library_screen.dart)、[shelf_views.dart](../apps/app/lib/src/widgets/shelf_views.dart)
- [R4] 系列详情/书行：[series_detail_screen.dart](../apps/app/lib/src/screens/series_detail_screen.dart)、[series_book_row.dart](../apps/app/lib/src/widgets/series_book_row.dart)、[series_header.dart](../apps/app/lib/src/widgets/series_header.dart)
- [R5] 阅读器：[reader_screen.dart](../apps/app/lib/src/screens/reader_screen.dart)、[reader_chrome.dart](../apps/app/lib/src/widgets/reader_chrome.dart)、[reader_zoom.dart](../apps/app/lib/src/widgets/reader_zoom.dart)
- [R6] 阅读偏好/预设：[reader_prefs.dart](../apps/app/lib/src/data/reader_prefs.dart)、[reader_prefs_provider.dart](../apps/app/lib/src/providers/reader_prefs_provider.dart)
- [R7] 设置/持久化：[settings_screen.dart](../apps/app/lib/src/screens/settings_screen.dart)、[settings_store.dart](../apps/app/lib/src/data/settings_store.dart)
- [R8] 下载/缓存：[download_service.dart](../apps/app/lib/src/data/download/download_service.dart)、[download_providers.dart](../apps/app/lib/src/providers/download_providers.dart)、[downloads_screen.dart](../apps/app/lib/src/screens/downloads_screen.dart)
- [R9] 设计系统：[design-system.md](design-system.md)
- [R10] 黄金图：[library@phone_light.png](../apps/app/test/golden/goldens/library@phone_light.png)、[reading_now@phone_light.png](../apps/app/test/golden/goldens/reading_now@phone_light.png)、[series@phone_light.png](../apps/app/test/golden/goldens/series@phone_light.png)、[reader@phone_dark.png](../apps/app/test/golden/goldens/reader@phone_dark.png)、[search@phone_light.png](../apps/app/test/golden/goldens/search@phone_light.png)、[collections@phone_light.png](../apps/app/test/golden/goldens/collections@phone_light.png)、[settings@eink.png](../apps/app/test/golden/goldens/settings@eink.png)

### 7.4 方法与置信度

- **高置信**：版本、平台、功能有无、设置项、代码实现、黄金图；来自源码/API/官方文档。
- **中置信**：Panels 的排序数量、Aidoku 的“无 fit/无亮度/无锁定缩放”——基于源码设置项“未见”，可能存在未暴露的实现。
- **低置信 / 主观**：“高级感”“玻璃是否过重”“标题该不该保留”，来自截图与黄金图对比，没有 iPhone/iPad 实机走查。
- **本轮未做**：真机截图对照（`docs/assets/` 仍无 Panels/Aidoku 参照图）、TalkBack/VoiceOver 走查、iPad 分屏、墨水屏真机残影。下一轮如果要做视觉定稿，先补这四项。

---

> 维护提示：Panels 4 发布后，本文的 Panels 列需要整体重评；Aidoku 的功能以 `main` 分支源码为准，版本号以 Releases 为准。不要把“未发布/未核实”的功能算进当前差距。
