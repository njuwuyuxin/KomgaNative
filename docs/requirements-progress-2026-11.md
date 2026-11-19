# 需求收敛进度（2026-11 起）

> 需求明细与验收标准见 [requirements-plan-2026-11.md](requirements-plan-2026-11.md)；
> 差距来源见 [competitor-research-2026-11.md](competitor-research-2026-11.md)。
>
> 状态：`TODO` 未开始 / `WIP` 开发中 / `DONE` 已通过门禁 + 设备验证并推送。
> 每行完成后填 commit，便于回溯"哪次改动兑现了哪条需求"。

## W0 正确性

| ID | 需求 | P | 状态 | commit |
|---|---|---|---|---|
| FIX-01 | 墨水屏探测贯通阅读器 | P0 | DONE | `20cf264` |
| FIX-02 | 主题/墨水屏/书架视图持久化 | P0 | DONE | `6f2c646` |
| FIX-03 | 阅读方向覆盖所有入口 | P0 | DONE | `feat(app): 方向未知时按系列兜底` |
| FIX-04 | 预设应用补齐锁定缩放/去白边 | P0 | DONE | `feat(app): 预设应用共用 withConfig` |
| FIX-05 | 正在读骨架与空态修正 | P0 | DONE | `488e19d` |
| FIX-06 | 列表层进度与系列名 | P0 | DONE | `feat: 书行页码与继续卡的系列名` |
| FIX-07 | 下载队列持久化 | P0 | DONE | `feat(app): 下载队列落盘并恢复` |
| FIX-08 | 搜索/收藏集/阅读列表分页 | P0 | DONE | `feat: 搜索/收藏集/阅读列表接分页` |
| FIX-09 | 版本号/简介按钮/标签溢出 | P0 | DONE | `feat: 版本读构建产物、简介/标签按需展开` |

## W1 阅读器

| ID | 需求 | P | 状态 | commit |
|---|---|---|---|---|
| QUA-01 | 拆 `reader_screen` + 清理死代码 | P1 | DONE | `refactor(reader): 拆分阅读器状态与命令` |
| RDR-01 | 阅读器页码滑杆 + 剩余页 | P1 | DONE | `feat(reader): 页码滑杆与剩余页` |
| RDR-02 | 阅读器目录/章节列表 | P1 | DONE | `feat(reader): 目录面板` |
| RDR-03 | 顶栏 IA + AA 快捷设置 | P1 | DONE | `feat(reader): 顶栏四槽 + AA 快捷设置` |
| RDR-04 | 阅读设置分组/重置/适配预览 | P1 | DONE | `feat(reader): 设置分四组、可单组重置` |
| RDR-05 | 翻页动画选择 | P1 | DONE | `feat(reader): 翻页动画可选` |
| RDR-06 | 双页分组持久化 | P1 | DONE | `feat(reader): 双页分组按书持久化` |

## W2 书架/系列

| ID | 需求 | P | 状态 | commit |
|---|---|---|---|---|
| LIB-01 | 书架标题/计数/筛选状态/toolbar 收敛 | P1 | TODO | — |
| LIB-02 | 未读角标 + 置顶 | P1 | DONE | `feat(shelf): 未读角标 + 系列置顶` |
| LIB-03 | 书架多选/批量 | P1 | DONE | `feat(shelf): 多选与批量标记` |
| LIB-04 | 排序补充 + 保存筛选组合 | P1 | DONE | `feat(shelf): 保存筛选组合 + 删掉空操作排序` |
| SER-01 | 系列书列表排序/筛选 | P1 | DONE | `feat(series): 书列表排序与筛选` |
| SER-02 | 系列书多选/批量/标记之前所有 | P1 | DONE | `feat(series): 书多选与批量标记` |
| SER-03 | 系列下载全部/未读 N 本 | P1 | DONE | `feat(series): 批量下载全部/未读 N 本` |
| UI-01 | 玻璃层级/阴影/字体克制 | P1 | DONE | `feat(ui): 单层标题栏、轻阴影、进度数字` |

## W3 搜索/下载/设置

| ID | 需求 | P | 状态 | commit |
|---|---|---|---|---|
| SCH-01 | 搜索历史 + 空态 | P1 | DONE | `feat(search): 搜索历史与空态引导` |
| SCH-02 | 搜索 facets（状态/标签/作者） | P1 | TODO | — |
| SCH-03 | 搜索分页 + 结果系列名 | P1 | DONE | `feat(search): 分页保留旧结果与失败提示` |
| DLD-01 | 下载设置（仅 Wi-Fi/读完删除/并发） | P1 | TODO | — |
| DLD-02 | 下载队列 UI + 全局反馈 | P1 | DONE | `feat(downloads): 队列暂停/重试/删除全部` |
| SET-01 | 设置 IA（Reader/Library/Downloads/History/About） | P2 | TODO | — |

## W4 历史/收藏/备份

| ID | 需求 | P | 状态 | commit |
|---|---|---|---|---|
| HIS-01 | 阅读 session 数据模型 | P2 | DONE | `feat(history): 阅读会话记账与落库` |
| HIS-02 | History 页 + 最近阅读行 | P2 | DONE | `feat(history): 历史页与最近阅读横滑` |
| SET-02 | 本地偏好导出/导入 | P2 | DONE | `feat(settings): 偏好导出/导入（剪贴板）` |
| UI-02 | 收藏集封面拼贴/描述/搜索 | P2 | DONE | `feat(collections): 封面拼贴 + 搜索排序` |
| PLT-01 | 平板书架两栏 | P2 | DONE | `feat(shelf): 平板两栏（库导航 + 书架）` |

## W5 深度/平台

| ID | 需求 | P | 状态 | commit |
|---|---|---|---|---|
| HIS-03 | Insights（连续天数/热力图/统计） | P2 | TODO | — |
| HIS-04 | 阅读器内阅读时长 | P2 | DONE | `feat(reader): chrome 显示本次阅读时长` |
| PLT-02 | iPad 默认双页/阅读布局 | P2 | DONE | `feat(reader): 平板默认排版（自动/单页/双页）` |
| I18N-01 | 数据层错误文案本地化 | P2 | DONE | `feat(i18n): 失败类型走 l10n` |
| A11Y-01 | TalkBack/VoiceOver + Dynamic Type 2.0 | P2 | TODO | — |
| UI-03 | 黄金图覆盖补齐 | P2 | TODO | — |

## W6 可选增强

| ID | 需求 | P | 状态 | commit |
|---|---|---|---|---|
| RDR-07 | 点击区预设 + 反转 | P2 | TODO | — |
| RDR-08 | 条漫自动滚动 | P2 | TODO | — |
| SER-04 | 收藏集新建/编辑（API 验证后） | P2 | TODO | — |
| I18N-02 | 语言扩展框架（日/繁中/西/法） | P2 | TODO | — |

---

## 已知取舍

实施过程中如果某条需求与既有约束冲突（例如 Komga 服务端不支持该查询参数），
在本节记录"降级成什么"和"为什么"，不要静默砍功能。

## 实施记录

### FIX-01 墨水屏探测贯通阅读器

- 新增 `effectiveEinkProvider`（`forceEink || einkDetected`）作为唯一来源；
  `KomgaApp`、`ReaderScreen`（配色 / 翻页效果 / 开场 Hero）都读它。
- 新增黄金图 `reader_auto_eink`（只覆盖探测为真、不打开强制开关）与
  `test/providers/effective_eink_test.dart`。
- 顺手把 `ReaderScreen` 里重复的 `settingsProvider` 读取去掉，避免再次出现
  "主题变了、阅读器没变"。

### FIX-02 主题 / 墨水屏 / 书架视图持久化

- 存储从"一个字段一个方法"改成**一份快照** `AppSettings`：
  `themeMode`、`forceEink`、`language`、`haptics`、`view`、`coverSize`、
  `sort`、`readStatus`，外加 `libraryFilters`（每台服务器上次选的库）。
- `SettingsStore.update(mutate)` 做"读出最新 → 只改这几个字段 → 写回"，并在
  `SecureSettingsStore` 里串行化：设置页与书架控制器共用同一个 blob，读改写
  才不会被对方用旧快照覆盖。
- 书架**先恢复再加载**，避免"先按默认排序画一屏、再跳成上次的排序"。
- 存档里的库 id 会先跟当前服务器的库列表核对：不存在就回"全部库"并清掉脏记录；
  库列表取不到（离线）时保留原选择。
- 解码逐字段容错（未知枚举/类型不对只影响该字段），覆盖旧版本只有 `language`
  的存档与非法 JSON。

