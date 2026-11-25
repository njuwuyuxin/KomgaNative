<div align="center">

# Yomu

**专为 [Komga](https://komga.org) 打造的跨平台原生漫画阅读客户端**

阅读体验优先 · 适配 Android / iOS / Android 墨水屏

**简体中文** | [English](README.en.md)

[![CI](https://github.com/njuwuyuxin/Yomu/actions/workflows/ci.yml/badge.svg)](https://github.com/njuwuyuxin/Yomu/actions/workflows/ci.yml)
[![Android Build](https://github.com/njuwuyuxin/Yomu/actions/workflows/build-android.yml/badge.svg)](https://github.com/njuwuyuxin/Yomu/actions/workflows/build-android.yml)
[![iOS Build](https://github.com/njuwuyuxin/Yomu/actions/workflows/build-ios.yml/badge.svg)](https://github.com/njuwuyuxin/Yomu/actions/workflows/build-ios.yml)
![Flutter](https://img.shields.io/badge/Flutter-3.50.0-02569B?logo=flutter&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20E--Ink-2E7D32)

</div>

---

## 简介

**Yomu** 是面向自建 [Komga](https://komga.org) 漫画服务器的跨平台原生客户端（基于 Flutter），专注于流畅的漫画阅读体验、可靠的离线与多设备进度同步，以及针对手机、平板与电子墨水屏的形态适配。

## 核心特性

### 沉浸式漫画阅读器
- **三种阅读模式**：支持**单页**、**双页跨页**（自动处理封面单页与宽页跨图，支持按书手动微调双页分组）与**纵向连续（条漫）**，默认自动跟随系列阅读方向与设备横竖屏。
- **翻页与画面控制**：内置着色器真实卷页、平移、淡入与无动画瞬切；支持适应屏幕/填满屏幕/适应宽度/适应高度、自动去白边、双指/双击缩放与锁定缩放、动态/沉浸式页边取色背景、应用内亮度调节、屏幕常亮及条漫自动滚动。
- **多样化操控与工具**：支持五种点击区预设与方向反转、Android 音量键翻页、键盘/蓝牙翻页器、顶栏 `AA` 快捷设置、按系列独立记住设置、可复用的阅读预设、系列目录跳转、缩略图滑条、无痕阅读、单页分享以及一键保存原图（双页自动左右拼接保存）。

### 墨水屏与多形态适配
- **电子墨水屏专项优化**：提供零动画、零阴影、纯黑白高对比度主题与白底黑字阅读画布；Android 端支持自动识别常见墨水屏设备（Boox / Meebook / Boyue / Hisense 等），亦可随时手动切换。
- **手机与平板自适应**：平板宽屏自动启用书架双栏（书库侧栏 + 书架网格）与系列详情双栏，支持独立的平板默认单/双页排版设置；Android 端主动申请屏幕最高刷新率。
- **无障碍与双语**：内置完整读屏语义与动态字体缩放适配，支持**简体中文**与 **English**（可跟随系统或手动切换）。

### 书架、收藏与全局搜索
- **正在读首页**：聚合继续阅读、最近阅读记录、最近添加与按书库货架，打开应用即可续读。
- **书架与系列管理**：支持网格/列表切换、封面尺寸调节、排序与阅读状态/书库筛选、保存常用筛选组合、系列置顶、未读角标，以及书架/系列内多选批量标记已读/未读与批量加入收藏集。
- **收藏集与阅读列表**：支持封面拼贴浏览、搜索与排序，支持直接新建、重命名、删除收藏集及管理其中系列。
- **全局搜索**：跨系列与书籍检索，提供搜索历史以及阅读状态/标签筛选。

### 离线缓存、整本下载与进度同步
- **本地优先进度同步**：翻页进度优先写入本地数据库并自动在联网、回前台或冷启动时补交，基于服务端时间戳完成多设备对账，断网阅读不丢进度。
- **智能离线缓存**：自动缓存浏览过的书架、详情、封面与页图（图片 256 MB LRU 淘汰，与用户数据分库存储），断网时无缝回退并展示离线状态提示。
- **整本与批量下载**：支持单本、整系列或前 N 本未读批量下载，具备持久化下载队列、暂停/继续/重试、仅 Wi-Fi 下载、并发数配置与标记已读后自动清理。

### 安全连接、多服务器与阅读统计
- **更安全的登录方式**：支持「账号密码换取专属可吊销 API Key（本地绝不保存密码）」与「直接粘贴 API Key」两种模式，凭据加密存储于系统 Keychain / Keystore。
- **反向代理与内网友好**：完整支持局域网 HTTP、反代子路径（如 `https://host/komga`）、HTTP 误连 HTTPS 端口自动升级，以及自签名/过期证书的 **TOFU（首次信任）指纹固定**。
- **多服务器隔离与本地统计**：支持保存并一键切换多台 Komga 服务器，所有进度、下载、置顶、历史与阅读覆盖按服务器完全隔离；内置本地阅读历史、连续阅读天数与 12 周热力图，并支持通过剪贴板导出/导入偏好设置（不含凭据）。

---

## 获取与使用

### 1. 获取安装包

目前可通过本仓库的 [GitHub Actions](https://github.com/njuwuyuxin/Yomu/actions) 获取每次构建产物（Artifact 保留 14 天，下载需登录 GitHub 账号）：

| 平台 | 流水线 | 产物说明 |
|---|---|---|
| **Android** | `Android` (`build-android.yml`) | `komga-native-apk`：可直接在 Android 设备安装的 `app-release.apk`（debug 签名） |
| **iOS** | `iOS` (`build-ios.yml`) | `komga-native-ios-unsigned`：未签名 `Runner.app.zip`（真机安装需通过 Xcode 自行签名） |

### 2. 连接到你的 Komga 服务器

1. 启动应用，输入 Komga 服务器地址（例如 `http://192.168.1.10:25600` 或带反代子路径的 `https://comics.example.com/komga`）。
2. 选择登录方式：
   - **账号模式**：输入邮箱与密码，客户端会自动调用 Komga API 创建一把独立的客户端 API Key 并仅保存该 Key（可在 Komga 后台随时吊销）。
   - **API Key 模式**：在 Komga 网页端 `账号设置 → API Keys` 生成后直接粘贴（适合开启双步验证的场景）。
3. **局域网与反代处理**：
   - 局域网明文 `http://` 可直接使用；若端口实际仅监听 HTTPS，客户端会自动升级为 `https://` 重试。
   - 若服务器使用自签名或已过期证书，客户端会展示证书 CN、颁发者、有效期与 SHA-256 指纹；核对无误点击信任后仅固定当前证书，证书更换时会再次提示确认。

更多反代与证书细节可参考 [docs/tls-and-proxy.md](docs/tls-and-proxy.md)。

---

## 本地构建与部署

### 环境要求

- **Flutter**：`3.50.0`（见 `.fvmrc`）
- **Dart SDK**：`^3.14.0`
- **Android 构建**：JDK 17 + Android SDK
- **iOS 构建**：macOS + Xcode

> Windows 用户可使用仓库内置的无管理员权限引导脚本一键体检或安装依赖：
> ```powershell
> powershell -NoProfile -ExecutionPolicy Bypass -File tool\bootstrap.ps1 -CheckOnly
> powershell -NoProfile -ExecutionPolicy Bypass -File tool\bootstrap.ps1
> ```
> 详细步骤与排障见 [docs/environment-setup.md](docs/environment-setup.md)。

### 从源码运行与构建

> 注意：Drift 数据库代码与多语言文件（`*.g.dart` / `app_localizations*.dart`）不提交至仓库，**首次克隆后需先执行代码生成**。

```bash
# 1. 克隆仓库
git clone https://github.com/njuwuyuxin/Yomu.git
cd Yomu

# 2. 安装 Workspace 依赖
cd apps/app && flutter pub get && cd ../..

# 3. 生成 Drift 与多语言代码
dart run tool/ci.dart codegen

# 4. 运行到已连接的设备或模拟器
cd apps/app && flutter run
```

构建 Release 产物：

```bash
# Android APK
cd apps/app && flutter build apk --release

# iOS（无签名验证；真机分发请配置签名后使用 flutter build ipa）
cd apps/app && flutter build ios --release --no-codesign
```

本地质量门禁（代码生成 + 格式检查 + 静态分析 + 架构分层检查 + 全量单测与黄金图）：

```bash
dart run tool/ci.dart check
```

---

## 项目结构

项目采用 Dart Pub Workspace 单仓多包结构，依赖方向严格受 `tool/ci.dart layers` 约束：

```text
Yomu/
├── apps/app                      # Flutter 应用主体（Android / iOS）
├── packages/
│   ├── komga_domain              # 纯 Dart 领域模型（零外部依赖）
│   ├── komga_reader_engine       # 纯 Dart 阅读器几何引擎（单双页分组、缩放、点击区、自动滚动、提色）
│   ├── komga_sync_engine         # 纯 Dart 进度 Outbox 与多设备对账引擎
│   ├── komga_api                 # Komga REST 传输层、错误模型、URL 契约与离线缓存接口
│   ├── komga_design_system       # 设计 Token、Light / Dark / E-Ink 三主题与玻璃控件库
│   └── komga_platform            # 平台能力抽象（断点形态、墨水屏探测、硬件键、网络与存图）
├── tool/                         # CI 门禁（ci.dart）、环境引导与本地联调脚本
└── docs/                         # 架构设计、使用指南、ADR 与开发记录
```

依赖边界：`apps/app → (design_system, platform, api, engines, domain)`，`engines → domain`，`domain → 无`。
