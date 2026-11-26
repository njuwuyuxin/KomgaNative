# ADR 0010: CBR (RAR4/RAR5) 与 CB7 (7z) 原生解码桥接与固实包滑动窗口策略

- **状态**：已采纳（2026-11-26）
- **关联需求**：`LMB-12`（二期 Phase C）

## 背景

民间漫画归档除 `CBZ/ZIP`、`EPUB`、`CBT/TAR`、`PDF` 外，还存在大量 `.cbr`（RAR4 / RAR5）与 `.cb7`（7z / LZMA2）文件。两类格式存在两个核心技术约束：

1. **算法复杂度与许可边界**：7z 依赖 `LZMA2` 及可选多文件固实压缩（Solid Block）；RAR4/RAR5 使用专有解压算法，纯 Dart 手写既无性能保障也难以维护。
2. **固实包（Solid Archive）随机跳页退化**：固实 7z/RAR 压缩包把多页合并在同一压缩流里，若阅读器每翻一页都单独重新打开归档并从头解压到第 `k` 页，整本 200 页将退化为 \(O(N^2)\) 解压耗时与高发热。

## 决策

1. **抽象边界（`yomu_platform` + `yomu_local_archive`）**：
   - 在 `packages/yomu_platform` 定义平台通道 `NativeArchiveBridge`（`yomu/native_archive`），提供 `listEntries`、`extractEntry` 与面向固实包的单趟批量接口 `extractWindow(entryNames)`；
   - 在纯 Dart `packages/yomu_local_archive` 提供 `SolidArchiveWindowCache`（默认窗口大小 6 页、上限 18 页 LRU 缓存，合并并发窗口请求，把固实包顺序翻页由 \(O(N^2)\) 降为 \(O(N)\) 线性单趟解压）以及零依赖 RAR4/RAR5 二进制头嗅探与无压缩（Stored）条目解析。
2. **Android 端原生解码依赖（仅 Gradle JVM 依赖，零 NDK ABI 膨胀）**：
   - `org.apache.commons:commons-compress:1.27.1`（Apache-2.0）+ `org.tukaani:xz:1.10`（Public Domain）：提供完整原生 `7z / CB7`（含 LZMA2、固实块与密码解密）解压；
   - `com.github.junrar:junrar:7.5.5`（UnRAR-compatible）：提供完整原生 `RAR4 / CBR`（含固实包与密码解密）解压。
   - 相比引入 `pub.dev` C/C++ FFI 插件，Gradle 纯 JVM 依赖不增加多架构 `.so` 体积，不破坏 Windows CI 与 Gradle 8/AGP 构建。
3. **iOS 端兼容性**：
   - 在 `SceneDelegate.swift` 注册 `yomu/native_archive` 插件通道，保持零 CocoaPods 额外依赖确保 macOS CI 编译稳定；后续如需 iOS 侧 RAR5/LZMA2 压缩流解码，可在同一通道后无感接入静态 `libarchive.xcframework`，Dart 业务层无需改动。

## 后果

- Android 实机与模拟器可直接导入并流畅阅读 `.cb7/.7z`（含固实包、LZMA2、加密包）与 `.cbr/.rar`（RAR4）；
- 固实包通过 `SolidArchiveWindowCache` 实现窗口预解与内存上限控制，避免翻页卡顿与 OOM；
- 加密 RAR/7z 统一抛出 `ArchiveErrorKind.encryptedArchive`，无缝接入 `LMB-13` 密码弹窗与钥匙串记忆链路。