### FIX-03 阅读方向覆盖所有入口

- `ReaderScreen` 在 `direction == unknown` 时自己解析：取书（路由入口只带
  bookId）→ `book.seriesId` → `seriesDetailProvider` → `series.readingDirection`。
  显式传入的方向仍然优先，系列页/继续阅读卡行为不变。
- 方向只在 `build` 里解析并缓存到 `_direction`；音量键、键盘、生命周期这些
  事件回调读缓存，避免在 build 之外 `ref.watch`。
- 系列查不到（离线 / 深链脏数据）回 unknown，界面按从左到右兜底，不阻塞打开。
- 测试：`reader_direction_fallback_test.dart` 7 条，覆盖 RTL/LTR 兜底、底栏箭头
  镜像、系列缺失、显式优先、系列晚到、路由直接进入。
- 设备走查限制：这台服务器没有阅读列表/收藏集，搜索页目前也不出书结果，
  所以"搜索/阅读列表入口"在真机上造不出来；RTL 系列从系列页进入已确认方向正确
  （缩略图滑条第 1 页在最右）。

### FIX-04 预设应用补齐锁定缩放/去白边

- 新增 `ReaderPrefs.withConfig(config)`：一次覆盖全部配置字段，预设列表与系列
  覆盖保持不变。`applyPreset` 的全局/按系列两条路径都只调它（+`withSeriesOverride`），
  字段清单只写一遍，以后加开关不会再漏一条路径。
- 测试：`reader_preset_apply_test.dart` 5 条——全局逐字段一致、按系列一致、
  删覆盖回全局、旧存档缺字段按 false、无效 id 不改任何东西。
- 设备走查：在阅读设置里成功新建"预设 3"（含锁定缩放/去白边），面板交互正常；
  应用后逐项回填由上述单测钉住（设备端 adb 点击在这张长面板上不稳定，
  没有逐项截图确认，这一点如实记录）。

### FIX-05 正在读骨架与空态修正

- 继续卡/最近添加/按库货架三块各自是独立请求，现在各自处理三态：
  加载 → 骨架；首次失败 → 错误卡片 + 重试；有数据但刷新失败 → 保留内容 + 一行提示。
- Riverpod 在 `invalidate` 后会把旧值丢掉（刷新失败时 `AsyncValue.value` 为空），
  所以卡片和货架各记一份 `lastGood`：刷新失败不会让整块内容消失。
- 组件参数用"列表 + hasError"而不是 `AsyncValue`：`whenData` 会丢掉加载态携带的
  错误（Riverpod 3 首次失败是 `AsyncLoading` + `hasError`），界面直接读 `hasError` 才可靠。
- 新增 `reading_now_loading@phone_light` 黄金图（骨架态）与 4 条 widget 测试
  （延迟 provider、首次失败 + 重试、刷新失败保留内容、货架失败不炸整页）。
- 设备走查：冷启动 0.9s 截图确认是骨架（不是"还没有在读的书"），4s 后正常出内容。

### FIX-06 列表层进度与系列名

- 领域层 `Book` 增加可选 `seriesTitle`，按真实响应的 `BookDto.seriesTitle` 解析
  （fixture `book_in_progress.json` / `books-search.json` 都有），`withProgress` 保留。
- 书行副标题三档：在读 `p. 5/19 · 19 pages`、读完 `Read · 20 pages`、未读 `21 pages`。
- 继续阅读卡：第一行系列名，第二行 `Vol. 1 · p. 5/12`；没有系列名时退回书名（老数据）。
- 搜索结果的书行补系列名（`Frieren · Vol. 1`），否则一屏都是 "Vol. 1" 分不清。
- 测试：domain 的 `withProgress` 保留系列名、API fixture 解析 `seriesTitle`、
  书行三档文案、搜索结果的系列名、继续卡文案与 a11y 标签；更新
  `reading_now@*` 与 `readlist_detail@eink` 黄金图。

### FIX-07 下载队列持久化

- 新增 Drift 表 `DownloadQueueEntries`（缓存库 schema v2 → v3，`createTable`
  迁移）：bookId / seriesId / name / number / pagesCount / state / done / total /
  createdAt。只存恢复所需的最小书目信息——重启时不一定能联网。
- 队列状态在入队、开始、每页进度、完成/取消/删除时落盘；重启后由
  `downloadQueueProvider` 读回，控制器自动接着下。已下载完的条目、以及
  用户已经手动开始的那一本都会被跳过（不重复入队、不把"下载中"改回"排队中"）。
- 落盘是**尽力而为**：缓存库打不开（平台通道缺失/磁盘满）只影响"能不能恢复"，
  绝不让"点下载"变成没反应；读队列走 FutureProvider，失败是 `AsyncError`
  而不是未捕获异常（裸 `unawaited` 会把整棵 widget 树炸掉，黄金图里当场撞到）。
- 新增"取消全部"（头部按钮，仅在有排队/进行中时出现）：清空排队、取消进行中、
  清掉磁盘队列；已下载的书不动。
- 测试：`downloads_queue_test.dart` 4 条（依次下载、杀进程重启恢复、已下载不重下、
  取消全部）；`pumpSeriesGolden` / `pumpReadListGolden` 补内存缓存库。
- 设备走查：点下载 → 2 秒后强杀进程 → 重启进"已下载的书"，
  显示 `海賊王 卷001 8 / 214` 并在继续跑，头部出现"取消全部"。

### FIX-08 搜索 / 收藏集 / 阅读列表分页

- 五处列表全部改成"按 size 取一页"的 family（与系列书列表同一套思路）：
  搜索结果（系列 + 书）、收藏集、阅读列表、收藏集内系列、阅读列表内书。
  默认一页 `kListPageSize = 30`，点"加载更多"再加一页。
- 新增 `LoadMoreFooter`：`已显示 x / 共 y 条` （items / books / series 三种单位），
  加载完自动消失。以前收藏集/阅读列表都硬取 20 条，第 21 条起静默消失。
- 搜索换词时把 size 重置回一页，不会把上一次的"加载更多"带过去。
- 测试：`pagination_test.dart` 5 条（收藏集、阅读列表、两个详情、搜索），
  用一个**尊重 size** 的假仓库（默认假仓库不切片，测不出截断）。
- 设备走查限制：当前服务器只有个位数收藏集/阅读列表、搜索命中也很少，
  造不出"超过一页"的数据，因此这条只做了 widget 测试；分页是纯客户端逻辑，
  服务端参数（`page`/`size`）已在 `docs/series-queries.md` 与契约测试里覆盖。

### FIX-09 版本号 / 简介按钮 / 标签溢出

- 版本号改读构建产物：新增 `package_info_plus`（ADR 0007），设置页"版本"行显示
  `version (buildNumber)`，开源许可页用同一个版本；读不到/还没读到时回退到
  `kFallbackAppVersion`，不显示空白。
- 简介"展开"只在真的被截断时出现：`LayoutBuilder` + `TextPainter.didExceedMaxLines`，
  短简介不再挂一个永远用不上的按钮。
- 标签超过 3 个收成 `+N`（同形状胶囊），点一下展开全部——以前 `take(4)`
  把剩下的悄悄丢掉。
- 测试：`settings_version_test.dart`（有/无构建号）、`series_header_test.dart`
  新增短简介无按钮、6 个标签显示 `+3` 并可展开；更新 `settings@eink` 黄金图。
- 设备走查：设置页"版本"显示 `0.1.0 (1)`（连的是 APK 真实的 versionCode）。

## W1 实施记录

### QUA-01 拆 `reader_screen` + 清理死代码

- `reader_screen.dart` 560 → 275 行：状态字段与命令（翻页/跳页/分享/隐身/分组/
  键盘/音量键/生命周期回写）搬进 `part` 文件里的 `mixin _ReaderDerive`。
  用 part 而不是"再拆一个 widget"：这些方法要直接读写页码、分屏起点等私有状态，
  拆成 widget 只会变成一长串回调参数；part 与宿主同属一个 library，私有成员照常可见
  （与 `reader_page_turn.dart` 同一套写法）。
- `mixin` 的 `on` 约束加上 `WidgetsBindingObserver`，生命周期回调的 `@override`
  才成立。
- 清掉死代码：`ShelfGrid`（书架页自己建网格，早已不用）与 `RefreshableStatus`
  （空态/错误态改由各页面自己处理）连同不再需要的 import。
- 清掉 8 个未被引用的 ARB key（`readsRightToLeft`…`readFromStart`，其中
  `continueReadingProgress` 是 FIX-06 之后失效的）。
