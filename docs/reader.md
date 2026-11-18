# 阅读器：模式、设置与持久化

阅读器的代码分三层，改动前先认准层，别把几何塞进 widget、也别把网络塞进页面：

| 层 | 位置 | 职责 |
|---|---|---|
| 几何（纯 Dart） | `packages/komga_reader_engine` | 单页适配缩放、双页分组与视觉顺序、纵向偏移与页码映射 |
| 编排（Flutter） | `apps/app/lib/src/screens/reader_screen.dart` | 当前页、模式解析、进度回写、生命周期、亮度遮罩、常亮 |
| 绘制（Flutter） | `apps/app/lib/src/widgets/reader_{paged,vertical}_view.dart`、`reader_chrome.dart`、`reader_settings_sheet.dart` | 一屏画哪几页、顶栏底栏、设置面板 |

## 三种模式

- **单页**：一屏一页，点左右三分之一翻页，中间收 chrome；
- **双页**：`buildSpreads` 分组（封面单独、宽页单独、其余两两），RTL 时后一页画在左；
  顶栏页码显示 `2–3 / 12`；"最后一屏含末页"也算 `completed`（只按页码判断会让系列进度永远差一页）；
- **纵向连续**：`ListView` 按算好的每页高度铺开，滚动位置用 `pageAtViewportCenter`
  （视口中心法则 + 二分）换算页码；跳页用 `scrollOffsetForPage`。

## 手势、翻页方向与页码

- **缩放**：双指以**两指中点**为基准（`zoomAboutFocal` 纯函数，有单测），焦点下的画面停在原地；
  单指拖动平移，缩回适配尺寸自动归位。以前只改 `zoomFactor` 不动平移，手指在右下角捏合、
  画面却从左上角放大——这是真实反馈修掉的。
- **翻页方向**：左右三分之一的点击区与底栏两个箭头**共用同一个判断**
  （`ReaderControls.leftTurnsNext`，来源是系列 `readingDirection`）。RTL 漫画的左侧
  （点击区 / 左箭头）都是"下一页"，LTR 镜像；不会再出现"点左边前进、箭头左边后退"。
  后续加"从左到右 / 从右到左"设置时，只需要换掉这个判断的来源。
- **页码**：顶栏是"当前 / 总数"（`3 / 12`、`2–3 / 12`）；底栏只说**当前页**
  （`Page 3` / `Pages 3–4`）。底栏以前显示总页数，翻页时不变，看起来像页码坏了。

## 默认模式：跟随书

`ReaderModeChoice.auto` 是默认值：系列 `readingDirection` 为 `WEBTOON`/`VERTICAL` 时进纵向，
其余单页。**双页没有元数据可依**，只能用户选，所以模式是"偏好"而不是"每本书的属性"。

## 设置与持久化

| 项 | 行为 | 存储 |
|---|---|---|
| 阅读模式 | 全局偏好（auto/single/double/vertical） | `ReaderPrefs` JSON |
| 亮度 | 阅读区上盖一层黑色遮罩（`1 - brightness`），不吃点击 | 同上 |
| 常亮 | 进阅读器置真、退出置假；见下 | 同上 |
| 跳页 | 面板里拖动，松手才跳；滑条停在目标页不回弹；纵向模式走 `jumpToken` 触发滚动 | 不持久化（临时操作） |

**为什么不用 Drift 存这几个字段**：它们只有几字节、写入频率是"用户改设置"，
用已有的 `flutter_secure_storage` 就够；Drift 留给真正需要查询的东西（书架缓存、页图缓存、进度 outbox）。
`ReaderPrefsStore` 是接口，将来换 Drift 实现不动调用方。

坏存档必须回默认值（`ReaderPrefs.fromJson` 逐字段判类型 + 夹取），
亮度下限 0.2：存档里出现 0 也不能变成黑屏。

## 页图加载与预取（翻页不闪黑）

页图有三层，翻页走的是前两层，第三层只在**离线**时兜底：

| 层 | 内容 | 生命周期 |
| --- | --- | --- |
| `readerPageImageProvider` | 当前屏的原始字节（`AsyncValue`） | autoDispose：翻走即释放 |
| `KomgaReaderRepository._pages`（`ByteLruCache`） | 最近 16 页的原始字节 | 会话内，LRU |
| `PaintingBinding.imageCache` | 解码后的位图（`MemoryImage`） | Flutter 引擎管，默认 100 MB |
| `DriftHttpCache` | 磁盘上的响应体 | 只在请求**失败**时读（`KomgaSession._cachedBytes`） |

