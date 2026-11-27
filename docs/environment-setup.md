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
│  ├─ emulator\                # 模拟器（可选，已装：§11）
│  ├─ system-images\           # 模拟器系统镜像（可选，已装：§11）
│  ├─ extras\google\           # AEHD 驱动安装包（可选：§11）
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

> `bootstrap.ps1` 写 PATH 前会检查目录是否存在，**不存在就跳过并打印警告**。本机首次引导时 `emulator\` 还不存在，所以实际 PATH 里没有这一条；装完模拟器再重跑 `bootstrap.ps1` 才会补上。不补也不影响：`dart run tool/emulator.dart` 用绝对路径调用，不依赖 PATH（§11）。

---

## 6. 验收标准

**重开一个终端**（让用户级 PATH 生效），依次执行：

```powershell
flutter --version          # 应输出 Flutter 3.50.0 / Dart 3.14.0
java -version              # 应输出 17.0.x
adb version                # 应输出 Android Debug Bridge version ...
flutter doctor -v
dart run tool/emulator.dart --list   # 可选：装了模拟器才有意义（§11）
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
| 模拟器（可选，2026-11-17 补装） | emulator 37.2.13 + `system-images;android-36;google_apis;x86_64`（r07）+ AEHD 2.2.0；AVD `kn_api36`（pixel_7 / 4GB RAM / `-gpu host`），详见 §11 |
| 模拟器磁盘 | emulator 1.04GB + 系统镜像 4.27GB（`D:\DevTools` 合计 8.15→13.6GB）+ AVD 5.58GB（`%USERPROFILE%\.android\avd`，随快照/数据增长） |
| 未装 | Docker |

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

## 11. 模拟器（可选：本机预览 Android 效果）

> 只有要在 PC 上看 Android 效果时才需要。**不进仓库、不参与 CI**：SDK 包在 `D:\DevTools`，AVD 在 `%USERPROFILE%\.android\avd`，都是机器级产物。
> 日常启动统一走仓库里的 `dart run tool/emulator.dart`（§11.3）；本节只记录一次性安装与踩坑。

### 11.1 一次性安装（3 步，只有第 2 步要管理员）

| 步骤 | 命令 | 管理员 |
|---|---|---|
| 1. 装模拟器 + 镜像 + AEHD 安装包 | `sdkmanager "emulator" "system-images;android-36;google_apis;x86_64" "extras;google;Android_Emulator_Hypervisor_Driver"` | 否 |
| 2. 装 AEHD 驱动 | `D:\DevTools\android-sdk\extras\google\Android_Emulator_Hypervisor_Driver\silent_install.bat`（脚本自己弹 UAC） | **是**（一次） |
| 3. 验证 | `dart run tool/emulator.dart --list` → `AEHD (version 2.2) is installed and usable.`；`sc query aehd` → `RUNNING` | 否 |

不需要 Android Studio（cmdline-tools 够用）。镜像选 `google_apis` 而不是 `playstore`：体积小、可 `adb root`，本项目不依赖 GMS。
下载量约 5.3GB（emulator 1.04GB + 系统镜像 4.27GB），首次启动还会在 AVD 目录再写 5–6GB。

**为什么用 AEHD 而不是 WHPX**：WHPX 要启用 Hyper-V 平台并**重启**，且 Hyper-V 会连带影响 VirtualBox/VMware；AEHD 是内核驱动，装完即用、不重启。两者**不能同时用**——Hyper-V 开着时 AEHD 装不上也跑不起来（`-accel-check` 报冲突）。

### 11.2 硬件加速的前置条件

| 条件 | 本机 | 检查方式 |
|---|---|---|
| BIOS 里 CPU 虚拟化（SVM / VT-x）打开 | ✅ | 任务管理器 → 性能 → CPU →「虚拟化：已启用」 |
| 未启用 Hyper-V / WHPX | ✅ | `(Get-CimInstance Win32_OptionalFeature -Filter "Name='HypervisorPlatform'").InstallState` = `2`（未启用） |
| 内核隔离 / 内存完整性关闭 | ✅ | `Win32_DeviceGuard.VirtualizationBasedSecurityStatus` = `0` |

后两条任一不满足时，`sc start aehd` 会失败或 `-accel-check` 报错；先解决再装驱动。

### 11.3 启动与交互

```powershell
dart run tool/emulator.dart          # 首次自动建 AVD（kn_api36），等到开机完成并打印 serial
dart run tool/emulator.dart --run    # 启动 + flutter run（热重载 r / 热重启 R）
dart run tool/emulator.dart --list   # AVD 列表 + 加速状态
dart run tool/emulator.dart --stop   # 关机
```

脚本行为（`tool/emulator.dart`）：