- 验证：55 条阅读器测试 + 黄金图全部不变（零行为变更）；设备上打开第 114/227 页
  照常渲染，滑杆与"剩 113 页"一致。

### A11Y-01 无障碍 + Dynamic Type 2.0

- **2.0× 黄金图**两张：`library@phone_light_text2.0`、`settings@phone_light_text2.0`。
  书架在 2.0× 下自动降成两列、标题换行；设置页副标题多行、卡片自动长高。
- **语义测试**（`a11y_semantics_test.dart` 4 条）：书架封面能被读屏念出系列名、
  顶部三颗动作有 tooltip 语义、设置页开关有可读标签、2.0× 下标题不被固定高度裁掉。
- **点击区**：断言书架图标按钮 ≥44dp（低于这个值手指容易点不中）。
- **减少动态效果**：已有路径——`AppMotion.of(context)` 读
  `MediaQuery.maybeDisableAnimationsOf`，为 true 时全部时长归零（与墨水屏同一分支），
  不需要新增代码；本项只确认它还在。
- **诚实缺口**：
  1. 没有真机 TalkBack 走查（本环境只能用语义树 + 黄金图代替）；
  2. 2.0× 下**底部导航标签会截断成"正…"**、设置页分段控件标签截断成"Syst…/Engli…"。
     都是省略号而非裁切，但确实违反"不截断"的严格标准，记在这里而不是假装通过。
- 设备走查：`settings put system font_scale 2.0` 后重开书架，文字放大、无重叠、
  列表行自动变高；走查后已恢复 `font_scale 1.0`。

### I18N-01 数据层错误文案本地化

- `ShelfFailure` 增加 `ShelfFailureKind`（auth / network / server / protocol /
  certificate / unexpected），每个子类给出自己的 `kind`。数据层从此只保证"是什么错"，
  **不再决定"怎么说"**。
- 新增 `lib/src/l10n/failure_text.dart`：`l10n.failureTitle(kind)` / `failureHint(kind)`
  两张 switch 表 + `failureKindOf(error)`（未知类型一律 `unexpected`，
  **绝不把异常对象拼进界面**）。
- 替换了 8 处直接显示 `failure.message` 的地方：书架错误页、收藏集/阅读列表/收藏详情、
  系列详情 SnackBar、搜索刷新失败、阅读器打开失败页、下载失败状态。
- 新词条 12 条（6 种类 × 标题/建议），中英各一套。
- 测试：`failure_l10n_test.dart` 3 条——每种失败的中英标题都不为空且中文含汉字
  （防止直接抄英文）、`KomgaError` → kind 映射逐个断言、未知错误归 unexpected
  且文案里不含原始异常文本。
- 设备走查：断网后书架显示"离线 · 显示已保存的内容 / 重试"（此前已本地化的横幅）。
  "无缓存 + 请求失败"那种整页错误在真机上不好造（要清数据重登），
  这条由上面 3 条单测覆盖；走查后已恢复网络（`wifi_on` 已确认）。

### PLT-02 平板默认排版

- `ReaderPrefs.tabletLayout`（`auto` / `single` / `double`，默认 auto），设置页"阅读"组
  有对应的一组 chip，提示写清"只在平板上生效"。
- 解析抽成**纯函数** `resolveReaderMode`，优先级从高到低：
  1. 用户显式选过阅读模式（单页/双页/纵向）——系列/书覆盖会落到这里，**永远优先**；
  2. 平板默认排版（非 auto，且设备是平板）；
  3. auto：跟随方向，横屏双页、竖屏单页。
- "不影响手机"是硬条件：桌面断点用 `WindowSizeClass.expanded`（与书架两栏同一个），
  手机即使设了"双页"也不改行为。
- 测试：`tablet_layout_test.dart` 9 条（auto 横竖屏、强制单/双页、手机不受影响 ×2、
  显式模式压过平板设置 ×2、条漫方向、偏好往返、坏值回 auto）。
- 黄金图：`settings@eink` 因新增控件重生成。
- 设备走查：`wm size 1280x800 + density 160` 下打开设置，"阅读"组里
  **平板默认排版**（自动/单页/双页 + 说明）渲染正确；走查后已 `wm size reset`。

### PLT-01 平板书架两栏

- `WindowSizeClass.expanded`（≥1024）时书架变成两栏：左侧 `ShelfSideRail`
  （全部系列 + 每个书库），右侧原来的书架内容。手机上完全不变。
- 选中项直接调 `ShelfController.selectLibrary`，与搜索框旁的库筛选菜单**同一份状态**，
  不会出现"左边选了一个库、右边筛选条还是旧的"。
- 断点判断只在 `WindowSizeClass` 里做（AGENTS.md 不变量 6），页面里不再自己比宽度。
- 与现有 NavigationRail 共存：导航栏在最左（全局导航），库导航在其次（书架内筛选），
  两者语义不同，没有合并。
- 测试：`shelf_two_pane_test.dart` 3 条（390 宽无左栏、1024 宽有左栏且点"Manga"会切换库、
  1366 宽仍是两栏）。
- 黄金图：`library@tablet_dark` 重生成并自查——左栏 Libraries/All series/Manga +
  右侧四列封面，与设备截图一致。
- 设备走查：`adb shell wm size 1024x1600 && density 160` 后重开应用，
  书架页确实变成"库导航 + 书架"两栏，且 NavigationRail 仍在最左。走查后已 `wm size reset`。

### UI-02 收藏集封面拼贴 / 搜索 / 排序

- `CollectionCovers`：最多取 4 张系列封面（走已有的 `seriesCoverProvider` LRU 缓存，
  不新增接口）；0 张用首字母色块（颜色由名字哈希决定，同一名字永远同色），
  1 张单图，2–4 张两列拼贴（拼贴内格子不单独圆角，由外层统一裁）。
- 收藏集页加搜索框 + 排序菜单：名称 / 系列数（降序）/ 最近更新。**在本地排序**——
  收藏集的"系列数""最近修改"都不在服务端排序字段里，与其发一个被静默忽略的参数，
  不如本地说清楚（这条按"API 真值规则"做的选择）。
- **描述**：Komga 的CollectionDto 没有 summary 字段（只有 ReadList 有），
  所以收藏集行显示"N 个系列"；阅读列表那边保留原有 summary 展示。
- 修一个自己引入的 bug：空态先判"搜索无结果"，导致**服务器上一条收藏集都没有时**
  也显示"没有匹配项"，而且搜索框整个消失。改成先判 `items.isEmpty`（"还没有收藏集"），
  只有在有数据但过滤后为空时才显示"没有匹配项"，并且此时搜索框仍在。
- 测试：`collections_covers_test.dart` 4 条（拼贴与系列数、无封面首字母、搜索过滤与空态、
  按系列数排序）。另外 `pagination_test` 里"加载更多"因新增搜索行被顶出屏幕，
  加了 `ensureVisible` 再点。
- 黄金图：`collections@*` 三张重生成并自查（首字母块 / 双格拼贴 / 搜索行）。
- 设备走查：收藏页空态显示"还没有收藏集。"（修复后的正确文案）。当前服务器账号
  没有收藏集，拼贴在设备上没得看，由黄金图覆盖。

### SET-02 本地偏好导出/导入

- `PrefsBackup`（纯逻辑）：`{version, kinds, exportedAt, reader, settings}`。
  导出 = `ReaderPrefs.toJson()` + `AppSettings.toJson()`；导入严格校验
  **顶层是对象 / 有 version / version 相等 / reader 与 settings 都是对象**，
  任何一条不满足就抛 `PrefsBackupException`，**绝不部分应用**。
- **不含凭据**：服务器地址、邮箱、API Key、密码、token 都在安全存储里，从不进备份。
  有一条测试专门断言导出串里搜不到 `apikey/password/token/secret/@/http`。
- 传输方式用**剪贴板**：不引入 `share_plus`/`file_picker`（新增依赖要先写 ADR），
  手机上几千字节的 JSON 复制粘贴比找文件快，而且内容本来就不敏感。
- 写盘时机：两份都**先解析成功再落盘**（`replaceAll` 先 save 再更新 state），
  坏文件不会把当前设置改成半截。
- 设置页新增"备份"组（导出/导入各一行，导入带确认框说明"服务器登录不受影响"）。
- 测试：`prefs_backup_test.dart` 6 条（往返还原、无凭据字段、坏 JSON、缺 version/版本不兼容、
  缺段、字段类型乱写回默认）。
