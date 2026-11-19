# UI 精致化与功能对齐开发计划（对标 Panels）

> **2026-11-19 收尾**：P0 6/6、P1 7/7、P2 8/8、P3 14/14 全部落地；P2 的 3 处缩水（Hero / 边缘返回 / 排序与捏合）也已补齐。
> 逐项功能对比、UI 细节对比与建议批次见 [panels-comparison.md](panels-comparison.md)。

> 写于 2026-11-18。来源：对 Panels（iOS 漫画阅读器）官方指南、官网、博客与社区的调研，
> 加上对本仓库代码的逐项盘点。目标是把现在"能用但朴素"的标准 Material 3 界面，
> 做成接近 iOS 原生质感的阅读体验。
>
> 范围约束：只做和 **Komga 场景**相关的部分。本地导入、网盘、商店、Panels 账号同步不在范围内。
> 每个需求都必须给出**墨水屏退化方案**。墨水屏不是"关掉动画的深色主题"，见 `docs/a11y-and-input.md`。

## 0. 结论先行

Panels 的高级感主要来自三点，和控件本身关系不大：

1. **克制**："The library is the surface, the reader is the product"。
   界面元素少，封面就是主视觉，阅读时几乎看不到 UI。
2. **连续性**：所有状态变化都有过渡，包括 chrome 淡入淡出、封面放大进详情、页面和背景色融合。
   我们目前的状态变化**全部是瞬切**。
3. **阅读器里的贴心细节**：底部缩略图滑条、动态背景色、读完后的下一本卡片、阅读预设。

所以排序原则是：**先补设计系统地基（P0），再做"每次打开都会看到"的阅读器体验（P1），
然后是书架和详情页（P2），最后是长尾功能（P3）**。

## 1. 现状基线（2026-11-18 盘点）

| 维度 | 现状 |
|---|---|
| 动效 | 只有卷页动画用了曲线（`reader_page_turn.dart`）。Hero、`AnimatedSwitcher`、Fade、Slide 一律为 0。`AppDurations` 在 app 里**没有任何引用** |
| 材质 | `BackdropFilter`、`BoxShadow`、自定义形状都为 0。普通圆角，没有阴影 token |
| 反馈 | 没有 `HapticFeedback`，没有按压缩放 |
| 字体排印 | 用 M3 默认值，没有字体排印 token；只打包了 Roboto，没有中文字体 |
| 组件 | 设计系统只有 `SeriesTile` 和 `StatusView` 两个组件 |
| 阅读器 chrome | `if (_chromeVisible)` 直接显隐，不切换系统沉浸模式 |
| 阅读器功能 | 有单页、双页、纵向、卷页、双指缩放、网格跳页、亮度遮罩、常亮、读完后的下一本条、音量键 |
| 缺少的阅读器功能 | 适配方式切换（引擎里有 `FitMode`，UI 没接）、手动阅读方向、双击缩放、背景色、预设 |
| 书架 | 只有网格视图，5 种排序 + 4 种筛选，有继续阅读行，没有收藏集和阅读列表 |
| 系列详情 | 不展示简介、作者、标签（`Series.summary` 已解析但没用上），单本书不能标记已读，书列表上限 100 本 |
| 文件体积 | `reader_screen.dart` **660 行**，已超过 350 行上限；`reader_chrome.dart` 341 行、`series_two_pane.dart` 324 行，接近上限 |

我们已有而 Panels 在 Komga 下**做不到**的能力，改造时**不能被削弱**：

- 流式阅读时自动接下一本（Panels 走 OPDS，流式阅读不支持）；
- Komga ondeck；
- 墨水屏主题；
- 音量键翻页；
- 自签名证书指纹固定；
- Android 端。

## 2. 优先级定义

| 级别 | 含义 | 目标批次 |
|---|---|---|
| **P0** | 地基。不做的话后面每个需求都会各写各的魔法数字和动画 | 第 1 批 |
| **P1** | 阅读器体验。每次打开都会看到，收益最大 | 第 2–3 批 |
| **P2** | 书架和详情页的质感，以及信息补全 | 第 4–5 批 |
| **P3** | 长尾功能 | 已完成 |
| **不做** | 成本远大于收益，或与 Komga 场景无关 | — |

每个需求的编号格式是 `UI-<级别>-<序号>`，提交信息和 PR 标题里引用这个编号。

---

## P0：设计系统地基

### UI-P0-1 拆分 `reader_screen.dart`（前置重构）
- **原因**：文件 660 行，超过 AGENTS.md 规定的 350 行上限。P1 的所有改动都会落在这里，必须先拆。
- **做法**：
  - 把预取编排（`_schedulePreload`、`_pumpPreload`）抽成 controller；
  - 把进度回写和生命周期抽成 mixin 或 controller；
  - 把亮度遮罩、常亮这类"装饰层"抽成独立 widget。
  - **行为零变化。**
- **验收**：所有阅读器测试和黄金图**不变**；单文件 ≤ 350 行。

### UI-P0-2 动效 token：时长、曲线、弹簧
- **新增**：
  - `AppMotion`：`quick`（约 150ms）、`standard`（约 300ms）、`emphasized`（约 450ms）三档时长；
  - 曲线：`standard` 用 easeOutCubic 系，`emphasized` 是带轻微回弹的曲线；
  - 两组 `SpringDescription`：`snappy`（界面元素）和 `gentle`（页面级）。
  - 现有 `AppDurations` 并入 `AppMotion`，或者让 `AppMotion` 引用它。二者只能保留一个出口。
- **墨水屏**：`AppMotion.resolve(eink: true)` 返回零时长和 `Curves.linear`；
  弹簧退化成瞬时到位。系统"减少动态效果"（`MediaQuery.disableAnimations`）也走同一条路径。
- **验收**：token 单测覆盖 eink、`disableAnimations` 和普通三种情况；
  app 里新增的动画只允许读 `AppMotion`（可以在 `ci.dart layers` 里加一条 grep 规则，禁止 `Duration(milliseconds:` 出现在 `screens/` 和 `widgets/`）。

### UI-P0-3 材质 token：毛玻璃与阴影
- **新增**：
  - `AppMaterials`：`chrome`（阅读器顶栏和底栏，强模糊加半透明底色）、`bar`（导航栏）、`sheet`（底部面板）三种材质；
  - `AppShadows`：`cover`（大半径、低透明度、向下偏移的柔和投影）、`card`、`floating` 三档；
  - 组件 `FrostedSurface`：封装 `ClipRect`、`BackdropFilter` 和底色。
- **墨水屏**：不模糊，改成不透明的纸色底加 1px 墨色描边，阴影为空。
- **性能**：`BackdropFilter` 只用在 chrome 和面板上，不能放进网格的单元格里。
  需要在 Android 低端模拟器上确认滚动和翻页不掉帧。
- **验收**：`FrostedSurface` 三个主题各一张黄金图。