第三层是"断网还能翻回去看"，不是读穿缓存：**在线时 LRU 未命中的页仍会请求网络**。

**第一帧的字节不许等异步**：`ReaderPage` 先用 `ReaderRepository.cachedPageImage`
同步问一句"这页现在在不在内存里"，在就直接画（翻回去、预取过的页都是这条路径）。

为什么必须同步：provider 是 autoDispose 的，每换一页都会先给一次 `AsyncLoading`，
只等它的话第一帧就是"黑底 + 转圈"——用户看到的就是"翻页闪一下"。
这一条是踩过的坑：先把 provider 改成 autoDispose（为了不把整本留在内存里），
结果**连翻回去都开始闪**，因为旧的 provider 不会 dispose、恰好白拿了"首帧就有数据"；
补上同步查询后才两边都对，并钉了「翻页首帧」两条测试（只 `pump()` 一帧断言）。

真没加载好的页（LRU 里没有）：**黑底 + 转圈**。

试过"先继续画上一页"（把旧画面顶到新页解码完），反馈很难受：
页码变了、图没变，用户第一反应是"卡住了/是 bug"。所以宁可露出明确的"还没加载好"。
预取做深就是为了让这条路径尽量不出现（见下）。

预取（`apps/app/lib/src/screens/reader_screen.dart` + `komga_reader_engine/src/preload.dart`）：

- 计划按**屏**算（`preloadPlan`），不是 `page ± 1`。双页模式一屏两页，按页码加减会
  一直漏掉每屏的第二页，表现是"翻一屏闪一次、翻一页不闪"——很难查，所以钉了单测；
- 往前 **4 屏**、往后 **2 屏**抓字节（单页约 4 页 / 双页约 8 页），
  最近 **2 屏**额外 `precacheImage` 预解码；
  按 1 页/秒的阅读速度算，4 屏就是 4 秒以上的缓冲——阅读快的人不会翻两下就撞上转圈；
- 触点在 `build` 里（`_schedulePreload`），只在 **页码或模式变化**时排一次，下一帧执行：
  保证当前页自己的请求先出去（弱网下顺序就是优先级），也避免每帧重复排；
- 并发上限 4 张，其余**排队**（`_pumpPreload`：前一张回来就补下一张）。
  早先是"超上限直接丢"，阅读快时计划尾部永远轮不到——排队才对；
- **为什么光抓字节不够**：`Image.memory` 在解码完成前那一帧没有像素，看到的就是
  Scaffold 的黑底——这就是"闪一下黑"。预解码后翻过去首帧就有图；
  解码比抓字节浅一档，是因为一张 1500×2200 的页解出来约 13 MB，全部预解码会把
  默认 100 MB 的 `ImageCache` 挤爆；
- 纵向模式不在这里预取：`ListView.cacheExtent` 自己会建下面两屏，再叠一层是重复请求；
- 预取失败静默——真翻到那页时会重新请求并显示正常的错误/重试。

验证方式：`packages/komga_reader_engine/test/preload_test.dart` 钉计划；
`apps/app/test/reader_screen_test.dart` 的「页图预加载」组断言"翻过去之前请求过哪几页/几屏"
（`FakeReaderRepository.pageRequests`），并用 `runAsync` 放真实时间断言下一屏已进 `ImageCache`；
「翻页首帧」组只 `pump()` 一帧，断言第一帧里没有 `CircularProgressIndicator`、
`reader-image-*` 已经在了（`pumpAndSettle` 会把这种问题吞掉，别用它验闪烁），
其中一条用 `FakeReaderRepository.pageGates` 把页图请求挂住，验证冷页确实显示转圈。

## 翻页动画（卷页）

跟手卷页：手指横滑时当前页跟着卷起来，松手补完；点击/底栏箭头/音量键走同一套动画。

**渲染**（`widgets/page_curl.dart` + `shaders/page_curl.frag`）：

- 上层是"当前屏的一张位图"，用片元着色器把它绕一条折线卷成圆柱——不是平移贴图，
  折线两侧的采样方式不同，越靠折线内容被压得越扁，才有"纸被卷起来"的拉伸；
- 位图在**空闲时**由页图字节解码得到（`ui.instantiateImageCodec`，每次翻页结束一帧后），
  所以开始拖的那一刻就有图，不占翻页关键帧；页图字节本来就在仓库 LRU 里，等于不额外下载；
- 下层是**相邻那一屏本身**的 widget：翻页时它已经被预取过，正常加载；
  万一没加载好，这里就是黑底 + 转圈，上层的卷页照常进行（用户看得到"下一页在下面"）。

