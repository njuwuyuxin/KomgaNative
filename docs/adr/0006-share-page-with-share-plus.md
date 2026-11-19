# ADR 0006：分享单页用 share_plus，而不是自己写原生通道

- 状态：采纳（2026-11-19）
- 相关：UI-P3-6、`apps/app/lib/src/data/page_share.dart`

## 背景

P3-6 要长按页缩略图"分享此页"（用户可以发到消息/笔记，或经系统面板"存储到文件"）。
平台能力是 Android 的 `ACTION_SEND` 与 iOS 的 `UIActivityViewController`。

## 决定

引入 **`share_plus` 13.3.1**，把页图字节写到 `getTemporaryDirectory()` 下的 PNG，
再用 `SharePlus.instance.share(ShareParams(files: [XFile(path)]))` 调系统分享面板。

测试通过 `ReaderScreen.onSharePage` 注入口（生产环境不传），不直接调用插件；
插件本身由真机走查确认。

## 理由

- **跨平台且成熟**：Android/iOS/macOS 都走系统分享；"保存到文件"由系统面板提供，
  不需要自己申请存储权限或写 FileProvider/UIDocumentPicker。
- **构建要求已满足**：插件要求 Flutter >=3.38.1、AGP >=8.12.1、Gradle >=8.13、
  Kotlin >=2.2.0；本仓库是 Flutter 3.50、AGP 9.3.1、Gradle 9.5、Kotlin 2.4.20。
- **iOS 不写未验证的原生代码**：仓库没有 macOS 环境；自己写 `UIActivityViewController`
  会违背"不写没跑过的 iOS 代码"的约定。插件由上游维护。

## 代价

- 多一个第三方依赖（连带 `cross_file`、`share_plus_platform_interface` 等）；
  需要 ADR，就是本文。
- 分享是"用户动作"的副作用，不能在 widget 测试里真正打开系统面板；测试只覆盖
  "长按 → 菜单 → 回调拿到页码"，插件调用靠模拟器/真机走查。
- 临时文件不主动删（面板可能仍在读）；系统按临时目录策略清理。
- Linux 不支持分享文件；本项目目标平台不含 Linux。

## 备选方案

- **自写 MethodChannel**：Android 要 FileProvider + Intent，iOS 要 UIActivityViewController；
  两端都要原生代码与真机验证，成本高于收益。
- **只保存到应用文档目录**：用户很难从文件管理器找到，且没有"发出去"的路径，不满足需求。
- **复制图片到剪贴板**：Flutter 没有内置的图片剪贴板，需要第三方/原生，且分享场景更常用。

## 验收

- `reader_screen_test` 覆盖长按缩略图 → 分享菜单 → `onSharePage` 收到正确页码。
- 模拟器 release 上长按缩略图 → 分享，系统面板能打开；选择"保存到文件"后图片可打开。
