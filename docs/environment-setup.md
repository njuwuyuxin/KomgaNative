# 开发环境搭建与双机切换（Windows）

> 目标：任何一台 Windows 10/11 开发机，**不需要管理员权限**，在 45–75 分钟内变成可开发 / 可构建 Android 的 KomgaNative 环境；两台机器（公司 + 家）行为一致。
> 配套脚本：[tool/bootstrap.ps1](../tool/bootstrap.ps1)（幂等，可反复执行）。

---

## 1. 设计原则

| 原则 | 做法 | 原因 |
|---|---|---|
| **不用管理员** | 全部装到 `D:\DevTools`，环境变量写「用户级」 | 公司电脑通常没有管理员权限；UAC 会打断 Agent 自动化 |
| **不碰系统** | 不改注册表、不改系统 PATH | 可回滚、不污染机器；卸载 = 删目录 + 删用户变量 |
| **可复现** | JDK / Flutter 走官方源 + sha256 校验，版本写在脚本参数里 | 两台机器版本一致；Flutter 版本不一致会让黄金图基线全红 |
| **幂等** | 每个组件先探测再安装，已存在则跳过 | 换机器、修环境、跑第二遍都安全 |
| **iOS 不上本机** | iOS 只在 GitHub Actions 的 macOS runner 构建 | 两台机器都不需要 Xcode / 证书 / 签名 |
| **只有 1 个 `.ps1`** | 引导脚本用 PowerShell，其余工具链一律 Dart（`tool/ci.dart`） | 企业执行策略（本机 `MachinePolicy=RemoteSigned` + 工作区 ACL 被 DLP/沙箱加固）会把仓库里的 `.ps1` 判定为不可信而拒绝执行；Dart 脚本不受该策略影响 |

**为什么不用 `fvm install` 装 Flutter**：FVM 的安装路径依赖 `git clone`（本机 git 未必在 PATH 上），而官方 stable 包提供 `sha256`。本项目只需要**一个固定版本**，所以 `bootstrap.ps1` 直接装「校验和锁定的官方 zip」到 `D:\DevTools\flutter\3.50.0`。需要多版本切换时再装 FVM（它仍可独立使用，脚本也支持指定 `-FlutterVersion`）。

---

## 2. 前置条件

- Windows 10 1803+ / Windows 11（需要自带 `curl.exe`、`tar.exe`）
- PowerShell 5.1+（推荐 `pwsh` 7）
- 磁盘：`D:`（或任意非系统盘）≥ 20GB 可用
- 网络：能访问 `dl.google.com`、`storage.googleapis.com`、`github.com`、`pub.dev`
- 可选：Git for Windows（没有的话脚本会警告并跳过 git 配置）

---

## 3. 一键引导

```powershell
# 体检（不下载任何东西，随时可跑）
powershell -NoProfile -ExecutionPolicy Bypass -File tool\bootstrap.ps1 -CheckOnly

# 完整安装（默认 D:\DevTools，Flutter 3.50.0，JDK 17）
powershell -NoProfile -ExecutionPolicy Bypass -File tool\bootstrap.ps1

# 换盘 / 换 Flutter 版本
powershell -NoProfile -ExecutionPolicy Bypass -File tool\bootstrap.ps1 -InstallRoot E:\Dev -FlutterVersion 3.50.0

# 已有 JDK，只补 Android + Flutter
powershell -NoProfile -ExecutionPolicy Bypass -File tool\bootstrap.ps1 -SkipJdk

# 强制重装某个组件
powershell -NoProfile -ExecutionPolicy Bypass -File tool\bootstrap.ps1 -Force -SkipJdk -SkipAndroid
```

> **两种 Shell 的兼容性**：脚本同时兼容 Windows PowerShell 5.1（系统自带）和 PowerShell 7（`pwsh`，可选安装）。本机只有 5.1，所以上面统一用 `powershell`。脚本文件必须是 **UTF-8 with BOM**，否则 5.1 会按 GBK 解析中文导致语法错误。
>
> **如果报 `... is not digitally signed`（而策略明明是 RemoteSigned）**：说明工作区目录被公司 DLP/沙箱打了标记，PowerShell 把它当不可信来源。把脚本复制到非受管控目录再跑即可：
> ```powershell
> Copy-Item tool\bootstrap.ps1 D:\DevTools\bootstrap.ps1 -Force
> powershell -NoProfile -ExecutionPolicy Bypass -File D:\DevTools\bootstrap.ps1
> ```

脚本会依次做：预检 → git 配置 → JDK 17 → Android cmdline-tools + 许可 + platform-tools → Flutter → 用户环境变量 → 验收。

