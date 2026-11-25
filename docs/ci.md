# CI / GitHub Actions

> 面向"没用过 GitHub Actions"的读者：先说清概念与钱，再说本仓库怎么配、怎么看、怎么改。

---

## 1. 它是什么

**GitHub Actions = GitHub 自带的免费 CI/机器人服务。** 你把 YAML 放在仓库的 `.github/workflows/` 下，GitHub 在"你规定的时机"把一台**临时虚拟机**开起来，按步骤执行命令，跑完销毁。

| 概念 | 含义 | 本仓库对应 |
|---|---|---|
| workflow | 一个 YAML 文件 = 一条流水线 | `ci.yml` / `build-android.yml` / `build-ios.yml` / `release.yml` |
| trigger (`on:`) | 什么时候跑 | push / pull_request / 打 tag / 手动 |
| job | 一台机器上的一组步骤 | `gate` / `apk` / `build` / `release-android` |
| runner | 实际执行的虚拟机 | `windows-latest` / `ubuntu-latest` / `macos-latest` |
| step | job 里的一步（跑命令或调用 action） | `flutter pub get`、`dart run tool/ci.dart check` |
| action (`uses:`) | 别人写好的可复用步骤 | `actions/checkout@v7`、`subosito/flutter-action@v2` |
| artifact | 跑完产出的文件，可下载 | APK、未签名 `.app.zip`、黄金图失败截图 |
| cache | 跨运行复用的目录，省下载时间 | Flutter SDK、Gradle 依赖 |
| secret | 加密变量，日志里自动打码 | Android 发布 keystore / 将来 iOS 签名密钥 |

**它不是**：不是服务器（不能常驻）、不是免费算力池（有额度和时长上限）、不适合做长时间任务（单 job 上限 6 小时）。

---

## 2. 免费吗？算一笔账

| 仓库 | 额度 |
|---|---|
| **公开仓库** | 标准 runner（Linux / Windows / macOS）**完全免费**，不计分钟 |
| 私有仓库（Free 计划） | **2,000 分钟/月**（个人账户下所有私有仓库共享），工件存储 500MB |
| 私有仓库（Pro / Team） | 3,000 / 10,000 分钟/月 |

**计费倍率**（私有仓库才计费）：

| Runner | 倍率 | 说明 |
|---|---|---|
| `ubuntu-latest` | 1× | 最便宜，适合测试/构建 |
| `windows-latest` | **2×** | 我们跑黄金图的门禁 |
| `macos-latest` | **10×** | 一次 10 分钟 iOS 构建 = 100 分钟额度 |

本仓库单次运行的账：

| 流水线 | 机器 | 实际耗时 | 折算额度 | 频率 |
|---|---|---|---|---|
| CI 门禁 | Windows | ~6 min | ~12 min（私有） | 每次 push / PR |
| Android APK | Ubuntu | ~8 min | ~8 min（私有） | main + 手动 |
| iOS 构建 | macOS | ~12 min | **~120 min（私有）** | push / PR / tag / 手动 |

> **本仓库当前是 public → 上表全部免费**，所以三条流水线都跟 push/PR 跑，额度不用管。
> 如果哪天转成私有，需要立刻把 `build-ios.yml` 的 `pull_request` 触发删掉（macOS 10× 计费，一次 PR 跑掉 120 分钟额度）。

结论：
- **仓库公开 → 全免费，随便跑。**
- **仓库私有 → 每月约 100 次门禁没问题；iOS 构建每月别超过 ~15 次**，所以私有化时 iOS 必须退回"仅手动/tag"。
- 计费从 job 开始执行算，排队时间不算；但不足 1 分钟按 1 分钟计，所以别把一个任务拆成 20 个 30 秒的 job。

> 建议：保持 public 仓库（Komga 客户端这类工具开源收益很大），CI 成本持续为 0。

---

## 3. 本仓库的四条流水线

| 文件 | 触发 | 机器 | 做什么 |
|---|---|---|---|
| `ci.yml` | push to main、PR、手动 | `windows-latest` | `dart run tool/ci.dart check`：格式 + 分析 + 分层规则 + 全部测试 + 黄金图比对 |
| `build-android.yml` | push to main（代码路径变化）、手动 | `ubuntu-latest` | `flutter pub get` → `dart run tool/ci.dart codegen` → `flutter build apk --release` → 上传 debug 签名 APK artifact |
| `build-ios.yml` | push / PR / `v*` tag / 手动 | `macos-latest` | `flutter pub get` → `dart run tool/ci.dart codegen` → `flutter build ios --release --no-codesign` → 上传 `.app.zip` |
| `release.yml` | push `v*` tag | `ubuntu-latest` | 校验 tag 与 `pubspec.yaml` 版本一致 → 还原正式 keystore → 构建分架构与通用 release APK → `apksigner` 验签 → 自动发布到 GitHub Releases（附 `SHA256SUMS.txt`） |

**为什么门禁放在 Windows**：黄金图基线以 Windows 为唯一平台（`AGENTS.md` 的约定）。在 Linux/macOS 上跑会因字体光栅化差异导致 5 张基线全部失配，而且修不好——只能换基线平台。