### UI-P0-4 形状 token：连续圆角
- **新增**：`AppShapes`。封面用小圆角（约 6），卡片和面板用中、大圆角，统一采用 Flutter 自带的
  `ContinuousRectangleBorder`（squircle 近似）。**不引入第三方包**，
  如果自带的效果不够，另写 ADR 再讨论。
- **同时**：清理盘点中发现的魔法数字（96×136、196、圆角 2、图标 20），全部改成 token。
- **墨水屏**：零圆角，保持现状。

### UI-P0-5 字体排印 token 与中文字体
- **新增**：`AppTypography`。层级包括大标题、标题、正文、说明、等宽数字（页码用 tabular figures，翻页时宽度不跳）。
- **中文字体**：这是路线图阶段 G 遗留的边界。引入一套可再分发的中文字体子集，
  先写 ADR 评审体积和许可。字体到位后补中文黄金图。
- **验收**：`settings@eink` 中的"中文"不再显示为方块。

### UI-P0-6 交互反馈原语
- **新增**：
  - 组件 `PressableScale`：按下缩小到约 0.97，松开时用 `snappy` 弹簧回弹；
  - 薄封装 `AppHaptics`：`selection`、`light`、`success` 三种，统一开关。
- **墨水屏**：不缩放；触感反馈保留，因为不影响屏幕刷新。
- **设置项**：设置页新增"触感反馈"开关，默认开启。

**P0 出口**：`ci.dart check` 全绿；设计系统新组件有单测和黄金图；`docs/` 中补一节设计 token 说明。

**进度（2026-11-18）：第 1 批完成。**

| 编号 | 落地 |
|---|---|
| P0-1 | `reader_screen.dart` 740 → 349 行，拆出 `reader_layout` / `reader_preloader` / `reader_progress_writer` / `reader_pages_gate` / `reader_top_bar` / `reader_frame` / `volume_key_scope` / `wake_lock_scope`、`screens/reader_args.dart`；原有阅读器测试与黄金图零变化，新增 `test/reader_layout_test.dart`（布局派生状态 + 进度防抖） |
| P0-2 | `AppMotion`（时长 / 曲线 / 弹簧 + `of`/`resolve` 统一退化），删除无人引用的 `AppDurations` |
| P0-3 | `AppMaterial`（chrome / bar / sheet）、`AppShadows`、`FrostedSurface`；`ci.dart layers` 禁止页面直接写 `BackdropFilter(` |
| P0-4 | `AppShapes`（`ContinuousRectangleBorder`，不引第三方包）、`AppSizes`；盘点出的 22 处魔法数字全部换成 token |
| P0-5 | `AppTypography`（含等宽数字页码）；中文字体按 ADR 0004：App 走系统字体，黄金图用 OFL 的 Noto Sans SC 子集，新增 `connection@phone_light_zh` |
| P0-6 | `PressableScale`、`AppHaptics`；设置页"触感反馈"开关（持久化，默认开启）；`ci.dart layers` 禁止页面直接写 `HapticFeedback.` |

说明见 [docs/design-system.md](design-system.md)。新 token 尚未用到具体页面上——那是第 2 批（P1）起的工作，
所以除了新增的 `design_tokens@*`、`connection@phone_light_zh` 与设置页（多了一行开关）外，页面基线不变。

---

## P1：阅读器体验

### UI-P1-1 Chrome 动画与沉浸模式 ★最高收益
- 顶栏和底栏改用 `FrostedSurface(chrome)`；显隐用淡入加 4–8px 位移，时长取 `AppMotion.standard`。
- chrome 隐藏时进入 `SystemUiMode.immersiveSticky`，显示时恢复系统栏，两者同步。
  退出阅读器时必须恢复原来的系统 UI 模式。
- 布局不能随系统栏显隐跳动：阅读区固定按全屏布局。
- **墨水屏**：瞬切，不透明纸色底加描边。
- **验收**：widget 测试断言显隐后的系统 UI 调用顺序，以及退出时恢复；黄金图更新 `reader@*`（基线变更原因：chrome 换成毛玻璃材质）。

### UI-P1-2 底部横向缩略图滑条
- 点开 chrome 后，底栏上方出现横向滚动的页面缩略图。当前页高亮并自动居中，点击跳页。
  双页模式按屏分组显示。
- 拖动时有 `selection` 触感反馈，每经过一页触发一次。
- 现有网格面板（`page_navigator_sheet.dart`）**保留**，作为"查看全部"的入口。
- 复用现有的 `cacheWidth` 降采样路径，只加载可见范围内的页。
- **墨水屏**：保留滑条，但滚动时不做惯性动画；也可以改成分页按钮式滚动，二选一，实现时再定。
- **验收**：可见范围懒加载测试（断言只请求了可见页）；RTL 时滑条方向镜像；黄金图。

### UI-P1-3 适配方式选择
- 设置面板加"适应屏幕 / 填满屏幕 / 适应宽度 / 自动"四个选项，接上引擎里已有的 `FitMode`。
  "填满"时溢出的方向允许平移。
- **验收**：引擎层补边界单测（宽页、超长页、0 尺寸）；偏好持久化与坏存档回退。

### UI-P1-4 手动阅读方向
- 设置项"跟随系列 / 从左到右 / 从右到左"。只需要替换 `ReaderControls.leftTurnsNext` 的数据来源，
  `docs/reader.md` 里已经预留了这一点。
- 卷页的捏角方向、点击区、底栏箭头、缩略图滑条方向都要跟着变。
- **验收**：RTL/LTR × 三种来源的组合测试。

### UI-P1-5 动态背景色
- 背景选项：黑色 / 白色 / 动态。"动态"模式提取当前页**边缘区域**的主色作为背景，翻页时颜色交叉渐变过渡。
- **提色算法**放在 `komga_reader_engine`，输入是降采样后的 RGBA 字节，保持纯 Dart、零依赖。
  页面解码之后在 isolate 里计算，结果按页缓存。
- 第一版只做单色；"沉浸式"的多色渐变放到 P3。
- 双页模式取两页边缘色的平均或主导色。
- **墨水屏**：不提供"动态"选项，固定白底。
- **验收**：算法单测（纯色、黑边扫描、白边扫描、透明像素、1×1 图片）；黄金图用合成页面验证。

### UI-P1-6 双击缩放
- 双击把双击点放大到 2.5 倍，再次双击还原。动画用 `gentle` 弹簧，以双击点为中心，
  复用 `zoomAboutFocal`。
- 必须和"点击中间切换 chrome"区分开，单击要等双击判定超时才生效。
  为了不让单击变慢，只在**中间区域**识别双击，左右翻页区保持立即响应。
- **验收**：手势冲突测试，覆盖单击、双击、双击后拖动、缩放态下的翻页。

### UI-P1-7 读完后的"下一本"卡片
- 把现有的 `Finished` 条换成卡片：显示下一本的封面、书名和"第 N 本"，
  按钮是"继续阅读"（主按钮）和"返回系列"。卡片带入场动画。