> **踩过的坑**：第一版用 `RenderRepaintBoundary.toImage()` 截当前屏当"这张纸"。
> 本地 widget 测试能跑通，真机上 `toImage` 永远拿不到 layer（`Null check operator
> used on a null value`），滑动翻页直接没有任何反馈。改成从页图字节自己解码后一次通过。
> 结论：截图类 API 必须真机验证，`pumpAndSettle` 绿了不代表设备上能用。

**几何**（`packages/komga_reader_engine/lib/src/page_turn.dart`，纯数值 + 单测）：

- 折线不是竖直的：起手过**书页角**（RTL 左下角、LTR 右下角）倾角 `kCurlTilt`≈31°，
  越翻越立直，临近**书脊**（RTL 右边、LTR 左边）变成竖直线——完全竖直的轴看起来像卷帘；
- 折线位置用 smoothstep 推进（慢—快—慢），不是线性：起手"掀起一个角"、中段扫过、
  贴书脊前收住；
- 圆柱半径 = 页宽 × `kCurlRadiusRatio`，但**随进度增长**：起手只有
  `kCurlRadiusStart`（22%）那么细的一个"翘起的页脚"，翻到 `kCurlRadiusGrowAt`
  （65%）附近才长成完整的卷筒。半径恒定的话，一上来就是一根细筒，不符合物理；
- 卷筒半径**沿折线也不均匀**：从"被捏住的角"往外逐渐变粗（`kCurlConeRatio`），
  所以起手是一个**尖的页脚**、往上看才慢慢变成等粗的卷筒——这是"捏住书页角"
  和"一根圆柱"的区别所在；
- 折线要走满 **页宽 + 一个半径**（不是只到页宽）：最后阶段卷筒从右边滑出去、
  可见宽度逐渐收窄到 0。只走到页宽的话，收尾会剩一根竖直白条停在右边缘、
  然后凭空消失（真机上截到过，就是"翻页结束很硬"的来源）；
- 着色器只画在**纸面矩形内**：纸不会跑到书页区域之外，收尾时卷筒滑出去而不是
  在黑色留白上画白条；
- 倾角衰减指数 `kCurlTiltDecay`。这几个常量就是全部手感参数，调只改这里；
- 单测钉的是"起手必须过角""收尾必须贴书脊且立直""倾角单调减""位移非线性"
  "卷筒从细长到粗""收尾时卷筒整个滑出纸面"，不钉具体像素——像素靠真机截图看。

> **法线方向别写反**：法线的 y 分量必须是负的（朝上）。写成 `+sin` 时"还没翻走"
> 的一侧会跑到下边，被掀起来的变成**左上**那半边——表现是"从左上角翻页"，
> 而且 p 刚离开 0 就几乎整页翻掉（看起来像跳变）。`page_turn_test.dart` 里
> 「起手是从左下角掀起」那条就是钉这个的。

> **卷筒必须是不透明的白纸背**：着色器里圆筒那一段**不能**返回透明
> （越界采样时要给纸背颜色）。返回透明会让卷边看起来像一层玻璃，
> 下层页面从"纸"里透出来。纸背面用偏暖的白（`kPaper`），随 `t` 由印面渐变过去。

> **收尾要淡出**：进度接近 1 时接触阴影和投在下层的影子都要收掉
> （`tailFade`），否则最后一帧会有一条阴影"啪"地消失——前后页尺寸不同时最明显。

> **贴图延迟一帧释放**：换页后立刻 `dispose()` 有时会闪一帧空白，
> 统一 `_retire` 到下一帧结束再释放。

**松手补完必须从当前进度接着播**（`_startSettle`）：直接把 `animateTo(1)` 交给
`AnimationController` 的话，起点是 controller 的旧值（0），表现是"已经翻了 70%，
一松手跳回 0 再重播"。所以要先把 `controller.value` 对齐到当前进度，
再按剩余距离反算时长（`animateTo` 自己会按剩余比例压缩，传入时要除回去）。

**手势与判定**（`widgets/reader_paged_view.dart`）：

- 单指、未缩放、`|dx| > 14px` 且横向占优（`|dx| > |dy| * 1.4`）才进入拖拽；
  双指一旦出现就标记为缩放，本次手势不再翻页；
- 进度 = 横向位移 / 视口宽；松手按 `settlePageTurn` 判定：拖过 35% 或轻扫（≥350px/s）
  就补完，否则回弹；补完时长按剩余距离算，下限 120ms、上限 400ms；
- 动画期间忽略新的点击/拖动（`_TurnPhase != idle`）。

**回退与不做动画的场景**：

