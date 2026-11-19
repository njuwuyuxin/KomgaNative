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
| `AppSizes` | `tokens.dart` | 分隔线、图标 16/18/20/24、进度条、最小触控 48、拖动条、货架封面 96×136、阅读器缩略图 36×52 与滑条高 68、卡片行小封面 44×62、悬浮导航条高 64 / 底部留白 112 | — |
| `AppMotion` | `motion.dart` | 时长 quick 150 / standard 300 / emphasized 450 ms；曲线 standard（easeOutCubic）、emphasized（轻微过冲）、exit；弹簧 snappy / gentle | 时长 0、曲线线性、`enabled = false`（调用方直接跳终值） |
| `AppMaterial` | `materials.dart` | `chrome`（阅读器，深色强模糊，不跟随深浅色）/ `bar`（液态玻璃：更透 + 提饱和 + `GlassOptics`）/ `sheet`，各有深浅两档 | 不模糊、不透明纸色底 + 1px 墨色描边 |
| `GlassOptics` | `glass_optics.dart` | 液态玻璃光学参数：饱和度、外缘折射（拉进距离 / 环带宽）、内缘聚光、8 方向镜面高光、轮廓、选中嵌入胶囊底色；`light` / `dark` 两档 | 墨水屏为 null |
| `AppShadows` | `materials.dart` | cover / card / floating：大半径、低透明度、向下偏移 | 空列表 |
| `AppShapes` | `shapes.dart` | cover / card / panel 用 `ContinuousRectangleBorder`（squircle 近似），sheet 只圆顶角，bar 是胶囊 | 直角；sheet 改描边 |
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
| `FrostedSurface` | 裁剪 →（液态玻璃档）外缘折射 → `BackdropFilter` 模糊（+ 提饱和）→ 半透明底色 → 体内反光 →（液态玻璃档）内缘聚光 + 方向性镜面高光边 + 轮廓（可传 `shape`） | 墨水屏不建 `BackdropFilter`、不画反光与光学层 |
| `GlassSurface` | `FrostedSurface` + 浮层阴影，默认胶囊形（导航条 / 搜索圆球） | 墨水屏不模糊、不反光、无阴影，只剩纸底 + 墨边 |
| `GlassRefraction` / `GlassLightPainter` | 液态玻璃合成版（fallback）的两块光学零件（`glass_optics_layers.dart`），只由 `FrostedSurface` 组装，页面不要直接用 | 墨水屏不会建出来 |
| `LiquidGlassShaderSurface` | 液态玻璃着色器版（`liquid_glass_shader.dart` + `shaders/liquid_glass.frag`），Impeller 真机上由 `FrostedSurface` 自动选用 | 墨水屏 / 非 Impeller / 加载失败 → 合成版 |
| `PressableScale` | 按下缩到 0.97、松开用 `snappy` 弹簧回弹；用 `Listener` 监听原始指针，不抢子组件的点击/长按/滚动 | 墨水屏 / 减少动态效果时完全透传 |
| `SkeletonBox` / `Shimmer` | 加载骨架色块 / 给骨架加一条扫过的高光（周期取 `AppMotion.shimmer`） | 墨水屏不画微光；`SkeletonBox` 改用 12% 墨色填充（墨水屏的 `surfaceContainerHighest` 会兜底成纸白，骨架会看不见） |
| `AppHaptics` | `selection` / `light` / `success` 三种语义 + 总开关 | 墨水屏保留（不影响刷新）；设置页"触感反馈"关闭时全部静默 |

**性能约束**：`BackdropFilter` 每帧都要读回背后像素，只用于 chrome、导航栏和面板，
**不要放进网格单元格或列表行**。

## 底部悬浮玻璃导航条

手机形态用 `widgets/floating_nav_bar.dart` 的 `FloatingNavBar`：一条胶囊放
"正在读 / 书架 / 设置"三个 tab，右侧一颗同高的搜索圆球（iOS 26 的排布）。
它替换了 Material 的 `NavigationBar`——后者的高度、指示器、水波纹和"整条贴底"
都是安卓味；这里要的是离屏幕边缘留白、内容从下面模糊穿过、按下轻微缩放。

几条必须知道的约定：

1. **内容真的从玻璃下面过**：`AdaptiveShell` 用 `Scaffold(extendBody: true)`，
   所以页面要自己在滚动内容末尾留 `AppSizes.navBarClearance`（112，已含最长一档
   安全区 + 条高 64 + 上下留白）。漏了的表现是"最后一行点不到"。
2. **键盘**：外壳 `resizeToAvoidBottomInset: false`，导航条留在原位被键盘盖住
   （iOS 的行为）；页面自己的 `Scaffold` 仍会为键盘让位。
3. **选中态**：彩色主题按 iOS 26——玻璃里再嵌一块**中性**胶囊（`GlassOptics.selectionFill`，
   浅色压一层灰、深色提一层白），只有图标/文字用主色；整块铺主色会把玻璃染成塑料。
   墨水屏反过来（墨底纸白），灰阶上一眼能认出来。
4. **标签比页面标题短一档**：英文 tab 是 "Reading"（页面标题仍是 "Reading now"），
   因为 "Reading now" 在 1.3 倍字号下会被截成 "Reading n…"。新增 tab 时先用
   `nav_bar@phone_light_text1.3` 这双眼睛看一下。