- 读完最后一屏后**继续往后翻**也可以直接进入下一本（Panels 的行为）。
- 保留现有约束：拿不到下一本时只显示"已读完"，不报错；继续使用 `pushReplacement`。
- **验收**：现有书末测试不回归，新增"末页再翻进下一本"测试；黄金图。

**P1 出口**：`docs/reader.md` 同步更新（设置表、手势、chrome 部分）；装到模拟器上实际走查一遍阅读器。

**进度（2026-11-18）：第 3 批完成（P1-3 / P1-4 / P1-6 / P1-5）。**

| 编号 | 落地 |
|---|---|
| P1-3 | 引擎新增 `FitMode.cover` 与 `contentOverflows`；设置面板加"适配方式"四档（适应屏幕 / 填满屏幕 / 适应宽度 / 适应高度）；填满/适应宽度时**溢出的方向单指平移**（拖动夹紧区间与引擎一致，不会出现拖过头的粘滞）；双页模式一律 `contain`（引擎里挡）；引擎补 cover/超长页/正方形页/双页忽略 fit 的边界单测 |
| P1-4 | `ReaderDirectionChoice`（跟随系列/LTR/RTL）+ 设置项；`rightToLeft` 一个来源派生点击区、底栏箭头、缩略图滑条方向与卷页镜像；组合单测覆盖 auto/LTR/RTL × 系列方向 |
| P1-6 | 双击缩放：中区双击 2.5 倍、再双击还原，`gentle` 弹簧 + `zoomAboutFocal` 保焦点；中区单击等 `kDoubleTapTimeout` 才切 chrome，左右翻页区立即响应；放大状态下点击/音量键/箭头都不翻页；墨水屏与"减少动态效果"直接到位。手势状态机拆成 `reader_page_turn`（翻页）/`reader_zoom`（缩放与点击）/`reader_paged_view`（布局），三个文件都在 350 行内 |
| P1-5 | 引擎 `edges.dart`：`edgeColor`（只看页边、跳过透明像素、1×1 与非法尺寸有单测）+ `averageColors`；`page_edge_color.dart` 用 `targetWidth: 32` 降采样解码后内联求平均（不开 isolate，理由见 docs/reader.md）；`pageEdgeColorProvider`（autoDispose，跟着页图一起回收）；背景三选项（黑/白/跟随画面），换色是 450ms 交叉渐变；墨水屏不给"动态"，存档里是动态也用纸色。`ReaderPalette` 区分 chrome 色与 `onBackground` 色 |

基线变更原因：设置面板多了三组选项（模式/适配/方向/背景/亮度/常亮/跳页），
新增 `reader_dynamic@phone_dark`（青绿页边的合成页 `test/fixtures/pages/edge_teal.png` 验证提色）。
新增的合成页只为黄金图存在，不进 App 包。

**进度（2026-11-18）：第 2 批完成（P1-1 / P1-2 / P1-7）。**

| 编号 | 落地 |
|---|---|
| P1-1 | `ReaderFrame` 改成"阅读区全屏 + chrome 浮层"：淡入淡出 + 8px 位移（`AppMotion.standard`），动画结束用 `Offstage` 摘掉（不销毁）；顶栏/底栏改用 `FrostedSurface(chrome)`；新增 `ReaderSystemUi`（隐藏→`immersiveSticky`、显示→`edgeToEdge`、退出必恢复，帧后调用）；chrome 内边距用 `viewPadding`；`reader_immersive_test.dart` 钉住调用顺序、退出恢复与"阅读区尺寸不变" |
| P1-2 | `ReaderThumbnailStrip`：按屏分组（`ReaderLayout.screenAt`/`screenCount`）、`ListView.builder` + 固定 `itemExtent` 懒加载、当前屏自动居中、RTL `reverse`、拖动每过一屏一次 `AppHaptics.selection()`；缩略图抽成 `PageThumbnailImage` 与网格面板共用，占位改成静态方块（转圈会让 `pumpAndSettle` 永不静止）；网格面板保留 |
| P1-7 | `ReaderFinishedCard` 取代 `ReaderFinishedBar`：下一本封面/书名/卷号 + "继续阅读"主按钮 + "返回系列"，入场淡入上浮；书尾继续往前翻直接进下一本（往回翻不触发）；拿不到下一本仍是"已读完"一行，不报错 |

基线变更原因：chrome 从"占位的行"变成浮层毛玻璃、阅读区改为全屏、底栏多了缩略图滑条、
书末从条变卡片。`reader_finished@phone_dark` 改用真实书列表以便卡片能显示下一本封面。

---

## P2：书架与详情页

### UI-P2-1 封面质感
- `SeriesTile` 加上 `AppShapes.cover` 圆角和 `AppShadows.cover` 投影；未读角标改成小圆点或胶囊；
  进度条变细，并贴在封面内侧底部。
- 封面加载完成时淡入，不再从色块直接跳到图片。
- 网格单元格外包 `PressableScale`。
- **验收**：书架全套黄金图更新（基线变更原因：封面质感）。

### UI-P2-2 Hero 过渡
- 书架封面到系列详情头部封面，继续阅读卡片到阅读器首页。
- tag 用 `series-<id>` / `book-<id>`。**同一页面上不能有重复的 tag**：同一个系列可能
  同时出现在"正在读"页的"最近添加"与按库货架里，这时每条货架用自己的作用域
  （`seriesHeroTag(id, scope: …)` → `series-<id>@<scope>`），详情页通过
  `SeriesDetailArgs` 接收被点那一份的 tag；tag 重复时 Flutter 只会随便挑一个 Hero，
  封面就会从另一份的位置飞进来。
- **首次打开也必须播**：系列详情页的头部第一帧就渲染（封面槽位 + Hero 落点），
  元信息与书列表后到、用骨架占位。否则第一次打开是"全屏加载"，第二次因为 provider
  有缓存才有动画（2026-11-19 修，见下方进度记录）。
- **墨水屏**：关闭 Hero，转场为零。
- **验收**：widget 测试断言 tag 唯一性；`series_detail_screen_test` 断言从书架首次进入时
  源/目标两个 Hero 落点同时存在；`reading_now_test` 断言多份副本页上点哪一份就用哪一份的
  tag；在模拟器上走查一遍。

### UI-P2-3 iOS 式页面转场与大标题
- 非墨水屏主题的 `pageTransitionsTheme` 在两个平台上都改用 Cupertino 式侧滑，支持边缘右滑返回。
- 书架和设置页改成可折叠的大标题（`SliverAppBar.large` 或自定义 sliver），滚动时标题收缩，顶栏换成毛玻璃材质。
- **注意**：Android 预测性返回手势与此有冲突，需要先确认行为再定方案。

### UI-P2-4 系列详情页重做
- 头部用模糊放大的封面做背景（`AppMaterials`），叠上封面、标题、作者、出版社、年份、标签，以及简介（可展开）。
- 新增的元数据字段先抓真实响应存入 fixture，再改解析层（遵守 API 真值规则）。
- 主按钮"继续阅读第 N 本"或"开始阅读"放在显眼位置。
- 书列表改成带封面的卡片行，支持分页加载（解除 100 本上限）。
- `series_two_pane.dart` 已有 324 行，先拆再改。
- **墨水屏**：不做模糊背景，用纯纸色背景加描边。
- **验收**：手机浅色、平板深色、墨水屏三张黄金图，平板两栏单独一张。