- 设备走查：设置 → 备份 → 导出偏好（提示"已复制到剪贴板"）→ 导入偏好（确认框文案正确）
  → 提示"偏好已导入"。**导出↔导入往返在真机上跑通了**。

### HIS-04 阅读器内阅读时长

- `ReaderPrefs.showSessionTime`（默认开，可关）：设置页"阅读"组有开关，
  也存在偏好里跟着导出。
- 阅读器标题栏页码后面显示 `2–3 / 184 · 1 分`。**只显示分钟**：
  秒级跳动既没有意义，又会逼着每秒重建。
- **不增加每秒 rebuild**：`Timer.periodic(30s)` 只在**分钟数变化时** setState；
  暂停中 `elapsed` 冻结，所以后台回来不会跳。
- 口径与历史一致：`ReadingSessionTracker.elapsed` 和退出时写进 `reading_sessions`
  的是同一个来源（`elapsed` 在 `finish` 之前就是最终时长），不会出现
  "阅读器显示 12 分、历史写着 9 分"。
- 测试：`reading_session_test.dart` 增加 2 条（`elapsed` 与最终会话时长一致、
  暂停时不再增长）；`settings_ia_test.dart` 增加 1 条（开关写进偏好）。
  写测试时抓到 `ReaderPrefs.copyWith` **漏传 `showSessionTime`**——开关点了没反应，
  补上后通过。
- 黄金图：`settings@eink` 因新增开关重生成；阅读器基线不变（黄金图里会话不到 1 分钟）。
- 设备走查：读了约 75 秒后点开 chrome，标题栏显示
  `[Kmoe][地缚少年花… 2–3 / 184 · 1 分` —— 本次时长按要求出现。

### HIS-03 Insights

- 纯计算层 `ReadingStats`（可注入 `now`，不碰 DB、不碰系统时钟）：
  - **当前连续**：今天读过就从今天数；今天还没读、昨天读过就从昨天数
    （否则每天早上一醒来连续天数就归零）；断两天归零。
  - **最长连续**：按日期排序后找最长的一段。
  - **周/月汇总**：时长按分钟向上取整（1 分钟的阅读不该显示 0），本数按 bookId 去重。
  - **热力图**：最近 12 周 × 7 天，每天记时长与读过几本。
  - 坏数据（时长 0、未来时间）跳过。
- `InsightsScreen`（`/insights` 顶层路由）：连续天数/最长连续、本周/本月时长与本数、
  12 周热力图（4 档深浅）；数字用 `progressNumber` 等宽字形；空数据是引导态。
  入口在历史页右上菜单（"阅读统计"）。
- 测试：`reading_stats_test.dart` 7 条（空数据、今天读过、昨天读过不清零、
  断档归零但保留最长、同日多次累加/去重、23:59 与次日 00:01 算两天、坏数据跳过）。
- 黄金图：新增 `insights@phone_light` / `insights@tablet_dark` / `insights@eink`，
  用 15 条造出来的会话渲染（热力图有明显深浅），`insights@phone_light` 已自查。
- 设备走查：**没做成**。阅读器 chrome 会自动隐藏，`adb` 盲点返回箭头连续几次都变成了
  "显示/隐藏 chrome"，最后停在阅读画面。统计页的渲染由 3 张黄金图钉住、
  口径由 7 条单测钉住；"读→统计页"这条端到端留待下次补。

### HIS-02 History 页 + 最近阅读行

- 新增 `/history`（`HistoryScreen`）：玻璃标题栏里就是搜索框；列表**按天分组**
  （今天 / 昨天 / yyyy-MM-dd）；每行封面 + 书名 + `第 a–b 页 · 12m 00s`；
  右侧 ✕ 删单条，右上菜单里"清空历史"（带确认，明确写了"只删本地历史，进度不受影响"）。
  空态有图标 + 标题 + 一句引导。
- "正在读"页新增 `RecentHistoryRow`：最近读过的书按会话时间**去重**横滑（最多 8 本），
  右侧"查看全部"进 `/history`；没有历史时整段不占位置。
- 数据全在本地 `reading_sessions`，不请求服务端——"我什么时候读了什么"是私有信息。
- **踩到一个路由坑**：一开始把 `/history` 和 `/settings` 放进同一个 `StatefulShellBranch`，
  而一个 branch 只能有一个根路由——结果**设置标签点开变成了历史页**，
  `l10n_test` 里"切到 English"直接找不到控件。改成顶层 `GoRoute` 后恢复。
- 测试：`history_screen_test.dart` 5 条（按天分组与页码/时长文案、删除单条、清空并回空态、
  空态、搜索过滤）。
- 黄金图：`reading_now@*` 因新增横滑条重生成（空库时该段不占位置，与基线一致），
  `settings@eink` 因新增"阅读历史"入口重生成。
- 设备走查：进阅读器读了约 16 秒（足以产生一条会话），但**这次没能在设备上翻回设置页**
  ——阅读器返回按钮连续几次没点中，最后停在阅读画面。历史页的渲染与交互由 5 条测试覆盖；
  端到端"读→历史里出现"这条路留待下次设备走查补。

### HIS-01 阅读 session 数据模型

- Drift 新增 `reading_sessions`（schema v5，`if (from < 5) createTable`）：
  bookId / seriesId / bookName / startedAt / endedAt / durationMs / startPage / endPage / completed。
  **为什么单独一张表**：进度只记"读到哪"，记不了"读了多久、读了几次"。
- `ReadingSessionTracker`（纯 Dart，可注入时钟）：`start / note / pause / resume / finish`。
  - 一次阅读只记一条（重复 `start` 忽略）；
  - **最短 10 秒**过滤：翻目录、误点、截图都会进出一次阅读器，记进去 Insights 立刻失真；
  - 切后台 `pause` 把结束时间钉住，回来 `resume` 把暂停区间从时长里剪掉；
  - 暂停期间翻页不改写 endPage。
- 阅读器接入：`initState` 开始计时（起点取书自带进度）、`_setPage` 记页、
  `didChangeAppLifecycleState` 暂停/恢复、`dispose` 结算写入。**隐身模式不记**——
  用户开隐身就是想"这次阅读别留痕"。
- 落库失败只影响"历史少一条"，不打断退出阅读器（`record` 里吞异常）。
- 测试：`reading_session_test.dart` 7 条（单条会话/最短过滤/暂停不计时/暂停中翻页无效/
  重复 start/结算后可再开始、表的写入-倒序-删除-清空）。
- 设备走查：进阅读器 → 返回系列页，无崩溃、进度与界面正常。
  **这次设备上只读了约 4 秒，按 10 秒规则不会落库**，所以看不到历史记录——
  真正的可见验证要等 HIS-02 的历史页。

### SET-01 设置 IA

- 分组重排为：**外观 → 阅读 → 书架 → 服务器 → 存储 → 下载 → 关于**。
- 新增**阅读**组（`SettingsReadingSection`）：阅读模式、翻页动画——把阅读器面板里的
  两个最常改的默认值提到设置里。**只有这两项**：全搬过来会变成第二个阅读设置面板，
  其余（适配/方向/背景/亮度）一次只对一本书生效，本来就该在书里调。
  写的是同一个 `readerPrefsProvider`，所以和阅读器里改完全等价。
- 新增**书架**组（`SettingsLibrarySection`）：网格/列表、封面大小，写
  `ShelfController` 的 setter，与书架顶部那三颗按钮同一份状态。
- **没有连接服务器时书架组不显示**：`shelfProvider` 在未连接时会直接抛
  （"未连接服务器时不应读取书架"），整组隐藏比让设置页炸掉更合理。
- **History/Insights 入口没做**：它依赖 HIS-01..04 的阅读历史数据模型（W4/W5），
  现在放一个点进去是空页面的入口没有意义，等 W4 一起做。
- 版本/构建号、清缓存、开源许可都保留在存储/关于组里（原有实现不动）。
- 测试：`settings_ia_test.dart` 3 条（改阅读模式/翻页动画会写进阅读偏好、
  未连接时不显示书架组、阅读组可达）。另外修了 `settings_servers_test` 的
  `revealKey`：页面里多了横向滚动的分段控件后 `Scrollable.first` 会选错，
  改成对主滚动视图双向拖动。
- 黄金图：`settings@eink` 重生成并自查（外观/阅读/书架/服务器/存储…顺序与内容）。
- 设备走查：设置页三组可见（外观 / 阅读 / 书架），阅读组显示当前"双页 + 平移"
  （与之前阅读器里改的值一致，说明读写同一份偏好）。