**耗时参考**（100Mbps 家宽 / 公司网）：

| 阶段 | 下载量 | 时间 |
|---|---|---|
| JDK 17（Temurin zip） | ~190MB | 2–4min |
| Android cmdline-tools | ~150MB | 2–4min |
| Flutter SDK zip | ~1.1GB | 8–20min |
| 解压 + 配置 | — | 3–5min |
| **合计** | ~1.5GB | **15–35min** |

首次 `flutter build apk` 还会再拉 Gradle 依赖 / Android platform（1–3GB），那属于构建而非环境搭建，建议第一次构建挑网络好的时候做。

---

## 4. 必须人工完成的两件事

这两项需要管理员权限，脚本只会**检测并提示**，不会自动改：

### 4.1 开启开发者模式（Flutter 必需）

```
设置 → 系统 → 开发者选项 → 开发人员模式 → 开
```

或者以管理员身份执行一次：

```powershell
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' `
  -Name AllowDevelopmentWithoutDevLicense -Value 1 -PropertyType DWord -Force
```

**不开会怎样**：依赖符号链接的插件/工具会报
`Building with plugins requires symlink support. Please enable Developer Mode in your system settings.`
实测（Flutter 3.50 + `path_provider`）：`flutter pub get` 与 `flutter build apk --debug` 都能通过，但该能力缺失是官方要求的前置条件，遇到报错时不要怀疑是代码问题。

### 4.2 开启系统长路径

以管理员身份执行：

```powershell
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' `
  -Name LongPathsEnabled -Value 1 -PropertyType DWord -Force
