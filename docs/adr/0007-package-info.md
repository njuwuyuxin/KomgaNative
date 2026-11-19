# ADR 0007：用 `package_info_plus` 读版本号

- 状态：已接受
- 日期：2026-11-19
- 相关需求：FIX-09

## 背景

设置页"版本"一行是硬编码的 `0.1.0 (v1)`：`pubspec.yaml` 里改成 `0.2.0+7` 之后
界面仍然显示 0.1.0，用户据此判断"装的是不是新版"就会判断错；"关于"里的
开源许可页也用了同一个假版本号。

版本号的真值只有一处：**构建产物里的 `versionName`/`versionCode`**。
Dart 代码在编译期拿不到它，只能运行时从平台侧读。

## 决策

引入 `package_info_plus`，在设置页读取真实版本与构建号：

```dart
final info = await PackageInfo.fromPlatform();
'${info.version} (${info.buildNumber})'
```

- `package_info_plus` 是 Flutter 官方（fluttercommunity）维护、pana 评分满分的
  插件，只读构建信息，不联网、不要权限；
- 读失败（极端情况下平台通道不可用）时回退到 `pubspec.yaml` 的版本常量，
  界面上不能出现空字符串。

## 备选方案

1. **构建时生成 Dart 常量**（`--dart-define` 或 codegen）。要在 CI/flutter 命令里
   额外注入，本地 `flutter run` 忘了传就又不准了，且与 App Store 的版本号来源
   不一致。
2. **保持硬编码**。已经在误导用户，且每次发版都要记得改两处。

## 影响

- 新增一个插件依赖（纯读取，无平台代码改动）；
- 测试里覆盖 `PackageInfoPlatform.instance`，不用真的读构建信息；
- 设置页的版本行从常量变成 `FutureProvider`：还没读到/读不到时显示 pubspec 里的兜底版本，\n  不留空白，也不显示一个看起来很像真的假版本号。
