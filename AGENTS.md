# KomgaNative — Agent 工作契约

> 这份文件是给 AI Agent 看的操作手册。改代码前先读它，不要靠猜。

## 项目是什么

Komga（自建漫画服务器）的跨平台原生客户端：iOS / Android / Android 墨水屏，阅读体验优先。
技术选型与理由见 `docs/tech-selection.md`，环境搭建见 `docs/environment-setup.md`。

## 命令（唯一入口）

```bash
dart run tool/ci.dart check      # 全量门禁：格式 + 分析 + 分层 + 全部测试
dart run tool/ci.dart fix        # 自动格式化 + dart fix
dart run tool/ci.dart test       # 只跑测试
dart run tool/ci.dart golden     # 重新生成黄金图基线（Windows）
```

单包测试（更快，改纯逻辑时优先）：

```bash
dart test packages/komga_reader_engine
dart test packages/komga_sync_engine
flutter test apps/app
```

## 仓库结构

```
apps/app                      Flutter 应用（唯一可执行目标：android, ios）
packages/komga_domain         纯 Dart：领域模型（零依赖）
packages/komga_reader_engine  纯 Dart：分页/双页/缩放几何计算
packages/komga_sync_engine    纯 Dart：进度 outbox + 多设备对账
packages/komga_api            Komga REST 传输层、错误模型、URL 构造
packages/komga_design_system  设计 token、三套主题、基础组件
packages/komga_platform       平台能力抽象（设备形态、墨水屏探测）
tool/ci.dart                  统一校验入口
docs/                         选型、环境、spec、ADR
```

## 架构不变量（违反即失败，`ci.dart layers` 会拦）

1. `komga_domain` / `komga_reader_engine` / `komga_sync_engine` **不得** import flutter / dio / drift / go_router。
2. `apps/app/lib/src/screens/**` 与 `widgets/**` **不得** import `package:komga_api`，只能经 Repository。
3. Widget 里不做网络 I/O，不 `await` 请求；只读 provider 状态 + 派发 intent。
4. 错误统一用 `KomgaError`（`packages/komga_api/lib/src/errors.dart`）或领域内的密封类型，UI 只 `switch`，不允许裸 `catch`。
5. 设计数值只能来自 `design_system` 的 token（`AppSpacing` / `AppRadii` / `AppDurations`），禁止魔法数字。
6. 断点判断只在 `WindowSizeClass`（一次性），页面内部不要自己判断"是不是平板"。

## 完成定义（DoD）

- [ ] 新增/修改的纯逻辑有单测；边界值（0、越界、未知、RTL、宽页）覆盖到
- [ ] 新增 UI 有黄金图（`apps/app/test/golden/`），并且**用 `read_image` 自查过**
- [ ] 涉及 API 的变更同步更新 `test/fixtures/`（M1 起）
- [ ] `dart run tool/ci.dart check` 全绿
- [ ] 相关 `docs/` 段落已更新

## 黄金图约定

- 基线平台：**Windows**（与 CI 的 `windows-latest` 一致）。不要在 Linux/macOS 上 `--update-goldens`，否则整套基线作废。
- 命名：`<页面>@<形态>_<主题>[_text<缩放>].png`，例如 `library@tablet_dark.png`。
- 新增页面必须同时补齐：手机 light、平板 dark、墨水屏 eink 三张（除非该页面在墨水屏不可达）。

## 反模式

- 不写 `dynamic`，不 `catch (_)`，不 `print`（用 `debugPrint` 或日志抽象）。
- 不为"以后可能用到"提前抽象：抽象只在出现**第三个**调用点时引入。
- 不新增第三方依赖；确需新增，先在 `docs/adr/` 写清楚理由。
- 单文件超过 350 行、单类超过 300 行 → 先拆再写。
- 不要为了让测试通过而改断言；基线变更必须能说出"为什么这次渲染变了"。

## CI

三条 workflow 在 `.github/workflows/`，说明见 `docs/ci.md`：

- `ci.yml`（Windows）：每次 push/PR 跑全量门禁，**本地绿不算绿，CI 绿才算**；
- `build-android.yml`（Ubuntu）：main 分支 / 手动，产出 release APK；
- `build-ios.yml`（macOS）：push / PR / tag / 手动，编译验证（public 仓库 macOS 免费；转私有需去掉 push/PR 触发）。

改 workflow 后请同步更新 `docs/ci.md` 的流水线表。

## 当前阶段

M0（骨架）：可运行的外壳 + 三套主题 + 黄金图闭环 + 纯逻辑包。
数据层还是示例数据（`apps/app/lib/src/data/sample_data.dart`），M1 接真实 Komga。