5. **只有搜索没有文字**：圆球靠 `Tooltip` + `Semantics(label:)` 表达，读屏念"搜索"。

基线：`nav_bar@{phone_light,phone_dark,eink,phone_light_text1.3}` 是导航条本身
（背后铺高对比条纹，才看得出透了多少）；`library_nav@phone_light` 是"书架 + 导航条"
的真实首页形态，专门钉住玻璃压在封面上的观感。

### 液态玻璃怎么合成

两条路径，由 `FrostedSurface` 自动选：

- **着色器版（真机 Impeller）**：`packages/komga_design_system/shaders/liquid_glass.frag`，
  `main()` 启动时 `LiquidGlassProgram.ensureLoaded()`。单层 `BackdropFilterLayer(ImageFilter.shader)`：
  圆角矩形 SDF 求外法线 → 外缘斜面（`bezel` 18）向内采样折射（外缘最大位移 `refraction` 22）
  → RGB 分通道不同位移做色散（`chromaticAberration` 0.12）→ 着色器内 12 点圆盘轻模糊（半径 4）
  → 提饱和 / 提亮 / 底色 → 斜面柔光 → 沿轮廓、随光向（左上主光、右下内反射）变化的镜面高光。
  参数在 `LiquidShaderParams.light / dark`。
  - 实测坐标约定（模拟器 Impeller/GLES，探针：位置编码背景 + 把 `FlutterFragCoord` / `u_size` 编进颜色）：
    `FlutterFragCoord()` 是**屏幕物理像素**，与所在图层无关；输入纹理按 `FlutterFragCoord()/u_size`
    采样与屏幕对齐，且能采到裁剪框外的背景（折射需要）。
  - **不要**把着色器和 `ImageFilter.blur` 用 `compose` 组合：实测组合后 `u_size` 变成带模糊外扩的尺寸、
    采样坐标偏移，画面整块错位。模糊放在着色器里做。
  - 玻璃的屏幕矩形每帧 paint 时取（`getTransformTo(null)`），并在帧尾比对屏幕位置，祖先平移
    （转场 / 外层图层 offset）时补画一帧。
  - 着色器版在黄金图里**看不到**（测试渲染器不是 Impeller），视觉验收只能在真机 / 模拟器上做。
- **合成版（fallback：测试渲染器 / Skia / 着色器加载失败）**：iOS 26 Liquid Glass 的观感拆成五层，
  全部用 Flutter 自带的滤镜 / 画笔合成，黄金图钉住的是这一版：

| 层 | 实现 | 参数 |
|---|---|---|
| 背后提饱和 | `ImageFilter.compose(ColorFilter.matrix(饱和), blur)` | `saturation` 1.8 / 1.6 |
| 外缘折射 | 只在外缘环带（外形 − 内缩外形，`evenOdd`）里生效的背景滤镜，以玻璃中心为原点缩小背景：外缘显示玻璃外 `refraction` 远的内容，越往里偏移越小；随后整体模糊揉平接缝 | `refraction` 10 / `refractionBand` 14 |
| 内缘聚光 | 沿外轮廓的两倍宽模糊描边，外半被裁掉，只剩向内渗的柔光 | `rimLight` / `rimWidth` 6 |
| 镜面高光边 | 沿外轮廓的 `SweepGradient` 描边，8 个方向各一档亮度：左上主光、右下反射、另两侧暗 | `specular` / `specularWidth` 1.2 |
| 轮廓 | 1px 暗线，浅色背景上把玻璃托出来 | `contour` |

坐标约定（实测，见下）：`BackdropFilterLayer` 里的 `ImageFilter.matrix` 作用在**当前图层的逻辑坐标**里，
所以折射的缩放原点取 `paint(offset)` 里的 `offset + size.center`，滚动 / 按下缩放 / DPR 都不影响。
这条是在 Windows 测试渲染器上用条纹探针量出来的（偏移 60px 的 `RepaintBoundary` 里，2 倍缩放以盒中心为不动点）；
真机 Impeller 的表现以 `ci.dart install` 后的设备观感为准。

## 触感反馈开关

设置页「触感反馈」（`settings-haptics`）→ `SettingsState.haptics`（默认开启）→
`KomgaApp` 每次 build 同步到 `AppHaptics.enabled`。存储在 `komganative.settings.v1`
的 JSON blob 里（与语言同一个 blob，写入是"读出 → 改一个字段 → 写回"，互不覆盖）。

## 验证

- `packages/komga_design_system/test/tokens_test.dart`：各 token 的普通 / 墨水屏 / 减少动态效果三种取值，
  `PressableScale` 的按下回弹、不抢点击、墨水屏透传，`FrostedSurface` / `GlassSurface` 的墨水屏退化
  （不模糊、不反光、无阴影），`AppHaptics` 的映射与开关。
- `apps/app/test/widgets/floating_nav_bar_test.dart`：导航条的点击派发、48 点按区、
  `selected` 语义、搜索圆球的读屏标签、墨水屏反白、1.3 倍字号不溢出。
- 黄金图 `design_tokens@{phone_light,tablet_dark,eink}`：彩色条纹上的三种毛玻璃、三档阴影与形状、字体层级。
  改 token 时先看这三张图变没变，再看页面。
- 黄金图 `nav_bar@{phone_light,phone_dark,eink,phone_light_text1.3}` 与 `library_nav@phone_light`：
  导航条本身 + 真实首页形态（见上一节）。
- 中文：见 ADR 0004。