### UI-P2-5 长按上下文菜单
- 长按系列或书时，带缩放效果弹出菜单。系列菜单：标记已读/未读、下载全部、查看详情；
  书的菜单：标记已读/未读、下载/删除、从头阅读。
- 这个需求顺带补上缺失的**单本书标记已读**功能。需要新端点时先加进 `KomgaUrls` 并补契约测试。
- 墨水屏用普通弹出菜单，不做缩放效果。

### UI-P2-6 Reading Now 首页
- 底部导航从"书架 / 设置"扩展为"**正在读** / 书架 / 设置"。
- "正在读"页的内容：
  - 大号继续阅读卡片（来自 ondeck）；
  - 最近添加的书；
  - 按库分组的横向货架。
- 原来书架里的继续阅读行在书架页移除，或者保留一个精简版，实现时再定。

### UI-P2-7 书架视图选项
- 网格/列表切换，封面大小分小、中、大三档；平板上支持双指捏合调整大小。
- 排序补充 Komga 支持的字段，例如按书籍数量、按发行日期。新排序参数要对照 OpenAPI 补契约测试。

### UI-P2-8 骨架屏与状态过渡
- 首屏的纯色骨架改成带微光（shimmer）的骨架；状态切换用 `PhaseFade` 做入场淡入
  （sliver 不能像 box 那样交叉淡入）。
- 系列详情页的头部**固定在三态之外**：它要在首帧就在（Hero 落点），不能跟着列表
  一起淡出/淡入。
- **墨水屏**：不做 shimmer，用静态骨架；骨架块本身要能看见（容器色在墨水屏会
  退化成纸白，见 `SkeletonBox`）。

**P2 出口**：书架、系列详情、新首页三套黄金图完整；在模拟器上能看到书架内容；
`docs/series-queries.md` 同步更新排序部分。

**进度（2026-11-18）：第 4 批完成（P2-1 / P2-2 / P2-3 / P2-8）。**

| 编号 | 落地 |
|---|---|
| P2-1 | `SeriesTile` 封面改 `AppShapes.cover` 连续圆角 + `AppShadows.cover` 柔和投影（墨水屏两者都退化）；已读角标改成半透明胶囊（等宽数字）；进度条挪到**封面内侧**底部；整张卡片包 `PressableScale`；新增 `CoverImage`（书架卡片 / 继续阅读 / 书末"下一本"三处共用），解码首帧淡入 |
| P2-2 | 书架卡片 → 系列详情头部用同一个 `series-<id>` tag（`seriesHeroTag`），墨水屏不挂 Hero；`shelf_polish_test` 断言 tag 唯一、详情页接到同一个 tag |
| P2-3 | 新增 `IosSlidePageTransitionsBuilder`（新页从左滑入 + 旧页 30% 视差），light/dark 主题在 Android 与 iOS 都用它，墨水屏保持零转场；书架与设置页改成 `SliverAppBar.large` 可折叠大标题，整页合成一条 `CustomScrollView`（继续阅读 / 搜索 / 筛选都成了 sliver） |
| P2-8 | 新增 `SkeletonBox` + `Shimmer`（周期取 `AppMotion.shimmer`）；墨水屏与"减少动态效果"下**不画微光**（灰阶屏上就是拖影）；书架与系列详情的状态切换都用 `PhaseFade` 做入场淡入（sliver 不能重叠；2026-11-19 起系列详情的头部固定在三态之外，理由见下一条进度）。**`PhaseFade` 的退化路径必须直接到终值**：曾经在 phase 变化时 `value = 0` 再 `forward()`，动画被禁用时这一步不推进，墨水屏书架整页停在 opacity 0（有数据但看不见，`library@eink` 与 `library_error@eink` 一度是两张一模一样的空白图）；现在由 `test/phase_fade_test.dart` 钉住 |

**与计划的偏差（明说）**：
- 边缘右滑返回**没有做**：`material_ui` 没有 Cupertino 的 transitions builder，而手势在
  Cupertino 的 `PageRoute` 里、不在转场 builder 里，要做得自定义 Route 并接管 go_router 的路由构造。
  Android 的系统返回手势不受影响。需要的话单开一条需求。
- P2-2 的"继续阅读卡片 → 阅读器首页"没做：阅读器首页的图是异步解码的，飞行途中首页可能还是
  转圈，Hero 反而更怪。目前只做"书架 → 详情"。

基线变更原因：封面形状/阴影/角标/进度条位置、大标题（书架/设置）、骨架微光。

**进度（2026-11-18）：第 5 批进行中。**

| 编号 | 落地 |
|---|---|
| P2-5 | 长按上下文菜单（`showContextMenu`，锚在被按的控件旁）；系列：标记全部已读/全部未读/查看详情；书行：标记已读/标记未读；补上**单本书标记已读**（`LibraryRepository.setBookRead` 走已有的 `PATCH`/`DELETE /books/{id}/read-progress`，并同步本地 outbox）；新增 `bookReadProvider`；书行包 `PressableScale` |
| P2-7 | 网格/列表切换 + 封面小/中/大三档（`ShelfView` / `ShelfCoverSize`，档位只影响"一格最宽多少"，仍然不判断平板）；`ShelfViewButton` 用 `CheckedPopupMenuItem` 标当前项；**不重新请求**，只换 sliver 类型；列表行 `SeriesShelfRow` 与网格卡片共用 Hero 与长按菜单；`komga_api` 补"排序 wire 值符合 `property,asc\|desc`"的契约测试 |

**进度（2026-11-19）：P2-7 排序与捏合补齐。**

| 落地 |
|---|
| `SeriesSort` 新增 `booksCountDesc` / `releaseDateDesc`，wire 值是 `booksCount,desc` / `booksMetadata.releaseDate,desc`；两者都对本机真实 Komga 1.30.1 验证过（发行日期先 `PATCH` 三本书的 metadata 再排序），证据见 `docs/series-queries.md`；书架排序菜单多了"书籍数量（多→少）""发行日期（新→旧）"两项 |
| 双指捏合：`widgets/shelf_pinch_detector.dart` 用 `Listener` 看原始指针，不参与手势竞技场，所以单指滚动/下拉刷新不受影响；**一次手势只换一档**（双指距离变化 >18%），网格视图生效；换档时 `AppHaptics.selection()` |
| 测试：`shelf_pinch_detector_test` 覆盖"双指放大/收拢各一档"、"单指拖动不触发"、"enabled=false 不响应"；`komga_api` 的排序格式契约测试会自动覆盖两个新枚举 |

**进度（2026-11-18）：P2-4 系列详情页重做。**