- 用 `ANDROID_HOME` / `ANDROID_SDK_ROOT` 找 SDK，找不到退回 `D:\DevTools\android-sdk`；
- 同名 AVD 已在运行时直接复用（打印 serial 后退出），不会重复启动；`--run` 仍会接上 `flutter run`；
- 复用前会判断现有实例是不是 `--headless` 起的（查宿主进程命令行里的 `-no-window`）：是的话**先关掉再以窗口模式重启**，避免"脚本说在运行、任务栏却找不到窗口"；
- **绝对路径**调用 `emulator.exe` / `adb.exe`，不依赖 PATH；
- AVD 不存在时用 `avdmanager` 创建（`pixel_7` / API 36），随后 `-memory 4096 -gpu host -no-boot-anim` 启动；
- 默认带 `-feature -Vulkan`（原因见 §11.4 第一条），代价是不能用 guest Vulkan，本项目用不到；
- 轮询 `adb devices` + `sys.boot_completed` 直到开机（上限 300 秒；**60 秒内 adb 看不到设备就直接判失败**，不用干等）；
- 失败时打印 `%TEMP%\komganative-emulator.log` 尾部——注意模拟器输出接在管道上时会被缓冲，日志可能是空的，这时手动 `emulator -avd kn_api36 -verbose` 复现最快。

交互要点：

- 单击=点按、按住=长按、拖动=滑动、滚轮=滚动、`Ctrl`+拖动=双指缩放；键盘直接输入；工具栏有返回/主页/最近任务/旋转/音量/电源。
- 把 APK 拖进窗口即安装；等价命令 `adb install -r apps/app/build/app/outputs/flutter-apk/app-debug.apk`。
- `flutter run` 里 `r` 热重载、`R` 热重启、`s` 截图；DevTools 的 widget inspector 能在模拟器里点控件、看布局树。
- 模拟器里的 `10.0.2.2` 是宿主机回环：本地 Komga 填 `http://10.0.2.2:25600`；或 `adb reverse tcp:25600 tcp:25600` 后填 `127.0.0.1:25600`。
- **墨水屏形态看不到**：`EinkProbe` 的原生实现要到 M5，模拟器上恒为 `EinkInfo.unknown`，走普通主题；eink 主题只能看黄金图。平板/手机布局靠换 AVD 的屏幕分辨率，拖窗口不一定改变 Android 的 display size。

### 11.4 已知坑

| 现象 | 原因 | 处理 |
|---|---|---|
| 启动后 `adb devices` 一直 `offline`、窗口停在开机画面 | gfxstream 的 Vulkan 后端在部分 NVIDIA 驱动上会让 guest 卡死（本机 2026-11-17：`-gpu host` 10 分钟未开机，加 `-feature -Vulkan` 后 10–25 秒开机） | 脚本已默认加 `-feature -Vulkan`；手动启动时也要加，或改用 `--gpu swiftshader_indirect` |
| `ERROR: x86_64 emulation currently requires hardware acceleration` | AEHD / WHPX 未就绪 | 回 §11.1 |
| `silent_install.bat` 里 `sc start aehd` 失败 | Hyper-V 开着，或内核隔离开着 | 关掉后重试（§11.2） |
| `emulator` 命令找不到 | bootstrap 写 PATH 时该目录还不存在，被跳过 | 用 `dart run tool/emulator.dart`；或补 PATH 后重开终端 |
| 窗口黑屏 / 启动即崩 | 显卡驱动、远程桌面、多显卡 | `dart run tool/emulator.dart --gpu swiftshader_indirect` |
| 脚本提示"已在运行"，但任务栏里找不到模拟器窗口 | 这个实例是 `--headless`（`-no-window`）起的：进程活着、adb 能连、App 也在跑，就是没有窗口 | 重新执行 `dart run tool/emulator.dart`，脚本会自动关掉 headless 实例并重启为窗口模式；也可以 `--stop` 后手动重启。确认方式：`Get-CimInstance Win32_Process | ? Name -like 'qemu*' | % CommandLine` 里有没有 `-no-window` |
| 首次启动 0.5–3 分钟 | 冷启动 + 首次解压镜像 | 正常；之后走 quickboot 快照，异常时加 `--cold` |
| C 盘被占 | AVD 默认在 `%USERPROFILE%\.android\avd` | 设 `ANDROID_AVD_HOME` 指向别的盘，再重建 AVD |

### 11.5 与仓库的关系

- 模拟器安装产物（SDK 包、系统镜像、AVD、驱动）**一律不进 git**；仓库里只多 `tool/emulator.dart` 和本节文档。
- CI 不跑模拟器：`ci.yml` 跑测试与黄金图，`build-android.yml` 只出 APK。模拟器是纯人工预览手段，不能替代黄金图验收。