### DLD-02 下载队列 UI + 全局反馈

- 下载页标题栏右侧收成一个 `⋮` 菜单（`QueueMenu`）：**暂停/继续**、**重试失败项**、
  **取消全部**、**删除全部下载**（带确认框）。四个动作平铺会把标题挤没，
  而"取消全部/删除全部"不可撤销，放菜单里还能顺手带一句说明。
- `DownloadsController` 新增 `pauseAll` / `resumeAll` / `retryFailed`：
  暂停只挡"从队列取新的"，正在下的那几本自然结束；继续时补位。
- **修掉一个真 bug**：`_runOne` 原来在 `finally` 之后无条件 `_clear(book.id)`，
  失败状态被立刻抹掉 —— 用户看不到哪本没下下来，"重试失败项"也没有对象可重试。
  现在只有成功/取消才清，失败保留在列表里。
- 空态补了一句说明（"在系列页下载一本书，它就会出现在这里，离线也能读"），
  不再只有一行标题。
- **关于"全局进度条/完成提示"**：没有做浮层式的全局 progress/toast——阅读时弹一条
  "下载完成"正是要求里说的"不打扰阅读"要避免的。现在的做法是：每本在列表/系列页
  显示自己的进度，下载页标题栏的菜单里能看到队列动作。这是一处**有意不做**，
  理由写在这里。
- 测试：`download_queue_controls_test.dart` 3 条（暂停后不启动新的/继续后补位、
  失败保留并可重试、取消全部后不再下载）。
- 黄金图：`downloads@*` 因标题栏换成菜单重生成，`downloads@phone_light` 已自查。
- 设备走查：设置 → 已下载的书，右上角 `⋮` 打开有"删除全部下载"。
  （暂停/重试要在有进行中或失败项时才出现，这台设备当前没有队列。）

### DLD-01 下载设置

- `AppSettings` 新增三项：`downloadWifiOnly`、`downloadAutoDeleteRead`、
  `downloadConcurrency`（1–3，存档里越界或类型不对会被夹回/回默认）。
  设置页多一个"下载"分组（两个开关 + 1/2/3 分段控件），改完让
  `downloadPolicyProvider` 失效。
- **仅 Wi-Fi**：`komga_platform` 新增 `NetworkProbe`（不引入任何依赖），
  用 `dart:io` 的网卡名做**启发式**判断（`wlan*`/`en0` = Wi-Fi，
  `rmnet*`/`ccmni*`/`pdp_ip*` = 蜂窝）；判断不出来时 `unknown` → **放行**。
  拿不到网络信息就把用户拦住，是最难排查的那类问题。
  拦截发生在两个入口（系列批量下载、单本下载按钮），提示"已开启仅 Wi-Fi 下载…"。
- **并发数**：`DownloadsController` 从"一次一本"改成 `_running` 集合 + 最多 N 个
  并行 worker，每本下完自动补位；`cancelAll` 也改为取消整个 `_running` 集合。
- **读完自动删除**：标记已读后按策略删掉该本的下载。**现在的触发点是"用户标记已读"**
  （单本菜单/批量），不是"阅读进度自然读完"——那条路径在同步层、暂时没有回调点，
  这一点在代码注释和这里都写明了，不假装是全自动。
- 策略读取一律用**同步** `value`（读不到就放行/保持默认）：`await .future` 会让
  "点下载"卡在一次设置读取上，而设置读不出来（平台通道缺失、存档损坏）时下载仍应可用。
  这个决定是被 `download_button_test` 的三个失败逼出来的。
- 测试：`download_policy_test.dart` 5 条（默认值与存档往返、并发数夹取、蜂窝拦截、
  unknown 放行、并发 2 时两本同时开跑并自动补位）。
- 黄金图：`settings@*` 因新增"下载"分组重生成，`settings@eink` 已自查。
- 设备走查：设置页"下载"分组三项齐全（仅 Wi-Fi / 读完自动删除 / 同时下载数 1·2·3）。

### SCH-03 搜索分页 + 结果系列名

- FIX-06/FIX-08 已经把"书结果显示 `系列名 · 书名`"和"加载更多"做掉了；这一项补的是
  **失败行为**与查询切换的干净度：
  - `_lastSeries` / `_lastBooks` 记住上一次成功的结果：翻页失败时**不清空**，
    顶部只多一条"刷新失败，显示的是上一次的结果"的提示。翻页失败就整页变错误、
    用户刚才翻到的那屏凭空消失，比"没加载出来"更让人困惑。
  - 换搜索词、换阅读状态、换标签都复位 `_size` 并清掉缓存的旧结果——
    否则新查询会用旧条数去请求，或者把上一次的列表当成这次的结果显示。
- 测试：`search_paging_test.dart` 3 条（分页：size 30/60/90 分别拿到 30/60/65 条；
  切换查询不串；翻页失败时旧结果还在且出现提示条）。
- 设备：本机服务器只有 ~11 个系列，一页就装得下，**没法在设备上触发"加载更多"**；
  分页与失败保留由上面 3 条测试覆盖（其中失败那条是真的拖到底点了一次"加载更多"）。
- 没有新增黄金图：搜索结果态在 SCH-02 里已经说明拿不到基线（真搜会拉起 Drift 缓存，
  黄金图环境没有 path_provider）。

### SCH-02 搜索 facets

- 先 spike（对照组方法，见 `docs/series-queries.md` 的判定方式）：
  - `read_status` 与 `search` 组合**验证通过**（Frieren 已读 → UNREAD 返回 0、READ 返回 1）；
  - `tag` **验证通过**：先 `PATCH /series/{id}/metadata` 写入 `tags:["VerifyTag"]`，
    `tag=VerifyTag` 只返回那一部，`tag=NotATag` 返回 0（正负对照都成立）；
  - `author` **不支持**：`author=Verify Author` 与 `author=NobodyHere` 返回完全一样（全部 5 部），
    服务端静默忽略 → 按 API 真值规则**不做作者筛选**，代码注释与本文都写明了原因。
- 搜索页新增 `SearchFacets`：阅读状态四颗 chip（全部/未读/在读/已读）+ **标签 chip**
  （从"未加标签筛选"的结果里按出现次数聚合前 6 个，Komga 没有 facets 接口），
  可单点筛选、再点取消、"清除"一键复位。
- `SearchQuery` 扩成 `(query, size, readStatus, tag)`，任一变化自动重查；
  `KomgaUrls.series(..., tag:)`、`fetchSeries`、`LibraryRepository.series` 都加了 `tag`。
- 测试：`search_facets_test.dart` 3 条（URL 带 `tag` 且无 tag 时不写、阅读状态带到服务端并
  可清除、标签 chip 来自聚合且可筛选/取消）。
- **没有搜索结果态黄金图**：真搜一次会拉起 Drift 缓存，黄金图环境没有 `path_provider`
  （`MissingPluginException`），强行 mock 一层不值得。facets 由上面 3 条 widget 测试覆盖，
  这里如实记录缺一张基线。
- 设备走查：搜 "e" → 顶部出现"筛选"与四颗状态 chip（全部带 ✓），下面正常出系列与书籍结果。

### SCH-01 搜索历史 + 空态

- `AppSettings.searchHistory`（最多 10 条，最新的在前）+ `withSearchTerm/withoutSearchTerm/clearSearchHistory`；
  存档容错：非字符串、空串、重复项一律丢弃。
- 只在**用户按下搜索键**或点历史/建议时记录，不在防抖里记——否则打 "frieren" 的过程中
  会把 "fri"、"frie" 也存进历史。
- 空态重做（`SearchEmptyState`）：有历史 → "最近搜索" + 清空 + 每条右侧 ✕；
  没历史 → 图标 + 标题 + 说明，并用"正在读"的系列名给出可点的建议胶囊。
  **为什么不用热门标签**：没有可靠的"热门"接口，按 API 真值规则不编。
- 踩坑：空态一开始是 `ListView` 塞进 `SliverFillRemaining(hasScrollBody: false)`，
  直接触发 `RenderViewport does not support returning intrinsic dimensions`；
  改成 `SliverToBoxAdapter` + `Column`，滚动交给整页。
- 测试：`search_history_test.dart` 5 条（去重/上限/空白词、单删与全清、存档往返与坏条目、
  空态列出历史并可回填搜索、删除与清空会落盘并回落到引导态）。
- 黄金图：新增 `search_history@phone_light`，`search@*` 因空态改版重生成，两张都自查过。
- 设备走查：搜 "frieren"（该服务器无结果）→ 点输入框的 ✕ 清空 → "最近搜索"里出现
  `frieren`，带 ✕ 与"清空"。