| 落地 |
|---|
| 领域层 `Series` 新增 `authors` / `publisher` / `releaseDate` / `tags`；`seriesFromJson` 从 `metadata.publisher` 与 `booksMetadata`（作者数组、`releaseDate`、标签、简介）解析，空值给空集合；`komga_api` 导出 `parsers.dart`，fixture 测试覆盖"真实响应里这几项是空的也不崩"与"构造样本的字段映射" |
| 头部抽成 `widgets/series_header.dart`（`series_two_pane.dart` 380 → 292 行）：模糊放大的封面当背景（`ImageFiltered` 而不是 `BackdropFilter`——模糊的是封面自己，便宜且不违反分层规则）、渐变遮罩、封面 + 标题 + 已读进度 + 作者/出版社/年份 + 标签胶囊 + 可展开简介 |
| 主按钮 `series-main-action`：`data/book_selection.dart` 的 `nextBookToRead` 决定"下一本该读的"（优先在读 → 否则第一本未读 → 全读完则不显示按钮），文案是"继续阅读 第 N 本"或"开始阅读"；纯逻辑有单测 |
| 墨水屏：不做模糊背景，纸色 + 墨色下边框 |

**P2-4 分页（随本批补上）**：`seriesBooksProvider` 的参数从 `String` 改成
`({String seriesId, int size})`，详情页持有一个"要多少本"的视图状态（默认 100，
点一次"加载更多"加 50）；截断提示从死文案变成可点的 `series-load-more`。
客户端不拼列表——`size` 变了就是一次新查询，不存在两份不一致的书列表。
代价：`ref.invalidate(seriesBooksProvider)` 变成整族失效（比按 key 失效略粗，
但书列表本来就跟着详情页一起刷新）。

**进度（2026-11-18）：P2-6「正在读」首页。**

| 落地 |
|---|
| 新增 `screens/reading_now_screen.dart`：大号继续阅读卡片（ondeck 第一本 + 进度 + 主按钮）、"最近添加"横向货架（`series(sort: recentlyAdded)`）、按库分组的横向货架（`series(libraryId:)`）；空态给一句说明而不是空壳；ondeck / 列表失败都只是"这一块不显示"，不把整页变成错误页 |
| 新增 `recentSeriesProvider` / `libraryShelfProvider`：只用**已验证过**的 `GET /api/v1/series`（理由见 `docs/series-queries.md`："/api/v1/books 按添加时间列"没有 fixture） |
| 底部导航从"书架 / 设置"变成"**正在读** / 书架 / 设置"，连接成功后的落地页也改成 `/reading`；平板侧边栏同样三项 |
| 书架页移除原来的"继续阅读"横排（`continue_reading_row.dart` 与其测试删除）——同一件事只在一个地方做；继续阅读卡保留了"按系列查阅读方向"的行为（日漫从首页进去仍是 RTL） |
| 新页面按约定补齐三张黄金图：`reading_now@phone_light` / `@tablet_dark` / `@eink`；`a11y_test` 的"继续阅读卡片"用例改到新页面（语义标签与 48 点按区不放宽） |

**进度（2026-11-19）：P2-2 继续阅读卡片 → 阅读器开场 Hero（补齐缩水）。**

| 落地 |
|---|
| 新增 `widgets/book_hero_tag.dart`（`book-<id>`）与 `widgets/reader_opening_hero.dart`；继续阅读卡片封面包 `Hero`，`ReaderArgs` 把 tag 带到阅读器 |
| 阅读器第一帧不依赖页图：`ReaderOpeningHero` 先放一张封面落点（2:3 页面槽位），**等首屏页图字节真的到达**（404/失败或约 1.35s 超时兜底）再淡出，页图在下面接管。这样转场途中始终是封面，不会"封面飞过去变成一个转圈"。第一版固定 450ms 淡出，设备走查时在弱网/大页面上仍露出一次黑底转圈，所以改成等页图 |
| 墨水屏与系统"减少动态效果"不建 Hero；系列详情/深链没有 `heroTag` 时也不建。退场仍是普通滑动：页图是异步的，反向 Hero 会从转圈起飞，暂不做 |
| 测试：`reading_now_test` 断言继续阅读卡片用 `bookHeroTag('s1-b1')`；`reader_screen_test` 新增"页图没来时封面不淡出、页图到了才让位"（用 `pageGates` 卡住首页）；`pumpReader` 增加 `heroTag` / `settle` 参数 |
| 黄金图不变（Hero 包装不改变静态像素，`reading_now@*` 与 `reader@*` 基线均未动） |

**进度（2026-11-19）：P2-3 边缘右滑返回（补齐缩水）。**

| 落地 |
|---|
| 新增 `widgets/edge_swipe_back.dart`：只在**左边缘 24px**（RTL 为右边缘）放一条横向手势条，拖过 64px 或甩速 >700 就 `Navigator.maybePop`；页面中间/横向货架的手势不受影响 |
| 系列详情与阅读器接入；墨水屏、系统"减少动态效果"、不可 pop 的路由都不挂手势条 |
| **不是交互式跟手**：Flutter 3.47 起 `package:flutter/cupertino.dart` 已废弃（要求换 `cupertino_ui` 新依赖），真正的跟手返回在 Cupertino 的 `PageRoute` 里。我们保持零新依赖，用"边缘手势 + 主题侧滑转场"实现功能，跟手动画仍是缺口 |
| 测试：`edge_swipe_back_test` 覆盖"左边缘拖过阈值返回"、"中间拖不返回"、"墨水屏不挂手势条" |

**进度（2026-11-19）：首次打开系列详情的 Hero 一致性。**

| 落地 |
|---|
| 问题：首次打开系列时 `seriesDetailProvider` / `seriesBooksProvider` 都没有缓存，整页被骨架占掉 → 详情页没有 Hero 落点，书架→详情的共享元素动画不播；第二次打开因为 provider 有缓存才正常（第一次只是一次全屏加载） |
| `SeriesDetailScreen` 改成**头部第一帧就渲染**：`widgets/series_header_cover.dart` 抽出封面槽位（Hero + 模糊背景 + 封面占位）；`SeriesHeader` 接收 `metadataLoading` / `booksLoading`，未到的标题/作者/进度/主按钮用 `SkeletonBox` 占位；元信息与书列表各自异步到 |
| 书列表三态从整页 `AnimatedSwitcher` 换成 `PhaseFade`（sliver 不能重叠），头部在动画之外、Hero 落点不会中途消失；`series_two_pane.dart` 只留两栏布局，列表三态/骨架/错误拆到 `widgets/series_book_list.dart`，书行拆到 `widgets/series_book_row.dart` |
| `SkeletonBox` 在墨水屏改用 12% 墨色填充：墨水屏 `ColorScheme` 没定义 `surfaceContainerHighest`，会兜底成纸白，骨架在灰阶屏上原来是白底白块（`series_loading@eink` 黄金图抓到过） |
| 测试：`series_detail_screen_test` 新增"首帧 Hero/占位"、"从书架首次进入时源/目标两个 Hero 同时存在"、"详情也失败不会永远停在骨架"；`shelf_polish_test` 改为断言头部不在 `PhaseFade` 内；`design_system_test` 钉住 `SkeletonBox` 在墨水屏的可视填充 |
| 新增黄金图 `series_loading@{phone_light,tablet_two_pane,eink}`：这是首次打开（元信息与书列表都没回来）的新 UI 状态；`series@*` 四张基线未动，说明加载完成后的版式没有漂移 |

