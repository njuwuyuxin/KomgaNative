# 设计系统：token 与基础组件

> 对应 `docs/ui-polish-plan.md` 第 1 批（P0）。代码在 `packages/komga_design_system/lib/src/`。

## 规则

1. 页面里的**数值只从 token 取**（间距、尺寸、圆角、时长、曲线、阴影、模糊）。
2. **墨水屏与"减少动态效果"的退化在 token 里做**，页面不自己判断：
   - 主题是不是墨水屏：`AppTheme.isEink(theme)`；
   - 每个 token 都有 `of(context)`（自动退化）和 `resolve(eink: …)`（纯函数，便于单测/控制器）。
3. 毛玻璃与触感反馈**只能**经 `FrostedSurface` / `AppHaptics`。
   `tool/ci.dart layers` 会拦 `screens/`、`widgets/` 里直接写 `BackdropFilter(` 或 `HapticFeedback.`。

## Token 一览

| 类 | 文件 | 内容 | 墨水屏 / 减少动态效果 |
|---|---|---|---|
| `AppSpacing` | `tokens.dart` | xxs 2 / xs 4 / sm 8 / md 16 / lg 24 / xl 32 / xxl 48 | — |
| `AppRadii` | `tokens.dart` | xs 6（封面）/ sm 8 / md 12 / lg 20 / xl 28（面板顶角） | 主题与 `AppShapes` 压成 0 |
| `AppSizes` | `tokens.dart` | 分隔线、图标 16/18/20/24、进度条、最小触控 48、拖动条、货架封面 96×136、阅读器缩略图 36×52 与滑条高 68、卡片行小封面 44×62 等 | — |
| `AppMotion` | `motion.dart` | 时长 quick 150 / standard 300 / emphasized 450 ms；曲线 standard（easeOutCubic）、emphasized（轻微过冲）、exit；弹簧 snappy / gentle | 时长 0、曲线线性、`enabled = false`（调用方直接跳终值） |
| `AppMaterial` | `materials.dart` | `chrome`（阅读器，深色强模糊，不跟随深浅色）/ `bar` / `sheet`，各有深浅两档 | 不模糊、不透明纸色底 + 1px 墨色描边 |
| `AppShadows` | `materials.dart` | cover / card / floating：大半径、低透明度、向下偏移 | 空列表 |
| `AppShapes` | `shapes.dart` | cover / card / panel 用 `ContinuousRectangleBorder`（squircle 近似），sheet 只圆顶角 | 直角；sheet 改描边 |
| `AppTypography` | `typography.dart` | largeTitle / title / headline / body / caption / label / pageNumber（等宽数字） | —（字号跟随系统缩放） |

`AppDurations` 已删除：它在 app 里没有任何引用，由 `AppMotion` 取代（只保留一个出口）。

### 为什么连续圆角要乘系数

`ContinuousRectangleBorder` 的 `borderRadius` 不是"视觉圆角"：同样的数值，看起来只有
`RoundedRectangleBorder` 的一半左右。`AppShapes` 统一乘 `2.2`，让 `AppRadii.md` 在两种形状上
大小接近；页面不要自己再乘。

### 为什么阅读器 chrome 不跟随深浅色

chrome 永远压在漫画画面上：浅色模式下用浅色毛玻璃，白底漫画上文字会糊成一片。
与 iOS 照片 / 图书的做法一致，阅读器 chrome 固定深色材质。

## 组件

| 组件 | 作用 | 退化 |
|---|---|---|
| `FrostedSurface` | 裁剪 → `BackdropFilter` → 半透明底色（可传 `shape`） | 墨水屏不建 `BackdropFilter` |
| `PressableScale` | 按下缩到 0.97、松开用 `snappy` 弹簧回弹；用 `Listener` 监听原始指针，不抢子组件的点击/长按/滚动 | 墨水屏 / 减少动态效果时完全透传 |
| `AppHaptics` | `selection` / `light` / `success` 三种语义 + 总开关 | 墨水屏保留（不影响刷新）；设置页"触感反馈"关闭时全部静默 |

**性能约束**：`BackdropFilter` 每帧都要读回背后像素，只用于 chrome、导航栏和面板，
**不要放进网格单元格或列表行**。

## 触感反馈开关

设置页「触感反馈」（`settings-haptics`）→ `SettingsState.haptics`（默认开启）→
`KomgaApp` 每次 build 同步到 `AppHaptics.enabled`。存储在 `komganative.settings.v1`
的 JSON blob 里（与语言同一个 blob，写入是"读出 → 改一个字段 → 写回"，互不覆盖）。

## 验证

- `packages/komga_design_system/test/tokens_test.dart`：各 token 的普通 / 墨水屏 / 减少动态效果三种取值，
  `PressableScale` 的按下回弹、不抢点击、墨水屏透传，`FrostedSurface` 的墨水屏退化，`AppHaptics` 的映射与开关。
- 黄金图 `design_tokens@{phone_light,tablet_dark,eink}`：彩色条纹上的三种毛玻璃、三档阴影与形状、字体层级。
  改 token 时先看这三张图变没变，再看页面。
- 中文：见 ADR 0004。
