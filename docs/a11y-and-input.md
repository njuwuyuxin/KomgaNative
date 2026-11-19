# 无障碍、输入与形态适配

> 阶段 H 的落地说明。范围：**音量键翻页（Android）、读屏语义与最小点击区、平板两栏、
> 墨水屏的边界**。这份文档只写已经落地并有测试/基线支撑的行为；没验证过的会明确标注。

## 音量键翻页（仅 Android）

### 链路

| 层 | 位置 | 行为 |
|---|---|---|
| 原生 | `android/.../MainActivity.kt` | `dispatchKeyEvent` 捕获 `KEYCODE_VOLUME_UP/DOWN` 的 `ACTION_DOWN`，在 `komganative/device` 通道上 `invokeMethod("volumeKey", "up"/"down")`，并 **返回 true 消费事件** |
| 抽象 | `packages/komga_platform/lib/src/hardware_keys.dart` | `HardwareKeys.volumeKeys` → `Stream<PageTurnKey>`；`ChannelHardwareKeys` 用 `MethodCallHandler → StreamController` 接收 |
| 编排 | `apps/app/lib/src/screens/reader_screen.dart` | `initState` 订阅，`dispose` 取消；单页/双页映射成 `_turn(-1/+1)`，纵向连续忽略 |

映射固定为 **音量上 = 上一页，音量下 = 下一页**（阅读顺序，不跟随 RTL 反转）。
双页模式下"上一页/下一页"是一整屏（一跨页），与点按翻页共用同一条 `_turn` 路径，
因此页码、进度回写、预取的行为完全一致。

### 事件消费与副作用

原生返回 `true` 后系统音量不再变化。但**只在阅读器激活期间**这样：Dart 侧
`HardwareKeys.setActive(true/false)` 在阅读器 `initState`/`dispose` 里调用，
原生侧用一个布尔开关决定要不要消费。否则整个 App（列表、设置、弹窗）都按不了音量，
那是比"不能翻页"更严重的回归。

长按音量键会产生多次 `ACTION_DOWN`（repeat），表现为连续翻页；这是有意的，
和按住翻页键的直觉一致。

### 降级

`ChannelHardwareKeys` 订阅时先 `invokeMethod("volumeKeys")` 握手一次：

- 平台没有实现（iOS / 桌面 / 测试）→ `MissingPluginException`，**静默保持空流**，
  阅读器没有任何反应，也不会把错误画到页面上；
- 通道在但握手失败 → `PlatformException`，同样静默；
- Android 原生侧对 `volumeKeys` 直接返回成功，之后才安装方法处理器。

## 读屏语义

（键盘 / 蓝牙翻页器见 [docs/reader.md](reader.md) 的"手势、翻页方向与页码"：阅读器
根节点 autofocus，方向键/PageUp/PageDown/空格翻页，Esc 退出。）
约定：**用户可见文案一律来自 `context.l10n`**；设计系统不持有 l10n，因此组件只接受
调用方传入的语义文案。语义树里的每个"可点区域"尽量只播报一句完整的话，而不是把
封面首字、角标、标题逐条念一遍。

| 区域 | 实现 | 语义内容 |
|---|---|---|
| 书架系列卡片 | `SeriesTile` 的 `Semantics(container, button, label)` + `ExcludeSemantics` 包住整张卡 | 标题 + `readOfTotal`（由 `SeriesShelfTile` 从 l10n 传入；设计系统不再硬编码「已读」） |
| 继续阅读卡片 | `Semantics(container, button, label, onTap)` + `ExcludeSemantics` 包住 `InkWell` | 书名 + `continueReadingProgress` / `bookPages` |
| 系列书行 | `SeriesBookRow` 的 `Semantics(container, button, label, onTap)` | `#卷号 · 书名` + 页数/已读状态；下载按钮保留为独立的按钮节点 |
| 阅读器顶/底栏 | `IconButton` + `tooltip`（Flutter 把 tooltip 放进语义的 `tooltip` 属性） | Close / Page thumbnails / Reading settings / Previous page / Next page |
| 下载按钮 | `IconButton` + `tooltip` | Download for offline reading / Downloaded · tap to remove / … |

### 最小点击区

- Material `IconButton` 默认 48×48（顶/底栏、下载按钮、搜索、排序等）；
- 继续阅读卡片是 96×196 的自定义 `InkWell`，整卡可点；
- 书架卡片本身是网格单元（`maxCrossAxisExtent: 190`，宽高都远超 48）；
- 书行是 `ListTile`，整行可点；
- 没有用 `MaterialTapTargetSize.shrinkWrap` 把任何按钮压到 48 以下。

`apps/app/test/a11y_test.dart` 用 `tester.getSemantics(find.byKey(...))` 断言了：
书架卡片的 label/button、继续阅读卡片的 label/button、书行的可读标签、下载按钮的
独立语义，以及阅读器五个图标按钮的 `tooltip` 语义与尺寸。语义测试必须在测试体末尾
**显式 `handle.dispose()`**：框架在 `tearDown` 之前检查未释放的 `SemanticsHandle`。

## 平板两栏（系列详情）

`SeriesDetailScreen` 用 `WindowSizeClass.of(MediaQuery.sizeOf(context).width)` 做**一次**
决策：

- `expanded`（≥1024）：`SeriesTwoPane`，左头部 / 右书列表，中间 1px 分隔线；
- 其余：保持原来的单栏（头部与书列表同一条滚动流）。