基线变更原因：仅新增 `series_loading@*` 三张；`series@*` 与其它页面基线均未变。

**进度（2026-11-19）：Hero tag 按货架加作用域（"正在读"页点的不是那一份）。**

| 落地 |
|---|
| 现象："正在读"页点系列卡片进详情、退出时，封面从一个奇怪的位置飞。原因：该页"最近添加"（全库、按添加时间）与按库货架天然重叠，同一个系列在同一路由里出现两份相同 tag；Flutter 只会挑其中一个 Hero（release 静默选错、debug 断言），飞行起点/终点就变成另一份（常常在屏幕外）。书架页每个系列只有一份，所以一直是对的 |
| 新增 `widgets/series_hero_tag.dart`：`seriesHeroTag(id, scope: …)` 生成 `series-<id>@<scope>`；"正在读"的每条货架传自己的 scope（`reading-now-recent` / `reading-now-library-<id>`），`SeriesShelfTile` / `SeriesShelfRow` 接受 `heroTag` |
| 详情页新增 `SeriesDetailArgs.heroTag`（路由 extra）：源卡片把自己的 tag 带过去，头部（含首次打开的占位封面）都用它；深链/冷启动没有 extra 时退回默认 `series-<id>`（没有源卡片，本来也不飞）。长按菜单"查看详情"同样带 tag |
| 顺带修掉一个只会出现在 debug 的断言：Hero 飞行层（Overlay）没有 `Material` 祖先，而书架卡片内部有 `InkWell`，退出时抛 "No Material widget found"。卡片外包一层 `Material(type: transparency)`，只补祖先、不画东西（黄金图未变） |
| 测试：`reading_now_test` 新增"同页 Hero tag 唯一"与"点哪一份货架卡片，详情页就用那一份的 tag"（含退出回原页）；`shelf_polish_test` / `series_detail_screen_test` 的 tag 断言改从 `series_hero_tag.dart` 取 |

基线变更原因：无（Hero tag 与透明 Material 都不改变绘制）。

---

## P3：长尾功能（✅ 14/14 完成，2026-11-19）

| 编号 | 需求 | 状态 |
|---|---|---|
| UI-P3-1 | 阅读预设 | ✅ |
| UI-P3-2 | 按系列记住阅读设置 | ✅ ADR 0005 |
| UI-P3-3 | 横屏自动单/双页 | ✅ |
| UI-P3-4 | 锁定缩放 | ✅ |
| UI-P3-5 | 手动修正双页分组 | ✅ |
| UI-P3-6 | 缩略图长按分享/保存 | ✅ ADR 0006 |
| UI-P3-7 | 沉浸式多色动态背景 | ✅ |
| UI-P3-8 | 收藏集 + 阅读列表 | ✅ |
| UI-P3-9 | 跨库全局搜索 | ✅ |
| UI-P3-10 | 图像滤镜（去白边） | ✅ |
| UI-P3-11 | 键盘快捷键 / 蓝牙翻页器 | ✅ |
| UI-P3-12 | 隐身模式 | ✅ |
| UI-P3-13 | 下载管理页 / 串行队列 | ✅ |
| UI-P3-14 | 墨水屏自动探测 | ✅ |

**进度（2026-11-19）：P3-1 阅读预设。**

| 落地 |
|---|
| `ReaderPreset`（id / name / prefs 快照）挂在 `ReaderPrefs.presets` 上，继续用同一个 secure storage JSON；预设里的 `prefs` 用 `toJson(includePresets: false)`，不会递归 |
| `ReaderPrefsController.savePreset / applyPreset / deletePreset`；应用预设只覆盖模式/适配/方向/背景/亮度/常亮，保留预设列表；坏条目逐条跳过 |
| 面板顶部 `ReaderPresetSection`：`Save current` 弹命名框（默认 "Preset N"）、chip 点一下应用、× 删除；键 `reader-preset-save` / `reader-preset-<id>` |
| 测试：`reader_presets_test` 覆盖保存→改设置→应用回来、删除；`data/reader_prefs_test` 覆盖预设 JSON 往返与坏条目；新增 `reader_settings_presets@phone_dark` 基线（chip 视觉），`reader_settings@phone_light` 也补上（浅色主题下面板仍是深色，见下） |
| 设备走查时发现：浅色主题下 `FrostedSurface` 的 `sheet` 会跟随 Theme.brightness 变成浅灰底 + 白字，面板不可读。已在 `showReaderSettingsSheet` 显式传深色 sheet 材质（墨水屏仍走纸色），`reader_settings@phone_light` 基线钉住 |

**进度（2026-11-19）：P3-2 按系列记住阅读设置。**

| 落地 |
|---|
| `ReaderPrefs.seriesOverrides`（seriesId → 纯配置）+ `forSeries()`；存同一个 secure storage JSON，无 Drift；ADR 0005 说明取舍 |
| 阅读器全链路用 `forSeries(book.seriesId)`：音量键、模式解析、布局、背景；不会出现"面板是系列设置、阅读区还是全局" |
| 面板开关 `reader-series-remember`：打开快照当前生效值，之后改设置/应用预设只写覆盖；关闭删覆盖回全局。设置面板的 6 个 setter 全部带 `seriesId` |
| 测试：`data/reader_prefs_test` 覆盖系列覆盖 JSON 往返与 `forSeries` 优先；`reader_series_prefs_test` 覆盖"打开开关只写覆盖、全局不变；关闭删除"；`reader_settings@*` 与 presets 基线更新（多了开关） |

**进度（2026-11-19）：P3-3 横屏自动双页。**

| 落地 |
|---|
| `ReaderModeChoice.resolve(direction, {landscape})`：`auto` 仍是条漫→纵向；普通漫画竖屏单页、横屏双页；显式 single/double/vertical 不受横屏影响 |
| `ReaderScreen` 在每次布局时用 `MediaQuery.orientationOf` 更新 `_landscape`，模式/布局/预取/音量键共用；`readerModeAutoHint` 文案同步说明 |
| 测试：`data/reader_prefs_test` 覆盖 auto 横屏/条漫/显式选择的组合；`reader_screen_test` 用 844×390 视口断言 `ReaderPagedView.doublePage == true`；`reader_settings@*` 基线因 hint 文案更新 |

**进度（2026-11-19）：P3-4 锁定缩放。**