```

**不开会怎样**：Gradle / pub 缓存里深层路径会触发 `The specified path, file name, or both are too long.`（尤其是 Android 构建产物）。

---

## 5. 目录布局

```
D:\DevTools\
├─ _downloads\                 # 安装包缓存（可随时删除，重跑会重新下）
├─ jdk-17\                     # Temurin JDK 17（JAVA_HOME）
├─ android-sdk\
│  ├─ cmdline-tools\latest\    # sdkmanager / avdmanager
│  ├─ platform-tools\          # adb / fastboot
│  ├─ platforms\               # android-35 / android-36（Gradle 也可按需补）
│  ├─ build-tools\
│  ├─ emulator\                # 模拟器（可选）
│  └─ licenses\                # 许可（由 sdkmanager 写入）
├─ flutter\
│  └─ 3.50.0\                  # Flutter SDK（PATH 指向 bin）
└─ fvm\fvm.exe                 # 可选：多版本管理
```

环境变量（全部是**用户级**，卸载时只需删除它们）：

| 变量 | 值 |
|---|---|
| `JAVA_HOME` | `D:\DevTools\jdk-17` |
| `ANDROID_HOME` / `ANDROID_SDK_ROOT` | `D:\DevTools\android-sdk` |
| `Path`（追加） | `...\jdk-17\bin`、`...\android-sdk\platform-tools`、`...\android-sdk\cmdline-tools\latest\bin`、`...\android-sdk\emulator`、`...\flutter\3.50.0\bin`、`C:\Program Files\Git\cmd` |

---

## 6. 验收标准

**重开一个终端**（让用户级 PATH 生效），依次执行：

```powershell
flutter --version          # 应输出 Flutter 3.50.0 / Dart 3.14.0
java -version              # 应输出 17.0.x
adb version                # 应输出 Android Debug Bridge version ...
flutter doctor -v
```

`flutter doctor` 的健康状态（本项目只需要这几项打勾）：

```
[√] Flutter (Channel stable, 3.50.0, ...)
[√] Windows Version
[√] Android toolchain - develop for Android devices (Android SDK version 3x)
[!] Android Studio (not installed)          ← 忽略，我们用 cmdline-tools
[!] Visual Studio - develop Windows apps    ← 忽略，本项目不做 Windows 桌面端
[√] Connected device                         ← 插上真机/启动模拟器后才有
```

**健康**的标准：没有 `✗`，只有「可忽略」的 Android Studio / Visual Studio 警告。

---

## 7. 双机切换流程

### 7.1 新机器（45–75 分钟）

1. 装 Git for Windows（如未装）
2. 管理员执行 §4 的两条命令（一次性）
3. `git clone <repo>` + `cd` 进仓库
4. `pwsh -File tool\bootstrap.ps1`
5. 重开终端 → `flutter doctor -v`
6. `dart run tool/ci.dart check`（CI 全绿后再开始写业务）

可选加速：把旧机器的 `%LOCALAPPDATA%\Pub\Cache`、`%USERPROFILE%\.gradle\caches` 用移动硬盘拷过去，能省 20–30 分钟（不拷也能跑）。

### 7.2 离开一台机器前（硬规则）

```powershell
git add -A
git commit -m "wip: <一句话说明>"
git push origin HEAD:refs/heads/wip/<你的名字>
```

**原因**：AI Agent 的会话上下文和未提交改动只存在于那台机器；跨机 `git stash` 是不可靠的，WIP 分支才是可靠载体。

### 7.3 绝对不能同步的东西

| 项 | 原因 |
|---|---|
| `build/`、`.dart_tool/`、`*.iml` | 机器相关，重建即可 |
| Android 签名 keystore + 密码 | 泄漏 = 任何人可发布你的包；放密码管理器附件 |
| `key.properties`、`.env` | 同上 |
| 本地 SQLite 数据库 | 测试产物，跨机带过去只会造成困惑 |
| `test/goldens/` 里的基线 | **要进 git**，但只由基线平台（Windows）生成 |

---

## 8. 常见问题

| 症状 | 原因 | 处理 |
|---|---|---|
| `Building with plugins requires symlink support` | 开发者模式没开 | §4.1 |
| `The specified path ... too long` | 长路径没开 | §4.2 |
| `flutter doctor` 报 Android toolchain `✗`，提示 licenses | 许可未接受 | `flutter doctor --android-licenses` 全 y |
| `flutter doctor` 找不到 Android SDK | `ANDROID_HOME` 未生效（旧终端） | 重开终端；或 `flutter config --android-sdk D:\DevTools\android-sdk` |
| `Unsupported class file major version 65` | Gradle 用到了 JDK 21+ | 确认 `JAVA_HOME` 指向 JDK 17；必要时在 `gradle.properties` 写 `org.gradle.java.home` |
| Gradle 依赖下载超时 | 国内网络 | 用镜像（见下） |
| 构建极慢 / 杀软扫描 | Defender 实时扫描 | 排除 `D:\DevTools`、项目 `build\`、`.dart_tool`、`.gradle` |
| `sdkmanager` 提示某 `platforms;android-3x` 找不到 | 该版本号不存在 | 忽略；AGP 会在首次构建时自动下载匹配版本 |
| 重开终端后 `flutter` 仍不可用 | 用户 PATH 未刷新 | 注销重登，或 `refreshenv`（choco 提供） |
| 真机装 release APK 后连任何服务器都提示"无法连接"，同机浏览器正常 | `INTERNET` 权限只在 `src/debug` / `src/profile` 的 manifest 里，release 不合并 | 权限必须写进 `apps/app/android/app/src/main/AndroidManifest.xml`；已有 `test/platform/android_manifest_test.dart` 钉住，拿到 APK 可用 `aapt2 dump permissions app-release.apk` 复核 |

**Gradle 镜像**（可选，写进 `%USERPROFILE%\.gradle\init.gradle`）：

```groovy
allprojects {
    repositories {
        maven { url 'https://maven.aliyun.com/repository/google' }
        maven { url 'https://maven.aliyun.com/repository/public' }
        google(); mavenCentral()
    }
}
```

**Flutter/pub 镜像**（可选，用户环境变量）：

```
PUB_HOSTED_URL=https://pub.flutter-io.cn
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

> 注意：镜像会引入“版本滞后/不可用”的新问题。只在直连确实超时时启用，并在 `AGENTS.md` 里记录当前是否启用，否则 Agent 会误判“依赖不存在”。

---

## 9. 升级与卸载

**升级 Flutter**：改脚本参数版本号重跑（会装到新目录，旧目录留着可回滚）：
```powershell
pwsh -File tool\bootstrap.ps1 -FlutterVersion 3.51.0
```
同时更新仓库 `.fvmrc` 与 CI 镜像，并重新生成黄金图基线（**必须在同一平台**）。

**卸载**：

```powershell
# 1. 删除目录
Remove-Item D:\DevTools -Recurse -Force
# 2. 删除用户环境变量（当前用户）
'JAVA_HOME','ANDROID_HOME','ANDROID_SDK_ROOT' | ForEach-Object {
    [Environment]::SetEnvironmentVariable($_, $null, 'User')
}
# 3. 从用户 PATH 中手动移除 D:\DevTools\* 条目（系统属性 → 环境变量）
```

---

## 10. 本机落地记录（2026-11-17，Windows 11 25H2 / 非管理员）

真实安装结果，可作为第二台机器的对照基线。

