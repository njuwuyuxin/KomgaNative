# KomgaNative

Komga 的跨平台客户端（iOS / Android / Android 墨水屏），阅读体验优先。

> 状态：**M0 骨架完成**（可运行的空壳 + 三套主题 + 黄金图闭环 + 纯逻辑包）。
> 数据层仍是示例数据，M1 接真实 Komga 服务器。

## 文档

| 文档 | 内容 |
|---|---|
| [docs/tech-selection.md](docs/tech-selection.md) | 技术选型：候选评分、技术栈、三大子系统设计、AI Agent 工程化、里程碑与风险 |
| [docs/environment-setup.md](docs/environment-setup.md) | 环境搭建与双机切换：免管理员安装、验收标准、踩坑表 |
| [docs/ci.md](docs/ci.md) | GitHub Actions：概念、免费额度与计费倍率、三条流水线、排障 |
| [AGENTS.md](AGENTS.md) | Agent 工作契约：命令、架构不变量、DoD、反模式 |

## CI

| 流水线 | 触发 | 机器 | 内容 |
|---|---|---|---|
| `ci.yml` | push / PR / 手动 | windows | 全量门禁（含黄金图） |
| `build-android.yml` | main / 手动 | ubuntu | release APK 产物 |
| `build-ios.yml` | push / PR / tag / 手动 | macos | `--no-codesign` 编译验证（public 仓库 macOS 免费） |

## 快速开始

```bash
# 1. 环境（Windows，用户级，无需管理员）
powershell -NoProfile -ExecutionPolicy Bypass -File tool\bootstrap.ps1 -CheckOnly   # 体检
powershell -NoProfile -ExecutionPolicy Bypass -File tool\bootstrap.ps1             # 安装

# 2. 依赖与校验
cd apps/app && flutter pub get && cd ../..
dart run tool/ci.dart check

# 3. 跑起来
cd apps/app && flutter run
```

## 结构

```
apps/app                       Flutter 应用（android / ios）
packages/komga_domain          领域模型（纯 Dart，零依赖）
packages/komga_reader_engine   阅读器几何：适配缩放、平移夹紧、双页/RTL 分组
packages/komga_sync_engine     进度 outbox + 多设备对账决策
packages/komga_api             Komga REST 传输层、错误模型、URL 构造
packages/komga_design_system   token、light/dark/eink 三主题、基础组件
packages/komga_platform        设备形态与墨水屏探测的抽象层
tool/ci.dart                   统一校验入口（check / fix / test / golden）
```

依赖方向由 `dart run tool/ci.dart check` 的 `layers` 步骤强制：
`app → (design_system, platform, api, engines, domain)`；`engines → domain`；`domain → 无`。

## 质量门禁

```bash
dart run tool/ci.dart check    # format + analyze + layers + 全部测试
dart run tool/ci.dart golden   # 重新生成黄金图（仅 Windows，与 CI 一致）
```

当前基线：**61 个测试**（纯 Dart 41 / Flutter 20），5 张黄金图覆盖
手机 light、平板 dark、手机 1.3 倍字号、墨水屏 settings、阅读器。

## 已知边界

- UI 文案暂为英文：i18n（ARB + 中文字体）在 M1 一起做，避免现在把 CJK 字体塞进黄金图。
- 未接服务器：登录/书架/阅读器数据都是 `apps/app/lib/src/data/sample_data.dart`。
- 无 Android 模拟器：用真机或 M1 时补装 system image。
