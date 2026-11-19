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
| LIB-04 | 排序补充 + 保存筛选组合 | P1 | TODO | — |
| SER-01 | 系列书列表排序/筛选 | P1 | TODO | — |
| SER-02 | 系列书多选/批量/标记之前所有 | P1 | TODO | — |
| SER-03 | 系列下载全部/未读 N 本 | P1 | TODO | — |
| UI-01 | 玻璃层级/阴影/字体克制 | P1 | TODO | — |

## W3 搜索/下载/设置

| ID | 需求 | P | 状态 | commit |
|---|---|---|---|---|
| SCH-01 | 搜索历史 + 空态 | P1 | TODO | — |
| SCH-02 | 搜索 facets（状态/标签/作者） | P1 | TODO | — |
| SCH-03 | 搜索分页 + 结果系列名 | P1 | TODO | — |
| DLD-01 | 下载设置（仅 Wi-Fi/读完删除/并发） | P1 | TODO | — |
| DLD-02 | 下载队列 UI + 全局反馈 | P1 | TODO | — |
| SET-01 | 设置 IA（Reader/Library/Downloads/History/About） | P2 | TODO | — |

## W4 历史/收藏/备份

| ID | 需求 | P | 状态 | commit |
|---|---|---|---|---|
| HIS-01 | 阅读 session 数据模型 | P2 | TODO | — |
| HIS-02 | History 页 + 最近阅读行 | P2 | TODO | — |
| SET-02 | 本地偏好导出/导入 | P2 | TODO | — |
| UI-02 | 收藏集封面拼贴/描述/搜索 | P2 | TODO | — |
| PLT-01 | 平板书架两栏 | P2 | TODO | — |

## W5 深度/平台

| ID | 需求 | P | 状态 | commit |
|---|---|---|---|---|
| HIS-03 | Insights（连续天数/热力图/统计） | P2 | TODO | — |
| HIS-04 | 阅读器内阅读时长 | P2 | TODO | — |
| PLT-02 | iPad 默认双页/阅读布局 | P2 | TODO | — |
| I18N-01 | 数据层错误文案本地化 | P2 | TODO | — |
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
