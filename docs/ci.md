# CI / GitHub Actions

> 面向"没用过 GitHub Actions"的读者：先说清概念与钱，再说本仓库怎么配、怎么看、怎么改。

---

## 1. 它是什么

**GitHub Actions = GitHub 自带的免费 CI/机器人服务。** 你把 YAML 放在仓库的 `.github/workflows/` 下，GitHub 在"你规定的时机"把一台**临时虚拟机**开起来，按步骤执行命令，跑完销毁。

| 概念 | 含义 | 本仓库对应 |
|---|---|---|
| workflow | 一个 YAML 文件 = 一条流水线 | `ci.yml` / `build-android.yml` / `build-ios.yml` |
| trigger (`on:`) | 什么时候跑 | push / pull_request / 打 tag / 手动 |
| job | 一台机器上的一组步骤 | `gate` / `apk` / `build` |
| runner | 实际执行的虚拟机 | `windows-latest` / `ubuntu-latest` / `macos-latest` |
| step | job 里的一步（跑命令或调用 action） | `flutter pub get`、`dart run tool/ci.dart check` |
| action (`uses:`) | 别人写好的可复用步骤 | `actions/checkout@v7`、`subosito/flutter-action@v2` |
| artifact | 跑完产出的文件，可下载 | APK、未签名 `.app.zip`、黄金图失败截图 |
| cache | 跨运行复用的目录，省下载时间 | Flutter SDK、Gradle 依赖 |
| secret | 加密变量，日志里自动打码 | 将来 TestFlight/Play 的签名密钥 |

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

## 3. 本仓库的三条流水线

| 文件 | 触发 | 机器 | 做什么 |
|---|---|---|---|
| `ci.yml` | push to main、PR、手动 | `windows-latest` | `dart run tool/ci.dart check`：格式 + 分析 + 分层规则 + 61 个测试 + 5 张黄金图 |
| `build-android.yml` | push to main（代码路径变化）、手动 | `ubuntu-latest` | `flutter build apk --release` → 上传 APK artifact |
| `build-ios.yml` | push / PR / `v*` tag / 手动 | `macos-latest` | `flutter build ios --release --no-codesign` → 上传 `.app.zip` |

**为什么门禁放在 Windows**：黄金图基线以 Windows 为唯一平台（`AGENTS.md` 的约定）。在 Linux/macOS 上跑会因字体光栅化差异导致 5 张基线全部失配，而且修不好——只能换基线平台。

**为什么 iOS 现在也跟 push**：仓库是 public，macOS runner 免费。三条流水线都跑，PR 能同时看到"Android 能编、iOS 能编"。
**如果转私有**：删掉 `build-ios.yml` 的 `pull_request` 与 `push` 触发，只留 `workflow_dispatch` 和 tag。

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

3. 推送成功后打开仓库页面的 **Actions** 标签，能看到三条 workflow 自动出现。

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
| `flutter pub get` 超时 | runner 访问 pub.dev 抖动 | 重跑；持续失败再考虑镜像（但要写进 AGENTS.md，否则本地/CI 不一致） |
| Gradle 下载超时 | 依赖没命中缓存 | 首次必慢；检查 `actions/cache` 的 key 是否因 `pubspec.lock` 变化频繁失效 |
| `Permission denied` / 工作流不出现 | 仓库 Actions 被禁用 | Settings → Actions → General → 允许 |
| macOS job 排队很久 | macOS runner 紧张 | 正常现象，别在 PR 上跑 iOS |

---

## 6. 后续要补的（按优先级）

1. **签名**：Android keystore + `key.properties` 走 secrets；iOS 用 App Store Connect API Key + `flutter build ipa`。
2. **契约测试**：job 里 `docker run gotson/komga`，跑真实服务器用例（M1）。
3. **分支保护**：Settings → Branches → 要求 `Gate` 通过才能合并（这也是"CI 当裁判"真正生效的地方）。
4. **成本优化**（私有仓库才有意义）：把纯 Dart 测试拆到 ubuntu job，Windows 只跑黄金图，可把单次门禁从 ~12 分钟压到 ~6 分钟。