---

## 12. 本地 Komga 服务器（可选：联调与抓 fixture）

> 只有要对着真实服务器联调、或重新抓 fixture 时才需要；**不参与 CI**，单测与黄金图全部走假实现。
> 服务器是**原生 jar**（`java -jar`），不是 Docker（本机也没装 Docker）。

日常只用仓库里的 `dart run tool/komga.dart`：

```powershell
dart run tool/komga.dart start     # 启动，等到 HTTP 就绪（首次约 10–20 秒）
dart run tool/komga.dart status    # 进程 / 端口 / 日志位置
dart run tool/komga.dart stop      # 停止
```

脚本行为（`tool/komga.dart`）：

- 站点目录按 `--home` → `$KOMGA_HOME` → 仓库 `.komga/` → `D:\DevTools\_verify\komga`（历史实例）的顺序取；
- Java 必须是 17+：按 `--java` → `$KOMGA_JAVA` → `$JAVA_HOME` → `D:\DevTools\jdk-17` → PATH 依次探测，**PATH 上的 java 是 11 时自动跳过**；
- 端口：`--port` → `$KOMGA_PORT` → 25600；
- 用 `ProcessStartMode.detached` 启动，脚本退出后服务器继续跑；stdout 不接管，**日志在 `<站点目录>\config\logs\komga.log`**；
- 就绪判定是 `GET /api/v1/libraries` 返回 401/200；10 秒后进程已退出会提前判失败，不干等 120 秒；
- 运行状态写在 `<站点目录>\.komga-run.json`（pid/port/jar/startedAt），`stop` 先按它精确杀；文件丢了就按 `komga-*.jar` 扫 java 进程，再杀不掉才报错；
- Windows 上 stop 是 `TerminateProcess`（没有 Ctrl+C 那套优雅关闭），SQLite 的 `-wal` 下次启动会自己恢复，不用手工清理。

站点目录里有什么：

| 路径 | 内容 | 进 git？ |
|---|---|---|
| `komga-<ver>.jar` | 服务端，127 MB | 否 |
| `config\` | database / sessions / tasks 三套 SQLite + lucene | 否 |
| `library\` | 漫画文件（本机是 `Verify Series #1.cbz`） | 否 |
| `pages\` | 页图缓存（跟着**启动时的工作目录**走，脚本已固定为该目录） | 否 |
| `.komga-run.json` | 脚本写的运行状态 | 否（`.gitignore` 里是 `.komga/`） |

客户端怎么连：

- 宿主机 / iOS 模拟器：`http://127.0.0.1:25600`
- Android 模拟器：`http://10.0.2.2:25600`；或 `adb reverse tcp:25600 tcp:25600` 后用 `127.0.0.1:25600`
- 本机实例的账号是首次 `POST /api/v1/claim` 建的：`komga@example.com` / `komga`（弱口令，仅本机验证用）

从零搭一个新实例（换机器时）：

```powershell
# 1) 下 jar（单文件，JDK 17 即可跑，不需要 Docker）
$dst = 'D:\DevTools\_verify\komga'
New-Item -ItemType Directory -Force $dst | Out-Null
Invoke-WebRequest 'https://github.com/gotson/komga/releases/download/1.30.1/komga-1.30.1.jar' -OutFile "$dst\komga-1.30.1.jar"

# 2) 起服务（脚本自己建 config\；第一次没有账号，必须 claim）
dart run tool/komga.dart start --home $dst
Invoke-WebRequest -Uri 'http://127.0.0.1:25600/api/v1/claim' -Method POST -UseBasicParsing `
  -Headers @{ 'X-Komga-Email' = 'komga@example.com'; 'X-Komga-Password' = 'komga' }

# 3) 建库 + 扫描：见 docs/komga-api-verification.md §2
```

---

## 13. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-17 | 初版：用户级安装、免管理员；Flutter 改用官方 zip + sha256（不用 `fvm install`）；黄金图基线平台定为 Windows（与开发机一致） |
| 2026-11-17 | 本机实装完成并回填实测结论（§10）；补充 PS 5.1 兼容性、执行策略、长路径三类踩坑 |
| 2026-11-17 | 补装模拟器：emulator 37.2.13 + `system-images;android-36;google_apis;x86_64` + AEHD 2.2.0；新增 §11 与 `tool/emulator.dart`；修正 PATH 说明（bootstrap 会跳过不存在的目录，故首次引导后 PATH 里没有 `emulator\`） |
| 2026-11-17 | 新增 §12 与 `tool/komga.dart`：本地 Komga 是原生 jar（不是 Docker），start/stop/status 不再手输 `java -jar`；`.gitignore` 忽略仓库内默认站点目录 `.komga/` |