| 落地 |
|---|
| `ReaderPrefs.lockZoom`（默认 false，进 JSON、预设、系列覆盖）；设置面板开关 `reader-lock-zoom` |
| `ReaderPagedView` 换屏时：`lockZoom` 开 → 保留 `_zoom`、`_pan` 归零；关 → 照旧 `_resetZoom`。适配方式/单双页变化仍复位（旧比例对应旧布局） |
| 放大状态下 `turn()` 默认仍忽略误触；`lockZoom` 开时放行，否则这个开关永远翻不了页 |
| 测试：`reader_lock_zoom_test` 覆盖"放大→翻页比例保持"与"未锁定时不翻页"；`data/reader_prefs_test` 覆盖默认值/JSON/系列覆盖；`reader_settings@*` 基线更新 |

**进度（2026-11-19）：P3-5 手动修正双页分组。**

| 落地 |
|---|
| 引擎 `buildSpreads(groupFrom:)`：起点前保持自动、起点起重新配对；落在默认跨页中间时前一页单独留下；宽页仍单独成屏。`ReaderLayout.spreadsFor` 透传 |
| 入口在缩略图网格（顶栏网格按钮）长按某一页；再长按恢复自动。底部滑条也支持长按，但按"屏"分组，语义是从该屏第一页开始 |
| `ReaderScreen._spreadFrom` 会话内有效，不落盘；`ReaderTopBar` / `PageNavigatorSheet` 传 `onGroupFrom`；`ReaderThumbnailStrip` 同样支持 |
| 测试：`spreads_test` 覆盖 groupFrom 的三种边界；`reader_screen_test` 覆盖"跳到第 3 页 → 长按第 3 页 → spread 从 [1,2] 变 [2,3] → 再长按回 [1,2]"；触感 + SnackBar 反馈 |

**进度（2026-11-19）：P3-6 缩略图长按分享/保存页。**

| 落地 |
|---|
| 引入 `share_plus` 13.3.1（ADR 0006）；`data/page_share.dart` 把页图写到临时目录 PNG，再调系统分享面板；用户可选"存储到文件" |
| 长按底部缩略图弹动作面板：分享此页；双页模式同时有"从这一页开始分组"（P3-5 入口从直接长按改成菜单，两个动作不再抢手势） |
| 分享失败（页图/平台异常）只弹 SnackBar；`ReaderScreen.onSharePage` 为测试接缝，生产走插件 |
| 测试：`reader_screen_test` 覆盖长按 → 菜单 → 回调拿到页码；模拟器上分享面板可打开（见设备走查） |

**进度（2026-11-19）：P3-7 沉浸式多色动态背景。**

| 落地 |
|---|
| 引擎 `edgeColors`：左右两侧分别取页边色（同样跳过透明像素、O(周长)）；单测覆盖左右分色、单侧透明、非法尺寸 |
| `ReaderBackgroundChoice.immersive`；`pageEdgeGradientProvider` 跟着页图回收；双页跨页按左右位置分别平均 |
| `ReaderPalette` 增加 `gradient`；`ReaderFrame` 的底色层从 `TweenAnimationBuilder<Color>` 换成 `AnimatedContainer` 的 `BoxDecoration`，可插值渐变；墨水屏仍只给纸色 |
| 设置面板多一档"沉浸式"；新增 `reader_immersive@phone_dark` 黄金图（合成左右红/蓝页边） |

**进度（2026-11-19）：P3-14 墨水屏自动探测。**

| 落地 |
|---|
| Android `MainActivity` 的 `komganative/device` 通道实现 `eink`：按 Build 厂商/品牌/型号匹配常见墨水屏标记，返回 `{isEink, vendor}`；宁可漏判不误判 |
| `einkDetectedProvider` 调 `EinkProbe`；`KomgaApp` 用 `settings.forceEink || detected` 选主题。探测失败只保持彩色，不阻塞启动；手动强制仍优先 |
| 测试：`eink_probe_test` 覆盖正常返回、MissingPlugin、PlatformException、null；iOS/测试环境仍 unknown |
| 未做：真实墨水屏设备上的探测命中率验证（模拟器无法伪造 Build 厂商）；需要 Boox/Kindle 真机走查 |

**进度（2026-11-19）：P3-11 键盘 / 蓝牙翻页器。**

| 落地 |
|---|
| 阅读器根节点 `Focus(autofocus: true, onKeyEvent:)`：右/左方向键按 RTL 语义翻页，PageDown/PageUp、空格翻页，Esc 退出 |
| 与点击区/音量键共用 `_requestTurn`，所以页码、进度、预取、RTL 完全一致；蓝牙翻页器/遥控器映射成方向键或 PageUp/Down 即可 |
| 测试：`reader_screen_test` 覆盖右箭头→第 2 页、左箭头→第 1 页、PageDown→第 2 页、空格→第 3 页 |

**进度（2026-11-19）：P3-12 隐身模式。**

| 落地 |
|---|
| 顶栏 `reader-incognito-button`（眼睛图标）切换 `_incognito`；`_scheduleProgress` 与切后台 flush 都短路，不发请求、不写 outbox |
| 会话级，不落盘；退出阅读器自动恢复。SnackBar 明确"本次不保存进度" |
| 与 Panels 语义不同：Panels 只隐藏 Reading Now，我们是完全不回写 Komga（服务端无 hidden 标记） |
| 测试：`reader_screen_test` 覆盖"开启后翻页 700ms 无 saved；关闭后恢复 saved" |

**进度（2026-11-19）：P3-8 收藏集 + 阅读列表。**

| 落地 |
|---|
| 领域/API：`KomgaCollection` / `ReadList`；`/collections`、`/collections/{id}/series`、`/readlists`、`/readlists/{id}/books` 四个端点；真实响应存 `collections.json` 等四份 fixture，契约测试 + 解析测试驱动 |
| 仓库/Provider：`collectionsProvider`、`readListsProvider`、`collectionSeriesProvider`、`readListBooksProvider`；错误统一 `ShelfFailure` |
| UI：书架顶栏收藏集图标 → `CollectionsScreen`（两 tab）；收藏集 → 系列行 → 系列详情；阅读列表 → 书行 → 阅读器。标题经 `extra` 传入，深链有 fallback |
| 测试：`collections_test` 覆盖两个 tab 的列表；`collections@phone_light/tablet_dark/eink` 三张黄金图；契约 + fixture 解析 4 条 |
| 未做：创建/编辑收藏集（只读展示服务端策展）；封面缩略图用系列/书封面，不单独拉 collection thumbnail |

**进度（2026-11-19）：P3-9 全局搜索。**

| 落地 |
|---|
| 新增 `/search` 分支（底部/侧栏第 3 项）；一个输入框同时查 `/series?search=` 与 `/books?search=`，按"系列 / 书籍"分区展示 |
| 防抖用 `AppMotion.of(context).emphasized`（墨水屏为 0，立即查）；清空按钮、无结果/错误态；系列进详情、书进阅读器 |
| API：`KomgaUrls.books` + `KomgaSession.searchBooks`；真实响应 `books-search.json`，契约 + 解析测试 |
| 测试：`search_test` 覆盖输入→防抖→书结果；`search@phone_light/tablet_dark/eink` 三张黄金图 |
| 未做：搜索历史/建议、按标签/作者筛选 chip（服务端已匹配这些字段，客户端暂不单独过滤） |