| 场景 | 行为 |
| --- | --- |
| 单页模式、往前翻 | 卷页 |
| 往前翻之前的页 | 平移（**没有上一屏的快照**——屏幕上只有当前屏） |
| 双页模式 | 平移（按用户确认：双页先不做卷页） |
| 墨水屏 / 系统"移除动画" | 不做动画：点击瞬切，横滑不响应 |
| 着色器加载失败 | 平移（不报错） |

**已知边界**：

- 着色器在 Windows 黄金图上是 Skia、真机上是 Impeller，像素级会有细微差异；
  黄金图只覆盖静态页面，卷页中间态靠真机截图 + 几何单测；
- 快照分辨率是设备像素（`toImage(pixelRatio: devicePixelRatio)`），
  在超低端设备上 `toImage` 可能较慢，此时退化为"这一帧先用平移"。

## 缩略图跳页

- 顶栏的网格按钮打开缩略图面板（`widgets/page_navigator_sheet.dart`），当前页描白边；
- Komga **没有页级缩略图接口**（`/books/{id}/thumbnail` 是整本封面），所以缩略图就是页图本身：
  网格懒构建 + `cacheWidth: 240` 解码降采样，只有滚到的页才会下载；
- 点一张 = 走和设置面板跳页同一条路径（纵向模式也会滚过去）；
- 黄金图 `reader_pages@phone_dark`：缩略图是**真实异步解码**，基线要在 `act` 之后
  放一小段真实时间（`settleAfterActWithRealTime`），否则截到的是黑块（踩过）。

## 书末：下一本 / 回系列

读到最后一页（双页模式：最后一屏含末页）时，底栏上方出现一条 `Finished`：

- **下一本**：按系列书列表的顺序取下一本；点它 = `pushReplacement` 打开。
  用替换而不是压栈：连读十本不必按十次返回，书架层级始终是"系列 → 当前这本"。
- **Series**：退回系列详情。
- 拿不到下一本（已是最后一本 / 离线没缓存 / 系列超过 100 本）时只显示 `Finished`，
  **不报错**——"下一本"是锦上添花，不能因为它把读完的页面变成错误页。
- 完成判定同时用于进度回写，所以"看到完成条"与"服务端 completed=true"是同一个条件。

## 硬件键：音量键翻页

`HardwareKeys`（`packages/komga_platform/lib/src/hardware_keys.dart`）把原生音量键变成
`Stream<PageTurnKey>`；阅读器 `initState` 订阅、`dispose` 取消：

- 音量上 = 上一页，音量下 = 下一页（阅读顺序，不跟 RTL 反转）；双页模式按"一屏"翻；
- 纵向连续模式忽略按键，滚动仍交给 `ListView`；
- Android 在 `MainActivity.dispatchKeyEvent` 里消费 ACTION_DOWN（系统音量不再变化）；
  iOS/桌面没有实现，`MissingPluginException` 静默降级为空流。

实现边界、事件消费的全局副作用与验证状态见 [docs/a11y-and-input.md](a11y-and-input.md)。

## 屏幕常亮

`packages/komga_platform/lib/src/wakelock.dart` 走 `komganative/device` 通道，Android 侧在
`MainActivity.kt` 只加一个 `FLAG_KEEP_SCREEN_ON`。故意没引 `wakelock_plus`：
需求就是一个 flag，加插件等于多一层原生构建面。

- Android：**已在模拟器上验证**（`dumpsys window` 里能看到 `fl=KEEP_SCREEN_ON`，关掉即消失）；
- iOS：**未实现**（`MissingPluginException` 被静默吞掉，只是不常亮，不影响阅读）。
  没有 macOS 环境验证，宁可留空也不写一段没跑过的 `AppDelegate` 代码。

## 已知缺口

- 亮度是**应用内遮罩**，不改系统亮度（系统亮度需要新插件；遮罩已能满足"夜里不刺眼"）；
- 偏好是全局的，不按书记忆；
- 纵向模式不叠加缩放（交给滚动）；
- 分页模式只预取前面 4 屏 / 后面 2 屏，**不预下载整本**（离线整本阅读靠"下载"功能，不靠预取）；
- 在线时页图只要不在 16 张 LRU 里就要重新请求网络（磁盘缓存是离线兜底，不是读穿缓存）；
  这种"很远的回翻"不会黑屏（会先画上一帧），但会明显停一下。
- 预解码依赖默认 100 MB 的 `ImageCache`：普通扫描页（约 1000×1400 ≈ 5.6 MB）装得下十几张，
  但超大页（解出来 > 30 MB）会把预解码的那张挤出去，翻页仍可能闪一次——真遇到了再按需
  放宽预算或降采样，别一上来就动全局参数。