**为什么 iOS 现在也跟 push**：仓库是 public，macOS runner 免费。三条流水线都跑，PR 能同时看到"Android 能编、iOS 能编"。
**如果转私有**：删掉 `build-ios.yml` 的 `pull_request` 与 `push` 触发，只留 `workflow_dispatch` 和 tag。

> **日常不必等 CI**：本地 `dart run tool/ci.dart check` + 模拟器验证通过即可提交推送；
> CI 结果是异步反馈（红了再单独修），见 `AGENTS.md`「标准交付流程」。

**为什么两条构建流水线在 `flutter build` 前都要跑 `codegen`**：`*.g.dart`（drift）与
`app_localizations*.dart` 都在 `.gitignore` 里，而 CI 是全新 clone。`flutter pub get` 只会顺带生成 l10n
（`flutter.generate: true`），**不会**跑 `build_runner`。跳过这一步，`flutter build` 会在 AOT 编译阶段直接失败：

```
Error: Target of URI hasn't been generated: '.../progress_database.g.dart'
Error: The getter 'cachedResponses' isn't defined for the type 'HttpCacheDatabase'
```

门禁（`tool/ci.dart check`）内部会先 codegen，所以 Windows 门禁一直绿，两条构建流水线却从引入 drift 的
提交起一直红——这是 v1 收尾时补的坑。本地验证"全新 clone 能不能编"不要用工作区（生成物还在），用
`git worktree add --detach ..\ci-sim HEAD` 后只跑 `flutter pub get` + `flutter build`。

### 3.1 产物（artifact）怎么拿

两条构建流水线都会上传产物，**保留 14 天**（`retention-days: 14`），过期后该次运行的 Artifacts 区域为空：

| 产物名 | 内容 | 来源 |
|---|---|---|
| `komga-native-apk` | `app-release.apk`（debug 签名，仅验证构建链路） | `build-android.yml` |
| `komga-native-ios-unsigned` | `Runner.app.zip`（**未签名**，`--no-codesign`） | `build-ios.yml` |

> **release APK 的 Android 权限只来自 `apps/app/android/app/src/main/AndroidManifest.xml`**：
> `src/debug` / `src/profile` 里的 `INTERNET` 不会合并进 release。缺了它，真机装包后任何地址都提示
> "无法连接到 xxx"（系统直接拒绝 socket），而模拟器的 debug 包完全正常——2026-11-17 真机测试踩过。
> 源码由 `apps/app/test/platform/android_manifest_test.dart` 钉住；拿到 artifact 后也可用
> `aapt2 dump permissions app-release.apk` 复核。

网页：仓库 → **Actions** → 点某次运行 → 页面底部 **Artifacts** → 下载。

命令行：**artifacts 下载需要认证**（对匿名请求返回 `401`，public 仓库也一样），
所以需要一个 `repo` 权限的 token：

```powershell
$token = $env:GITHUB_TOKEN          # 或本地 PAT
$run = Invoke-RestMethod -Headers @{Authorization="Bearer $token"} `
  "https://api.github.com/repos/<user>/KomgaNative/actions/workflows/build-ios.yml/runs?per_page=1"
$art = Invoke-RestMethod -Headers @{Authorization="Bearer $token"} `
  "https://api.github.com/repos/<user>/KomgaNative/actions/runs/$($run.workflow_runs[0].id)/artifacts"
$id = $art.artifacts[0].id
curl.exe -L -H "Authorization: Bearer $token" `
  "https://api.github.com/repos/<user>/KomgaNative/actions/artifacts/$id/zip" -o ios.zip