**进度（2026-11-19）：P3-10 图像滤镜（自动去白边）。**

| 落地 |
|---|
| 引擎 `detectBorderCrop`：四角定背景色、逐行/列扫描连续纯色边，单边上限 40%，整页纯色/四角不同/空图不裁；`borders_test` 覆盖白边、黑边、不对称、无边框、整页纯色、空图 |
| 页图解码到 48px 做检测（`pageBorderCrop`），provider 跟页图回收；`ReaderPage` 用 `MemoryImage` ImageStream + `drawImageRect` 精确裁剪，保留 contain 比例 |
| `ReaderPrefs.trimBorders` + 设置开关 `reader-trim-borders`；预设/系列覆盖/JSON 都带上；修复了相等性漏字段导致恢复被 Riverpod 吞掉的问题 |
| 测试：`reader_trim_test` 覆盖"白边页图开启后走裁剪绘制"；`reader_trim@phone_dark` 黄金图（合成白边页） |

**进度（2026-11-19）：底部导航玻璃化（iOS 26 液态玻璃）。**

| 落地 |
|---|
| 设计系统：`AppMaterialKind.bar` 改成玻璃档（模糊 22、底色 72%、白色高光描边、斜向反光渐变）；反光由 `FrostedSurface` 画在裁剪之内；新增 `GlassSurface`（毛玻璃 + 浮层阴影 + 默认胶囊）、`AppShapes.bar`（`StadiumBorder`，墨水屏直角）、`AppSizes.navBarHeight` / `navBarClearance` |
| 手机导航：新增 `widgets/floating_nav_bar.dart`（胶囊 tab + 右侧搜索圆球；选中项整格高亮、按下缩放、`AppHaptics.selection`、读屏 `selected` 语义）；`AdaptiveShell` 改成 `extendBody: true` 的浮层导航，`resizeToAvoidBottomInset: false` 让键盘盖住导航条（页面自己的 `Scaffold` 仍为键盘让位）；平板侧栏不变 |
| 信息架构：搜索从"胶囊里的第 3 个 tab"改成右侧圆球（与参照图一致）；英文 tab 标签用短一档的 "Reading"（新增 `navReadingNow`），否则 1.3 倍字号会截成 "Reading n…" |
| 页面让位：正在读 / 书架 / 设置 / 搜索四个分支页的滚动内容末尾统一留 `AppSizes.navBarClearance` |
| 测试：`floating_nav_bar_test`（点击派发、48 点按区、`selected` 语义、墨水屏反白、1.3 倍字号不溢出）；`tokens_test` 补 `GlassSurface` / `AppShapes.bar` / 玻璃材质断言；`app_smoke_test` 断言外壳是 `FloatingNavBar` 而不是 `NavigationBar` |
| 基线：新增 `nav_bar@{phone_light,phone_dark,eink,phone_light_text1.3}` 与 `library_nav@phone_light`；`design_tokens@{phone_light,tablet_dark}` 因 `bar` 材质变玻璃而更新（`design_tokens@eink` 未变，说明退化路径没动） |

基线变更原因：`bar` 从"85% 不透明灰白"变成"72% + 反光 + 白描边"的玻璃，token 图上的 swatch 变透；
其余页面基线未动（外壳不进页面黄金图，真实首页形态单开 `library_nav@phone_light` 钉住）。

## 不做

| 需求 | 理由 |
|---|---|
| 逐格阅读（Panels View） | 需要机器学习模型，Panels 打磨多年仍然标着"实验性" |
| Live Text、主体抠图、实时翻译 | 依赖平台机器学习，且只有 iOS 有 |
| 内容锁（Face ID） | 和自建服务器的使用场景关系弱 |
| 本地导入、网盘、内置商店 | 不在 Komga 客户端的定位内 |
| 可替换 App 图标、付费主题 | 收益低 |

## 3. 批次与依赖

```text
第1批  P0-1 拆分 ─┬─ P0-2 动效 ─┬─ P0-6 反馈
                  ├─ P0-3 材质 ─┤
                  ├─ P0-4 形状 ─┘
                  └─ P0-5 字体（ADR，可并行）
第2批  P1-1 chrome ── P1-2 缩略图滑条 ── P1-7 下一本卡片
第3批  P1-3 适配 / P1-4 方向 / P1-6 双击（相互独立）  P1-5 动态背景（引擎先行）
第4批  P2-1 封面 ── P2-2 Hero ── P2-3 转场与大标题 ── P2-8 骨架
第5批  P2-4 详情页（需 fixture） ── P2-5 长按菜单（需端点） ── P2-6 首页 ── P2-7 视图选项
之后   P3 按需求挑选
```

每批的出口与路线图（`docs/roadmap.md`）一致：
- `ci.dart check` 全绿；
- 运行 `dart run tool/ci.dart install` 装到模拟器上实际操作走查；
- 单独提交并推送（**不等 CI 结果**；红了再修）。

## 4. 每个需求的统一检查单

- [ ] 数值全部来自 token，没有新的魔法数字；
- [ ] 墨水屏退化路径已实现并有黄金图；系统"减少动态效果"开启时同样退化；
- [ ] RTL 下行为正确（凡是涉及方向的需求）；
- [ ] 新 UI 补齐手机浅色、平板深色、墨水屏三张黄金图，并已用 `read_image` 自查；
- [ ] 改动的基线都能说明"为什么这次渲染变了"；
- [ ] 动效类需求在 Android 模拟器上实际看过，而不只是测试通过；
- [ ] 动画测试不用 `pumpAndSettle` 掩盖首帧问题；
- [ ] 文件不超过 350 行，类不超过 300 行；
- [ ] 相关 `docs/` 段落已更新。

## 5. 参考来源

- Panels 功能与付费分级：<https://guides.panels.app/premium/what-is-panels-premium>
- 阅读器配置、预设、动态背景：<https://guides.panels.app/read-content/reader-configurations>
- 缩略图滑条与双页分组：<https://guides.panels.app/read-content/double-page-grouping>
- 继续阅读（OPDS 流式阅读不支持）：<https://guides.panels.app/read-content/continue-reading>
- 阅读会话与 Reading Now：<https://guides.panels.app/read-content/reading-sessions>
- 键盘快捷键（排序与视图选项的完整列表）：<https://guides.panels.app/remotes-and-controllers/keyboard-shortcuts>
- Panels 的 Komga 支持说明：<https://www.panels.app/komga-ios-app>
- Panels 4 预告（新 UI 与转场）：<https://www.panels.app/blog/iphoneduo>

> 说明：Panels 的视觉细节（毛玻璃 chrome、封面阴影、长按菜单等）出自对该 App 的使用印象，
> 官方文档里没有对应的截图级描述。开始做 P1 和 P2 之前，建议先在 iPhone 或 iPad 上对照实机截图，
> 存进 `docs/assets/panels-ref/` 作为验收参照。