### UI-01 玻璃层级 / 阴影 / 字体克制

- **下载页标题栏从三件套降到一层**：原来是「返回圆球 + 标题胶囊 + 取消圆球」并列，
  现在整条只有一个 `GlassSurface`，返回、标题、"取消全部"全在胶囊里
  （`downloads@*` 黄金图已自查：白底上只剩一条玻璃）。
- **浅色模式浮层阴影降一档**：新增 `AppShadows.floatingLight`（0x0D/0x1A，blur 3/20），
  `AppShadows.floatingOf(context)` 按主题取；`GlassSurface` 的 `shadows` 改为可空、
  默认走它。之前白底上是 0x2E + blur 32，糊成一圈灰边、看起来像"脏"而不是"浮起来"。
- **新增 `AppTypography.progressNumber`**（等宽数字 + w600），用在三处**会原地变化的数字**上：
  阅读器顶栏页码、系列头部"已读 N / M"、下载行"3 / 12"。不用等宽的话
  "9 / 12" → "10 / 12" 会让整行左右抖。
- 书架顶部在 LIB-01 时已经收敛到"搜索胶囊 + 三颗裸图标"（一层玻璃），这里不再改动。
- 黄金图：**全量重生成**（36 张受影响：所有用 `GlassSurface` 的页面阴影都变淡了），
  逐张抽查了 `library@phone_light`（搜索胶囊阴影明显变软）、`downloads@phone_light`、
  `series@phone_light`、`nav_bar@*`。
- 设备走查：设置 → 已下载的书，标题栏确实只有一条（e-ink 下是一条描边框，
  里面是返回箭头 + 标题，没有独立圆球）；书架/系列页阴影同样变淡。
- 低端 Android 帧率：没有在真机上量（模拟器不代表低端机），这里只做了"减少阴影层数"
  与"不新增 BackdropFilter"两项——`GlassSurface` 仍然只给常驻浮层用。

### SER-03 系列下载全部 / 未读 N 本

- 系列页右上多一个"下载"圆球：**下载全部** / **下载 1·5·10 本未读**，未读为空时后三项置灰。
  先弹确认框（"下载 N 本？会逐本排队；已下载过的会自动跳过"）再入队——
  一次可能排进几十本，误触的代价是几百兆流量。
- `DownloadsController.startMany(books)`：跳过**已下载**（查服务层）、**已在队列**、
  **正在下载**的，返回 `(queued, skipped)`；入队后按原有单本流程逐本下，
  完成后清队列行（沿用 FIX-07 的落盘队列）。
- 入队后的 SnackBar 写清"已排队 N 本"或"已排队 X 本，跳过已下载 Y 本"，
  并带一个"取消"直接 `cancelMany(ids)`——只撤掉这次入队的，不动别的。
- **修掉一个 l10n 撞名**：我新加的 `downloadQueued`（带 count 参数）和已有的无参
  `downloadQueued` 重名，生成代码里后者被覆盖，下载管理页编译报
  "Object 不能赋给 String"。改名 `downloadBatchQueued` 后恢复。
- 测试：`series_batch_download_test.dart` 4 条（全部入队并清队列、已下载跳过并如实回报、
  同一批重复提交不会下两次、取消后不再下载）。假服务在 `download()` 里也要记录
  "已下载"，否则"跳过已下载"这条规则在测试里根本没被验证。
- 黄金图：`series@*`、`series_loading@*` 因新增下载圆球重生成，`series@phone_light` 已自查。
- 设备走查：下载菜单四项齐全；点"下载 5 本未读"弹出确认框（标题/说明/取消/下载）。
  **没有真的在模拟器上跑完 5 本下载**（流量与时间），入队/去重/取消由 4 条单测覆盖。

### SER-02 系列书多选 / 批量 / 标记之前所有

- `BookSelectionState { active, ids }` 与书架的 `ShelfSelection` **分开**：宽屏两栏时两者
  可能同屏存在，共用一个 provider 会让"书架勾了两个系列"串到系列页的书上。
- 入口同样是工具条上的"选择"按钮（与 LIB-03 一致，长按仍留给单本菜单）；
  进入后工具条换成"已选 N 本 / 全选 / 取消"（复用 `ShelfSelectionBar`，多一个
  `countLabel` 让书架说"个"、系列页说"本"），底部 `persistentFooterButtons` 放批量条。
- 长按书行新增"标记之前所有为已读/未读"：按**当前顺序**取这本书之前的所有书。
  第一本书没有这两项。
- 批量标记逐个调用 `bookReadProvider`，失败不中断，结束后 `invalidate` 书列表与详情
  （书列表是"本地进度叠加"出来的，不刷新会留旧状态），统一提示"N 本已更新"。
- **修掉一个会做错事的 bug**：书行菜单原来用 `bool` 当动作值，单本"标记已读"和
  "之前所有为已读"都是 `true`——点"之前所有"会被当成"只标记这一本"。
  改成 `BookMenuAction` 枚举后两组动作彻底分开（测试先失败才暴露）。
- 测试：`series_book_selection_test.dart` 4 条（勾选不跳转、全选+批量逐本调用并退出、
  长按第 3 本只标记前两本、第一本没有"之前所有"）。
- 黄金图：`series@*` 因工具条多一个"选择"图标重生成（`series@eink` 已自查）。
- 设备走查：点"选择"→ 工具条变"✕ 已选 1 个 / 全选"，选中行高亮，
  底部"标记全部已读/未读"在导航条之上显示正常。

### SER-01 系列书列表排序 / 筛选

- 先 spike 再上线（同一个对照组方法）：`metadata.numberSort,asc|desc` **验证通过**
  （正反序对称）；`createdDate` / `metadata.releaseDate` 在本机库上无法与默认顺序区分
  （同系列几本书 createdDate 相同），按 API 真值规则**暂不上线**；
  `read_status=UNREAD|READ|IN_PROGRESS` 在 `/series/{id}/books` 上**验证通过**。
- 新工具条 `SeriesBooksToolbar`：左边"N 本"，右边排序 + 筛选两个玻璃菜单，
  带筛选时多一个"清除"。窄屏/宽屏共用同一个工具条（`toolbar` 传进两个 pane）。
- `SeriesBooksQuery` 从 `(seriesId, size)` 扩成 `(seriesId, size, sort, readStatus)`：
  任意一项变化就是一个新的 family key，自动重新请求，不需要手动 invalidate。
- 空态区分：有筛选时是"没有符合筛选的书 / 清除筛选可以看到这个系列的全部书"，
  而不是"这个系列还没有书"。
- 测试：`series_books_toolbar_test.dart` 4 条（总本数、按卷号降序**查数据层顺序**、
  筛选未读后条数变 2、筛到空结果的文案与清除）。这里踩了个坑：
  书行标题其实是 `#1 · Vol. 1` 一个 Text，`find.text('Vol. 1')` 永远匹配不到——
  排序断言改成直接读 provider 的数据。
- 黄金图：`series@*` 因新增工具条重生成，`series@phone_light` 已自查（"6 books" + 两个图标）。
- 设备走查：系列页工具条在（"10 本" + 排序/筛选图标）。**筛选/排序的下拉在设备上没点通**
  （两次点在图标之间的空隙），交互行为由上面 4 条 widget 测试覆盖。

### LIB-04 排序补充 + 保存筛选组合

- **先做 spike，再决定**：在本机 Komga 1.30.1 上用"随机属性当对照组"的方式复验
  （`sort=bogusField,desc` 返回 200 且是默认顺序 —— 说明"200"不能证明排序生效）：
  - `booksUnreadCount` / `booksReadCount` / `readProgress.lastModified` / `readProgress.readDate`
    **全部不支持**（把 Frieren 标成 0 未读 / 2 已读后，它们仍把 Frieren 排在最后）；
  - `booksCount` / `createdDate` / `metadata.titleSort` / `booksMetadata.releaseDate` 生效。
  - 记录在 `docs/series-queries.md` 的"LIB-04 复验"一节。
- 由此：**不新增**"未读数 / 阅读进度 / 最近打开"三种排序（没有服务端支持）；
  并**删掉 `SeriesSort.recentlyRead`**——它一直是空操作，之前的"验证"无法与默认顺序区分，属误判。
- 新增**保存筛选组合**：`ShelfFilterPreset { id, name, sort, readStatus, libraryId }`，
  存在 `AppSettings.filterPresets`（按服务器 baseUrl 分区，最多 8 条，同 id 覆盖）。
  筛选菜单里"保存当前筛选"（无筛选时置灰）→ 命名 → 菜单里出现"应用/删除"两项。