```

> **未签名的 `.app.zip` 装不到 iPhone 上**。它只能证明"能编过"，或者用来检查包内容。
> 真机安装需要签名（Apple ID 免费 provisioning，7 天有效；或付费开发者账号），
> 要么在 Mac 上用 Xcode 重签，要么在 CI 里配好证书走 `flutter build ipa`（见 §8）。


---

## 4. 怎么接到你的 GitHub

### 4.1 首次：建仓并推送

1. 网页建一个空仓库（**不要**勾选 README/.gitignore，避免冲突）：<https://github.com/new>
2. 本地执行（把 `<你>` 换成你的 GitHub 用户名）：

```bash
git remote add origin https://github.com/<你>/KomgaNative.git
git push -u origin main
```

首次推送会要求认证：GitHub 已不支持密码，用 **Personal Access Token（classic，勾 `repo`）** 当密码，或改用 SSH：

```bash
git remote set-url origin git@github.com:<你>/KomgaNative.git
```

3. 推送成功后打开仓库页面的 **Actions** 标签，能看到四条 workflow 自动出现。

### 4.2 双机开发时

两台机器用同一个远端即可：

```bash
# 家里机器
git clone https://github.com/<你>/KomgaNative.git
cd KomgaNative
powershell -NoProfile -ExecutionPolicy Bypass -File tool\bootstrap.ps1 -CheckOnly
```

凭证建议用 Git Credential Manager（Git for Windows 自带）或 SSH key，避免每次输 token。

---

## 5. 怎么看一次运行

1. **Actions** → 左侧选 workflow → 点某次 run。
2. 左侧是 job，点进去是逐步日志（可展开每一步）。
3. 失败时先看**第一个红色步骤的最后 30 行**——90% 的问题都在那里。
4. 跑到一半失败也能看：`Upload golden failures` 这一步在失败时才执行，产物在 run 页面底部 **Artifacts**。
5. 重跑：右上 **Re-run jobs**（可只重跑失败的 job）。

**常见失败与判断**：

| 现象 | 大概率原因 | 处理 |
|---|---|---|
| `golden` 失配，diff 百分比很小 | 字体/平台/Flutter 版本不一致 | 确认 runner 是 windows-latest 且 Flutter 版本 = `.fvmrc`；必要时本地 `dart run tool/ci.dart golden` 重生成 |
| `golden` 失配，**本地却全绿**，diff 只有几个像素（通常是一个数字） | 测试读了系统时钟：基线在本地那天/那个时区烙的，CI 跑 UTC、或者已经隔天 | 把"今天"注入进页面（如 `InsightsScreen(now:)`），黄金图里传固定值。门禁的 `goldens` 步会拦住 `test/golden` 里的 `DateTime.now()` |
| `flutter pub get` 超时 | runner 访问 pub.dev 抖动 | 重跑；持续失败再考虑镜像（但要写进 AGENTS.md，否则本地/CI 不一致） |
| `Build APK` / `Build iOS` 报 `isn't defined`、`Target of URI hasn't been generated` | 全新 clone 没有 drift 生成物 | 确认该 workflow 在 build 前有 `dart run tool/ci.dart codegen`；本地用干净 worktree 复现 |
| iOS job 报 `not acquired by Runner of type hosted` | GitHub macOS 容量不足，不是代码问题 | 直接 Re-run failed jobs |
| Gradle 下载超时 | 依赖没命中缓存 | 首次必慢；检查 `actions/cache` 的 key 是否因 `pubspec.lock` 变化频繁失效 |
| `Permission denied` / 工作流不出现 | 仓库 Actions 被禁用 | Settings → Actions → General → 允许 |
| macOS job 排队很久 | macOS runner 紧张 | 正常现象，别在 PR 上跑 iOS |

---

## 6. 发版（GitHub Releases）

推 `v*` 标签会触发 `.github/workflows/release.yml`，自动构建**正式签名**的 Android APK（`arm64-v8a` / `armeabi-v7a` / `x86_64` / `universal` + `SHA256SUMS.txt`）并发布到仓库 Releases 页面。

### 6.1 一次性配置：GitHub Actions Secrets

在仓库 **Settings → Secrets and variables → Actions → New repository secret** 中添加以下 4 项：

| Secret 名称 | 说明 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | 正式 `.jks` 文件的 Base64 编码（Windows PowerShell：`[Convert]::ToBase64String([IO.File]::ReadAllBytes("yomu-release.jks"))`） |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore 密码（`storePassword`） |
| `ANDROID_KEY_ALIAS` | Key 别名（`keyAlias`） |
| `ANDROID_KEY_PASSWORD` | Key 密码（`keyPassword`） |

> `apps/app/android/app/build.gradle.kts` 仅在存在 `apps/app/android/key.properties` 时启用正式签名，本地开发与日常 CI 未配置时自动回退 debug 签名；`release.yml` 会在构建前校验 Secrets 并在打包后用 `apksigner` 验签，防止误发 debug 签名包。

### 6.2 发布步骤

1. 更新 `apps/app/pubspec.yaml` 的 `version: <semver>+<build>`（`semver` 须与 tag 去掉 `v` 后一致，`build` 须严格递增）。
2. 本地跑完门禁与模拟器验证后提交推送到 `main`：
   ```bash
   dart run tool/ci.dart check
   dart run tool/ci.dart install
   ```
3. 打标签并推送：
   ```bash
   git tag -a v0.1.0 -m "Release v0.1.0"
   git push origin v0.1.0
   ```
   - 稳定版（如 `v0.1.0`、`v1.0.0`）会自动标记为 **Latest**；
   - 预发布版（含 `-`，如 `v0.2.0-rc.1`、`v0.2.0-beta.1`）会自动标记为 **Pre-release**。

---

## 7. 后续要补的（按优先级）

1. **iOS 正式签名**：用 App Store Connect API Key + `flutter build ipa` 接 TestFlight / App Store。
2. **契约测试**：job 里 `docker run gotson/komga`，跑真实服务器用例（M1）。
3. **分支保护**：Settings → Branches → 要求 `Gate` 通过才能合并（这也是"CI 当裁判"真正生效的地方）。
4. **成本优化**（私有仓库才有意义）：把纯 Dart 测试拆到 ubuntu job，Windows 只跑黄金图，可把单次门禁从 ~12 分钟压到 ~6 分钟。
