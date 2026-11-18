# ADR 0004：中文字体——App 走系统字体，黄金图用 Noto Sans SC 子集

- 状态：已采纳（2026-11-18）
- 相关：`docs/i18n.md`「中文字体与中文黄金图」、`docs/ui-polish-plan.md` UI-P0-5

## 背景

阶段 G 留下两个问题：

1. 黄金图只加载 Roboto，中文界面截出来是占位方块，**中文排版无法回归**；
2. 设计 token（UI-P0-5）要定字体排印层级，需要决定 App 里中文用什么字。

## 选项

| 方案 | 体积 | 问题 |
|---|---|---|
| A. App 打包完整思源黑体 / Noto Sans SC | 每个字重 8–17 MB | 安装包翻几倍；系统字体本来就是同一家族（Android 是 Noto CJK，iOS 是苹方），收益小 |
| B. App 打包常用字子集 | 2–4 MB | 书名、系列名是用户数据，任何子集都会缺字，缺字回退会导致同一行混用两种字体 |
| C. **App 用系统字体；测试用 UI 文案子集**（采纳） | App +0；仓库 +280 KB | 黄金图里的中文字形（Noto）与 iOS 真机（苹方）不完全一样——黄金图本来就只保证"布局 + 字形存在"，像素级字形一致不在它的职责内 |

## 决策

- **App 不打包中文字体**。`AppTypography` 只定义层级、字重、字距和等宽数字，字体家族交给系统
  （Android：Noto Sans CJK；iOS：苹方），中文与系统其他应用一致。
- **测试字体**：`apps/app/test/fonts/NotoSansSC-Regular-subset.ttf`
  - 来源：Noto Sans SC 2.004 可变字体（Adobe/Google，**SIL OFL 1.1**，许可全文
    `apps/app/test/fonts/LICENSE-NotoSansSC.txt`），固定为 `wght=400` 后子集化；
  - 字符集：`app_zh.arb` 全部文案 + 测试源码里出现的汉字 + ASCII + 常用中文标点（约 760 个字形，≈280 KB）；
  - 只在 `test/` 下，不在 `pubspec.yaml` 的 assets 里，不进安装包；
  - 粗体由引擎合成（只带一个字重，够黄金图用）。
- `golden_harness.dart` 加载它，并作为 `Roboto` 的 `fontFamilyFallback`；
  `pumpGoldenScreen(locale: Locale('zh'))` 出中文基线（首张：`connection@phone_light_zh`）。
- `test/golden/cjk_font_test.dart` 钉住"汉字走回退字体、宽度是全角"，
  防止字体文件丢失后中文基线悄悄退回占位方块。

## 后果

- **新增中文文案后要重新生成子集**，否则新字在黄金图里是方块。重新生成命令（需要 `fonttools`）：

  ```bash
  pip install fonttools
  python tool/cjk_font_subset.py            # 默认读 Windows 自带的 NotoSansSC-VF.ttf
  python tool/cjk_font_subset.py <源字体>   # 其他平台传 noto-cjk 的 NotoSansSC-VF.ttf
  ```

- 字体文件是二进制、约 280 KB，可接受；换 Flutter 版本不影响它。
- 若将来确有"App 内统一字形"的需求（例如 Android 某些 ROM 的系统中文字体很差），
  再单独评估方案 B，并另写 ADR。