- 测试：`shelf_filter_preset_test.dart` 8 条（模型 JSON 与坏条目容错、按服务器分区、
  同 id 覆盖与 8 条上限、删除、存档往返、控制器保存/应用/删除、空名字与无筛选不存）+
  `shelf_filter_menu_test.dart` 3 条（无筛选时置灰、保存后应用、删除）。
- 顺带修一个真 bug：命名对话框在 `showDialog` 返回后立刻 `dispose` 控制器，
  退场动画里的 `TextField` 再次使用它 → "used after being disposed"。改成由对话框
  自己的 StatefulWidget 持有控制器。
- 黄金图：`library_sort_menu@*` 因少了一项重生成（已自查）。
- 设备走查：筛选菜单里"保存当前筛选"在无筛选时置灰；选"在读"后书架变 8 个系列、
  顶部出现 `在读 ✕` chip、筛选图标高亮。

### LIB-03 书架多选 / 批量

- **入口是顶部工具条的"选择"按钮，不是长按**。计划里写的是"长按进入多选"，
  但长按在书架上已经是系列菜单（标记已读/置顶/详情），一个手势不能同时做两件事；
  竞品 Panels 也是"长按出菜单、多选走按钮"。这一处是**有意的偏离**，理由记录在此。
- `ShelfSelectionState { active, ids }`：把"在多选态"和"选了几项"分开——
  刚进多选时一项都没选，用"非空即多选"会让批量条一进来就消失。
- 顶部换成 `ShelfSelectionBar`（✕ / 已选 N / 全选），底部 `persistentFooterButtons`
  放 `ShelfBatchBar`（标记已读 / 未读），并抬到悬浮导航条之上（否则点不到）。
- 批量标记逐个调用（Komga 的"整系列已读"本身就是按系列的），失败项不中断，
  结束后统一提示"已更新 N 个"或"N 个成功，M 个失败"。下载按计划等 SER-03。
- **把页面拆开了**：`library_screen.dart` 在 LIB-02 后已 371 行（超 350 上限），
  现在拆成 `library_screen_shelf.dart`（内容区三态与网格/列表）+
  `library_screen_batch.dart`（批量操作 mixin），页面本体 250 行左右。
- 顺带修掉两个真 bug：
  1. `PressableScale` 在卡片被重建/销毁后收到 pointerUp 会用已 dispose 的
     `AnimationController` 播放动画 → 直接断言崩溃（真机上"点一下就跳页"的卡片必踩）；
  2. `showContextMenu` 的 `RelativeRect.fromLTRB(dx, dy, dx, dy)` 等于告诉
     `showMenu`"可用空间为 0"，菜单会被裁到只剩前两项；现在按屏幕剩余空间算。
- 测试：`shelf_selection_test.dart` 4 条（进入多选后点卡片是勾选、全选/取消、
  批量标记逐个调用并退出、失败项不影响其余项）；`context_menu_test` 更新为
  四项菜单并改用 `skipOffstage: false` 之外的正常断言（菜单不再被裁）。
- 黄金图：新增 `library_selection@phone_light`（多选态 + 底部批量条），
  `library*` 因新增"选择"按钮重生成。
- 设备走查：点"选择"→ 顶部变"✕ 已选 1 个 / 全选"，选中行带描边，
  底部批量条在导航条之上显示正常。

### LIB-02 未读角标 + 置顶

- 封面**左上角**未读数角标（`UnreadBadge`）：右下角已经是"已读/总数"，
  两个数字挤一起像一串；左上角只表达更紧急的那件事——还剩几本没看。
  未读为 0 时不画。
- 置顶：Drift 新表 `PinnedSeriesRows(serverId, seriesId, createdAt)`（schema v4，
  `if (from < 4) createTable`）。按 **serverId 分区**，同一台机器连过多个 Komga 也不串；
  重复置顶走 `insertOnConflictUpdate`，不会出现两行。
- 置顶区单独渲染：`pinnedSeriesProvider` 按 id 逐本取元数据（个位数，通常是 cache 命中），
  主列表把已置顶的剔掉——否则同一个系列会出现两次。**为什么不用"在已加载列表里排序"**：
  书架是服务端分页的，置顶的那本很可能还没加载到，那就等于没置顶。
- 长按菜单加"置顶/取消置顶"（按当前状态显示其中一项）。
- 测试：`pinned_series_test.dart` 5 条（置顶/取消/顺序、切服务器不串、重复置顶不产生两行、
  角标数量与"读完不显示"、置顶后进置顶区且主列表不重复出现）。
- 黄金图：`library*`、`collection_detail@*`、`reading_now@*` 共 16 张重生成
  （角标出现在所有用 `SeriesShelfTile` 的地方，属预期变化），`library@phone_light` 自查。
- 设备走查：列表视图每行封面左上角都有未读数（30/10/42/81/17/1/8…）。
  **置顶没有在设备上点通**：长按没稳定命中（几次落在行间滚动了列表），
  置顶的读写与分区由上面 5 条测试覆盖，这里如实记录设备侧缺这一步。

### LIB-01 书架标题 / 计数 / 筛选状态 / toolbar 收敛

- 大标题 `书架` + `N 个系列`（`state.totalElements`）作为**内容的第一行**，
  跟列表一起滚走——不是钉住的装饰条。iOS 大标题就是这个行为：往下滑时让位给内容，
  窄屏与 1.3× 字号下都不会挤（标题 `Flexible` + 省略号，计数是 `bodySmall`）。
- 新增 `ShelfActiveFilters`：把**生效中**的排序 / 阅读状态 / 库筛选摊成可单独清除的
  chips，两个以上条件时多一个"清除全部"。以前这些都藏在三个图标的下拉里，
  用户只看到"书少了"却不知道是哪一项在起作用。
- "排序 / 筛选 / 视图"三颗动作去掉独立玻璃底：搜索框是这一行唯一的玻璃元素，
  页面顶部从两层玻璃降到一层（这一步也顺带完成 UI-01 的一半）。
- 测试：`shelf_active_filters_test.dart` 3 条（无筛选不显示、三种条件各生成 chip
  且可单独清除、两个以上出现"清除全部"并真的清空）；`shelf_polish_test` 的
  "顶部只有搜索框"改为"搜索框+动作钉住、大标题随内容滚走"。
- 黄金图：`library*` 全部重生成（12 张），`library@phone_light` 自查：
  搜索胶囊 + 三颗裸图标 / `Library 6 series` / 库筛选条 / 网格。
- 设备走查：`书架 11 个系列` + 生效中的 `标题 Z-A ✕` chip 都在（e-ink 主题下）。

### RDR-06 双页分组持久化

- `ReaderPrefs` 增加 `spreadFrom`（bookId → 0 基页码）+ `withSpreadFrom(bookId, index?)`：
  `index` 为 null 或负数表示恢复自动（同时删掉该条目，不留脏数据）。
- 按**书**记而不是按系列：同一系列不同卷的排版可能不同；换书不会串。
  `configOnly()` 会丢掉它——它是"这本书的排版修正"，不该被存进预设或系列覆盖。
- 阅读器里 `_spreadFrom` 从会话字段改成从偏好 `read` 的 getter；长按缩略图
  改为 `setSpreadFrom(...)` 落盘（原来只 `setState`，退出就丢）。
  重建由 `ReaderScreen.build` 对同一个 provider 的 watch 负责，getter 用 `read`
  （它也会在事件回调/进度回写里被调用）。
- 存档容错：`spreadFrom` 只收"非空字符串 key + 非负 int"，非 Map / 类型不对 /
  负数 / 空 key 一律丢弃；单测覆盖这几种坏存档。
- 测试：`reader_spread_from_test.dart` 6 条（写入/覆盖/清除、坏存档容错、
  不进预设快照、系列覆盖不影响、控制器落盘、长按设定后"重进"仍是 [2,3]）。
- 设备走查：双页模式切换生效（112–113 → 114–115 的跨页标注变化），但**长按缩略图
  在真机上没稳定命中**（几次落在缩略图间隙，变成了跳页）。分组落盘与重进保持
  由上面 6 条测试覆盖，这里如实记录设备侧没有完成该项的端到端确认。

### RDR-05 翻页动画选择

- `ReaderPageTurnChoice { curl, slide, fade, none }` 落进 `ReaderPrefs`（含 JSON、
  `copyWith`、`==`/`hashCode`、交互组重置），设置面板"交互"组多一项"翻页动画"。