阈值刻意用 `expanded` 而不是"非 compact"：758×1024 的墨水屏、844×390 的横屏手机
放进两栏会把书列表挤成一条缝，竖向空间也不够。两栏布局拆在
`apps/app/lib/src/widgets/series_two_pane.dart`，`series_detail_screen.dart` 只负责
选择布局与路由；书列表的三态（骨架 / 错误 / 内容）在
`apps/app/lib/src/widgets/series_book_list.dart`，单本书行在
`apps/app/lib/src/widgets/series_book_row.dart`。

两栏模式的**头部第一帧就在**（封面 + Hero 落点），左侧与右侧各自渲染占位：
元信息与书列表异步到，到了再填。占位骨架都包在 `ExcludeSemantics` 里，
读屏不会念"空块"，只会念加载完成后的标题/进度/书行。

黄金图：`series@tablet_dark`（1024×768，深色）按两栏重新生成；新增
`series@tablet_two_pane`（同尺寸、浅色）。手机 / 墨水屏金图未变，说明窄屏路径没有漂移。
首次打开的占位态单独三张：`series_loading@{phone_light,tablet_two_pane,eink}`。

## 墨水屏边界

已经有的：

- e-ink 主题零动画、零阴影、无水波纹、纯黑白（`AppTheme.eink`）；
- **自动探测**（UI-P3-14）：Android 原生侧按 `Build.MANUFACTURER/BRAND/MODEL` 匹配
  Onyx/Boox、reMarkable、PocketBook、Kobo、Tolino、Boyue/LikeBook、Meebook、Supernote、Hisense
  等标记；命中后 App 自动用 e-ink 主题。探测失败/未实现（iOS、测试）一律 unknown，
  不阻塞启动；手动"墨水屏模式"开关仍然优先。
- 阅读器在墨水屏上用白底黑字（黑底会触发整屏全刷），顶栏/底栏/错误页同一套配色；
- 大尺寸点击目标（见上），避免小按钮在低刷新率屏幕上难按。

**本次没做**：

- 没有用户可调的"对比度 / 灰度"选项——只有固定的 e-ink 主题；加曲线/`ColorFilter`
  需要单独评审（会影响三套主题与所有金图）；
- 没有在真实墨水屏设备（Boox / Kindle）上做残影、刷新模式的主观验收；
- 没有做"可关闭阴影"的运行时开关（e-ink 主题本身就是零阴影）。

## 高刷新率（仅 Android）

`MainActivity.onCreate` 里调用 `requestHighestRefreshRate()`：在分辨率与当前模式相同的
`Display.Mode` 中挑刷新率最高的，写入 `WindowManager.LayoutParams.preferredDisplayModeId`，同时设置
`preferredRefreshRate`，因为有的 ROM 只认这个字段。

为什么要做：不少 ROM 会把**没有主动申请**高刷的 Flutter 应用（SurfaceView）锁在 60Hz。
用户在 120Hz 真机上反馈书架滑动"不够丝滑"，在系统设置里手动给本应用开启 120Hz 后立刻顺滑，
可以确认瓶颈在帧率档位，不在渲染耗时。

- 只申请、不强制：省电模式、温控、系统策略仍可降频；
- 不换分辨率：只在同分辨率的模式里挑；
- 墨水屏 / 单模式设备：只有一个模式，等于没设；
- iOS：ProMotion 需要在 `Info.plist` 里声明 `CADisableMinimumFrameDurationOnPhone`，**本次没做**
  （没有 macOS 环境验证）。

## 验证与未验证

已由门禁覆盖：

- `packages/komga_platform/test/hardware_keys_test.dart`：`up/down` 映射、未知参数忽略、
  无原生实现时静默空流，以及**通道参数形状**（`setActive` 必须发 `{"active": bool}`）；
- `apps/app/test/reader_screen_test.dart`：单页按键翻页、双页按屏翻页、纵向模式忽略；
- `apps/app/test/series_detail_screen_test.dart`：宽屏两栏 / 手机单栏的几何断言；
- `apps/app/test/a11y_test.dart`：语义与 48 点击区；
- 黄金图：`series@tablet_dark`（重生成）、`series@tablet_two_pane`（新增）。

已在模拟器上验证（Android release，2026-11-18）：

- `adb shell input keyevent 25` / `24` 在阅读器里分别是下一页 / 上一页（页码 21→22→21），
  并且**系统音量面板不再弹出**（之前会弹，见下）；
- 这里修过一个只在设备上暴露的 bug：`setActive` 以前把**裸 bool** 当通道参数发，
  原生侧 `call.argument<Boolean>("active")` 拿到非 Map 抛 `ClassCastException`
  （logcat: `MethodChannel#komganative/device: java.lang.ClassCastException`），
  调用失败又被 Dart 侧的 `on PlatformException` 吞掉 → `volumeKeysEnabled` 恒为 false，
  音量键只调系统音量、不翻页。单测用 `FakeHardwareKeys`，只验证了 Dart 侧事件流，
  所以"功能编译通过、测试全绿、真机上不工作"。现在的契约测试补上了这一层。
- 仍未验证：真实墨水屏设备（Boox / Kindle）上的按键手感与刷新表现。

未验证：

- iOS 的屏幕常亮仍未实现（见 `docs/reader.md`）：没有 macOS 环境，不写没跑过的
  `AppDelegate` 代码；iOS 音量键也没有实现；
- 没有用 TalkBack / VoiceOver 做人工走查；语义测试只到语义树，不等于真实读屏体验。
