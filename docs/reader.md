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

## 缩略图跳页与预取

- 顶栏的网格按钮打开缩略图面板（`widgets/page_navigator_sheet.dart`），当前页描白边；
- Komga **没有页级缩略图接口**（`/books/{id}/thumbnail` 是整本封面），所以缩略图就是页图本身：
  网格懒构建 + `cacheWidth: 240` 解码降采样，只有滚到的页才会下载；
- 点一张 = 走和设置面板跳页同一条路径（纵向模式也会滚过去）；
- 预取：翻页后对 `+1 / -1 / +2` 三页调一次仓库的 `pageImage`，只暖内存 LRU（8 张），
  失败静默——真翻到那页时仍会重新请求并显示错误；
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
- 纵向模式不叠加缩放（交给滚动）。