| 组件 | 结果 |
|---|---|
| Flutter | 3.50.0 stable / Dart 3.14.0 / DevTools 2.61.0 → `D:\DevTools\flutter\3.50.0`（sha256 校验通过） |
| JDK | Temurin 17.0.21+9 → `D:\DevTools\jdk-17`（sha256 校验通过） |
| Android | cmdline-tools 21.0、platform-tools 37.0.1、platforms 35/36、build-tools 35/36.0.0 |
| `flutter doctor -v` | **No issues found!**（Android toolchain + 许可全绿） |
| 环境变量 | `JAVA_HOME` / `ANDROID_HOME` / `ANDROID_SDK_ROOT` + 用户 PATH 5 条 |
| 磁盘占用 | `D:\DevTools` 8.15GB（其中 `_downloads` 2.06GB 可删）+ `.gradle` 缓存 3.5GB |
| 耗时 | 下载约 25 分钟（约 1.5GB，实测 1.3MB/s）；安装配置约 10 分钟 |
| 首次 APK 构建 | 636 秒（冷缓存），Gradle 自动补装 NDK r28c + CMake 3.22.1，产出 153MB debug APK |
| 未装 | Android 模拟器与系统镜像（可选，约 1.5GB）、Docker |

### 10.1 实测结论（覆盖了文档里的两个"想当然"）

| 结论 | 说明 |
|---|---|
| `flutter pub get` 加插件**不需要**开发者模式 | 已用 `path_provider` 冒烟验证 |
| `flutter build apk --debug` **不需要**开发者模式也能成功 | Flutter 3.50 下实测通过；但本机 `New-Item -ItemType SymbolicLink` 确实失败，个别插件/工具仍可能用到，**仍建议开启** |
| 不需要手动装 NDK | 首次构建由 AGP 自动补装 NDK + CMake（约 2.5GB），这也是首次构建慢的主因 |
| 长路径问题会真的发生 | 构建产物 `build\jni\.transforms\...` 超过 260 字符，导致**连删除都失败**，必须用 `\\?\` 前缀或 robocopy 清理；这正是要开 `LongPathsEnabled` 的原因 |

### 10.2 踩坑记录（第二台机器可能复现）

| 现象 | 原因 | 处理 |
|---|---|---|
| `.ps1` 报 `... is not digitally signed`（而策略是 RemoteSigned） | 工作区目录被 DLP/沙箱加固（`icacls` 显示 `Everyone:(CI)(DENY)(DC)`），PowerShell 判为不可信来源 | 把脚本复制到 `D:\DevTools` 再执行（脚本本身无需修改） |
| 中文乱码 / `Unexpected token` / 引号错位 | 脚本存成 UTF-8 **无 BOM**，PS 5.1 按 GBK 解析 | 保存为 **UTF-8 with BOM**；本仓库脚本已带 BOM，编辑时注意别被剥掉 |
| 脚本在 `java -version` 处直接退出 | PS 5.1 会把外部程序的 stderr 包装成 ErrorRecord，`ErrorActionPreference=Stop` 下成为致命错误 | 外部命令统一走 `Invoke-Native` 包装（脚本已内置） |
| `curl -C -` 续传卡住、文件一直 0 字节 | 对"已存在但为 0 字节"的文件续传行为异常 | 不要对不完整文件用 `-C -`；直接重新下载 |
| `sdkmanager --licenses` 无人值守失败 | PS 5.1 把字符串管道喂给 `.bat` 的 stdin 不可靠 | `cmd /c "...sdkmanager.bat --licenses < yes.txt"` |
| `flutter`/`adb` 命令找不到 | 用户级 PATH 写入后，已打开的终端不会刷新 | 重开终端；或用 `[Environment]::GetEnvironmentVariable('Path','User')` 临时拼接 |
| 构建目录删不掉（`The directory is not empty`） | 路径超 260 字符 | `Remove-Item -LiteralPath "\\?\D:\...\_smoke" -Recurse -Force` 或 `robocopy 空目录 目标 /MIR` |

> `D:\DevTools\_downloads` 里是 JDK / Flutter / cmdline-tools 的原始压缩包（2GB）。保留它可以让重装/换机免下载，但也可以随时删除。

---

## 11. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-17 | 初版：用户级安装、免管理员；Flutter 改用官方 zip + sha256（不用 `fvm install`）；黄金图基线平台定为 Windows（与开发机一致） |
| 2026-11-17 | 本机实装完成并回填实测结论（§10）；补充 PS 5.1 兼容性、执行策略、长路径三类踩坑 |