- `PageTurnStyle.resolve` 改成"用户选择 + 环境"：墨水屏、系统"减少动态效果"、
  或 token 时长被压成 0 时一律瞬切——用户选了卷页也不该在墨水屏上播动画。
  时长不再写死 400ms，由调用方传 `AppMotion.of(context).emphasized`（450ms）。
- 新增 `PageTurnEffect.fade`：当前屏整体淡出露出相邻屏；卷页计划只在选了 curl 时
  才准备（平移/淡入不需要纸面位图）。
- **修掉一个会静默吞掉设置的 bug**：`ReaderPrefs.==` 漏了 `pageTurn`（`hashCode`
  里有、`==` 里没有）。后果是只改翻页动画时 `_update` 判定"没变"直接 return——
  状态不落盘、界面也不刷新。是写测试时"设置改了但 store 还是 null"暴露出来的。
- 顺带把 `readerPrefsProvider` / `readerBookProvider` 的 watch 从 `ReaderPagesGate`
  的 builder 里提到 `ReaderScreen.build`：写在 builder 里时，偏好恢复不一定会
  让这一层重建（同一个 bug 的另一半症状）。
- 测试：`page_turn_style_test.dart` 8 条（四档映射、墨水屏/减少动效/零时长强制瞬切、
  时长来自 token、控制器落盘、选择传到绘制层、墨水屏即使选卷页也瞬切）、
  `reader_settings_sheet_test.dart` 加一条"交互组里选淡入会落盘"。
- 黄金图：`reader_settings@*` 因新增分组项更新；`reader_curl*` 的帧时刻按新的
  450ms 等比换算（`cold_under_reveal` 一张基线随之更新，原因是时长变了，
  不是卷页本身变了）。
- 设备走查：交互组里四项齐全，选"平移"后高亮与说明同步。

### RDR-04 阅读设置分组 / 重置 / 适配预览

- 完整面板按 **页面 / 布局 / 颜色 / 交互** 四组排，每组标题右侧有"重置"：
  只把这一组打回默认，其它组原样保留；已经是默认值时按钮置灰。
  数据层加 `ReaderSettingsGroup` + `ReaderPrefs.resetGroup/isGroupDefault`，
  控制器 `resetGroup(group, seriesId:)` 复用同一套"按系列优先"的写入规则。
- 顶部加摘要：`当前 · 跟随书籍 · 适应屏幕 · 跟随系列（· 黑色背景）`，不开任何一组
  也知道现在是什么组合。
- 适配方式每行左侧加 4 个小示意图（`ReaderFitPreview`）。这里有个诚实的限制：
  页面长宽比固定时，"填满屏幕"和"适应宽度"的**裁剪结果**天然一样，真正的差别是
  能往哪拖——所以后两种各多画一个 ↕ / ↔ 箭头，而不是编一个不存在的视觉差异。
  墨水屏只画线框（灰阶屏上填充块会糊成一片）。
- 拆出 `reader_settings_group.dart`（组标题、开关行、跳页滑条），
  面板从 366 行降到 326 行，仍在 350 以内。
- 测试：`reader_settings_groups_test.dart` 6 条（四组各自只重置自己、重置后
  `isGroupDefault` 为真、系列覆盖的重置只影响那个系列）、
  `reader_settings_sheet_test.dart` 5 条（摘要、四组按钮的启用状态、点重置只影响
  颜色组、示意图数量与 e-ink 调色板、墨水屏没有背景组）；
  更新 `reader_settings@*` 与 `reader_settings_presets@*` 黄金图。
- 设备走查：四组标题与"重置"都在，"交互"组因为锁定缩放开着而是亮的、
  其它三组置灰；适配方式四行各有示意图（墨水屏为线框 + 方向箭头）。

### RDR-03 顶栏 IA + AA 快捷设置

- 顶栏收成 4 槽：返回 / 标题（书名右侧带 `x / y` 页码）/ `AA` / `⋯`。
  目录、隐身、页面缩略图、阅读设置、分享本页全部进"⋯"菜单——6 颗图标挤一条时
  每颗的点击区都掉到 40pt 以下，比多一次点击更难受。
- `AA` 打开新的 `reader_quick_settings_sheet`：亮度、背景、方向、适配、锁定缩放，
  紧凑胶囊 + 滑杆，一屏放得下；墨水屏不显示背景（固定白底）。
- 新增 `reader_bar.dart`（原 `ReaderBar` 从 `reader_chrome.dart` 拆出），
  菜单项的 key 沿用旧的按钮名（`reader-settings-button` 等），测试只要"先开菜单"
  就能照旧点到；主壳换成 `reader-more-button` / `reader-quick-settings-button`。
- **修掉一个顺带发现的 bug**：快捷设置一开始无条件把改动写成"按系列覆盖"，
  即使这个系列没开"按系列记住"——用户会看到"改了只有这一本生效"。
  现在与完整面板同一条规则：只有已经存在系列覆盖时才写覆盖。
- 测试：`reader_quick_settings_test.dart` 5 条（AA 改背景/方向/适配/锁定缩放、
  墨水屏无背景、菜单五项齐全、顶栏只剩三颗常驻按钮）；`reader_harness` 新增
  `openReaderMenu` / `tapReaderMenu` / `openQuickSettings` / `openPages`，
  旧的 `reader-*-button` 调用点统一改走菜单；新增黄金图
  `reader_quick_settings@phone_dark`，并更新全部 `reader@*`。
- 设备走查：顶栏四个槽位；`AA` 里选"填满屏幕"后页面立即铺满（没进完整设置）；
  `⋯` 菜单五项齐全。

### RDR-02 阅读器目录

- 顶栏新增"目录"按钮（系列未知时——深链且书还没回来——按钮不出现），打开
  `reader_toc_sheet`：列出本系列的书（`seriesBooksProvider` 取 300 本），
  当前这本高亮 + `当前 · 第 x/y 页`、其余显示页数/已读。
- 打开时**定位到当前书**：先按固定行高给一个初始偏移，首帧后
  `Scrollable.ensureVisible` 精确滚进视野（24 本里的第 20 本会被滚到屏幕内）。
- 点另一本走 `pushReplacement` 并沿用当前阅读方向：连读十本不压返回栈，
  返回仍然是系列页（设备上已确认）。
- 测试：`reader_toc_test.dart` 3 条（列表与高亮、滚动定位、替换而不是压栈）。
- 未做黄金图：把面板单独摆出来时它没有 `FrostedSurface` 背景（真机由
  `showModalBottomSheet` 提供），渲染出来是白底白字；改用真实入口又受
  golden harness 的 `find.byType(MaterialApp)` 截图范围限制。面板的材质与
  `reader_settings@*` 同一套且已被那组黄金图覆盖，这里以 3 条 widget 测试为准。
- 设备走查：目录列出 42 本的系列、当前书标注 `当前 · 第 114/227 页`；
  点第 2 本切到卷02（1/238），返回直接回到系列页。

### RDR-01 阅读器页码滑杆 + 剩余页

- 底部新增 `ReaderPageSlider`：1..total 拖动跳页，只在跨页时触发跳转 + 触感
  （逐像素回调会让进度写入和触感都爆炸）；拖动中用本地值，父级重建不会抖动。
- RTL 时滑杆整体 `Directionality.rtl`：日漫的最小页在右边，拖动方向与阅读方向一致。
- 底栏不再重复"第 x 页"（顶栏已有 `x / y`），改成"剩 N 页"（ICU plural：
  0 → "Last page"、1 → "1 page left"）。`ReaderLayout.remaining` 按"当前屏之后"算，
  双页跨页时不会把同屏的第二页算进剩余。
- 测试：`reader_screen_test` 新增/改写 4 条（剩余页文案随翻页变化、双页到书末、
  拖滑杆跳到最后一页、RTL 时 Directionality 翻转）；更新全部 `reader@*` 黄金图。
- 设备走查：227 页的书，滑杆从第 1 页拖到第 114 页，页标与"剩 113 页"同步更新。

## W0 出口（P0 全绿）

9 项 P0 全部完成并逐条推送：FIX-01…FIX-09。每项都过了
`dart run tool/ci.dart check`（格式 + 分析 + 分层 + 全部测试 + 黄金图）与
`dart run tool/ci.dart install` 真机走查。
已知未覆盖：FIX-03 的"搜索/阅读列表入口"与 FIX-08 的分页在**这台服务器**上
造不出所需数据（见各条备注），改由 widget 测试钉住。
