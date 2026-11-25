<div align="center">

# Yomu

**A Cross-Platform Native Comic Reader Client for [Komga](https://komga.org)**

Reading-First Experience · Android / iOS / Android E-Ink

[简体中文](README.md) | **English**

[![CI](https://github.com/njuwuyuxin/Yomu/actions/workflows/ci.yml/badge.svg)](https://github.com/njuwuyuxin/Yomu/actions/workflows/ci.yml)
[![Android Build](https://github.com/njuwuyuxin/Yomu/actions/workflows/build-android.yml/badge.svg)](https://github.com/njuwuyuxin/Yomu/actions/workflows/build-android.yml)
[![iOS Build](https://github.com/njuwuyuxin/Yomu/actions/workflows/build-ios.yml/badge.svg)](https://github.com/njuwuyuxin/Yomu/actions/workflows/build-ios.yml)
![Flutter](https://img.shields.io/badge/Flutter-3.50.0-02569B?logo=flutter&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20E--Ink-2E7D32)

</div>

---

## Overview

**Yomu** is a cross-platform native client for self-hosted [Komga](https://komga.org) servers built with Flutter. It focuses on a responsive comic reading experience, reliable offline access and multi-device progress synchronization, and adaptive layouts tailored for phones, tablets, and E-Ink devices.

## Features

### Reading Experience
- **Three Reading Modes**: **Single Page**, **Double-Page Spread** (smart cover & wide-page detection, plus per-book manual spread offset adjustment), and **Vertical Continuous (Webtoon)**, automatically adapting to series reading direction and screen orientation.
- **Visual & Page-Turn Controls**: Realistic shader page curl, slide, fade, or instant transitions; fit modes (fit screen, fill screen, fit width, fit height), automatic margin cropping, pinch & double-tap zoom with zoom lock, dynamic/immersive edge-color backgrounds, in-app brightness dimming, keep screen awake, and webtoon auto-scroll.
- **Flexible Controls & Reader Tools**: Five customizable tap-zone presets with direction inversion, Android volume-key page turning, keyboard & Bluetooth page turner support, quick `AA` settings sheet, per-series setting overrides, reusable reading presets, chapter/volume TOC, thumbnail scrubber, incognito mode, page sharing, and one-tap image saving (with automatic left/right stitching for double-page spreads).

### E-Ink & Adaptive Layouts
- **Dedicated E-Ink Optimization**: Zero-animation, zero-shadow, high-contrast black-on-white theme and reading canvas; automatic Android E-Ink device detection (Boox, Meebook, Boyue/LikeBook, Hisense, etc.) with manual override.
- **Responsive Phone & Tablet UI**: Automatic two-pane library (library rail + shelf) and two-pane series detail on wide screens (`≥ 1024dp`), configurable default tablet layout (auto / single / double), and highest display refresh-rate request on Android.
- **Accessibility & Localization**: Screen-reader semantics, minimum touch targets, dynamic text scaling support, and bilingual UI (**简体中文** / **English**, system-following or manual).

### Library, Collections & Search
- **Reading Now Home**: Unified entry point for continue reading, recent reading history, recently added series, and per-library shelves.
- **Library & Series Management**: Grid/list views, adjustable cover sizes, sorting, read-status and library filters, savable filter presets, pinned series, unread count badges, and multi-select batch actions (mark read/unread, add to collections).
- **Collections & Read Lists**: Cover collages, local search & sorting, plus creating, renaming, deleting, and curating collections.
- **Global Search**: Search across both series and books with search history and read-status / tag facets.

### Offline Cache, Downloads & Progress Sync
- **Local-First Progress Outbox**: Page progress is persisted locally first and synced automatically on reconnect, app resume, or cold start, reconciling across devices via server timestamps without losing offline reads.
- **Offline Response & Image Caching**: Automatically caches visited shelves, metadata, covers, and pages (256 MB LRU budget for images, stored separately from user data) with seamless offline fallback and status banner.
- **Full-Book & Batch Downloads**: Download individual books, an entire series, or the next N unread books with a persistent download queue, pause/resume/retry controls, Wi-Fi-only option, configurable concurrency, and auto-delete after marking read.

### Security, Multi-Server & Insights
- **Credential-Safe Authentication**: Sign in with Account credentials (exchanges credentials for a dedicated revocable API key; **passwords are never stored**) or paste an existing Komga API key directly; keys are stored in the OS Keychain / Keystore.
- **Reverse-Proxy & LAN Friendly**: Supports LAN HTTP, reverse-proxy subpaths (e.g. `https://host/komga`), automatic `http` → `https` upgrade on HTTPS-only ports, and **TOFU (Trust On First Use)** SHA-256 fingerprint pinning for self-signed or expired certificates.
- **Multi-Server Isolation & Local Insights**: Save and switch between multiple Komga servers with complete per-server isolation for progress, downloads, pinned series, reading history, and per-series reader settings; includes local reading history, streaks, a 12-week activity heatmap, and clipboard preference backup/restore (excluding credentials).

---

## Installation & Usage

### 1. Download Prebuilt Artifacts

Prebuilt CI artifacts are available from [GitHub Actions](https://github.com/njuwuyuxin/Yomu/actions) (retained for 14 days; requires a GitHub account to download):

| Platform | Workflow | Artifact |
|---|---|---|
| **Android** | `Android` (`build-android.yml`) | `komga-native-apk` — installable `app-release.apk` (debug-signed) |
| **iOS** | `iOS` (`build-ios.yml`) | `komga-native-ios-unsigned` — unsigned `Runner.app.zip` (requires Xcode signing for physical devices) |

### 2. Connect to Your Komga Server

1. Launch the app and enter your Komga server URL (e.g., `http://192.168.1.10:25600` or a subpath URL like `https://comics.example.com/komga`).
2. Choose an authentication method:
   - **Account**: Enter your email and password. The client requests a dedicated API key from Komga and stores only that key (revocable anytime from Komga settings).
   - **API Key**: Create a key under Komga `Account Settings → API Keys` and paste it directly (recommended when 2FA is enabled).
3. **LAN & Reverse Proxy Notes**:
   - Plain `http://` works out of the box on local networks. If the port serves HTTPS only, the client detects the proxy response and upgrades to `https://` automatically.
   - For self-signed or expired certificates, a verification sheet displays the certificate CN, issuer, validity period, and SHA-256 fingerprint. Trusting pins only that leaf certificate and prompts again if it changes.

See [docs/tls-and-proxy.md](docs/tls-and-proxy.md) for detailed proxy and TLS behavior.

---

## Building from Source

### Prerequisites

- **Flutter**: `3.50.0` (see `.fvmrc`)
- **Dart SDK**: `^3.14.0`
- **Android builds**: JDK 17 + Android SDK
- **iOS builds**: macOS + Xcode

> On Windows, you can check or bootstrap the toolchain without administrator privileges using:
> ```powershell
> powershell -NoProfile -ExecutionPolicy Bypass -File tool\bootstrap.ps1 -CheckOnly
> powershell -NoProfile -ExecutionPolicy Bypass -File tool\bootstrap.ps1
> ```
> See [docs/environment-setup.md](docs/environment-setup.md) for details.

### Run & Build Locally

> Note: Generated Drift and localization files (`*.g.dart` / `app_localizations*.dart`) are git-ignored. **Run code generation once after a fresh clone.**

```bash
# 1. Clone the repository
git clone https://github.com/njuwuyuxin/Yomu.git
cd Yomu

# 2. Fetch workspace dependencies
cd apps/app && flutter pub get && cd ../..

# 3. Generate Drift and localization code
dart run tool/ci.dart codegen

# 4. Run on a connected device or emulator
cd apps/app && flutter run
```

Build release binaries:

```bash
# Android APK
cd apps/app && flutter build apk --release

# iOS (unsigned verification build; configure signing and use `flutter build ipa` for distribution)
cd apps/app && flutter build ios --release --no-codesign
```

Run the full local quality gate (codegen + format + analyze + layer rules + all unit/widget/golden tests):

```bash
dart run tool/ci.dart check
```

---

## Project Structure

Yomu uses a Dart Pub Workspace monorepo with layered boundaries enforced by `tool/ci.dart layers`:

```text
Yomu/
├── apps/app                      # Flutter application (Android / iOS)
├── packages/
│   ├── komga_domain              # Pure Dart domain models (zero dependencies)
│   ├── komga_reader_engine       # Pure Dart reader geometry (spreads, zoom, tap zones, auto-scroll, edge color)
│   ├── komga_sync_engine         # Pure Dart progress outbox & multi-device reconciliation
│   ├── komga_api                 # Komga REST transport, error model, URL contract & cache interface
│   ├── komga_design_system       # Design tokens, Light / Dark / E-Ink themes & glass components
│   └── komga_platform            # Platform abstractions (size class, E-Ink probe, hardware keys, network, image saving)
├── tool/                         # Unified CI runner (ci.dart), environment bootstrap & local helpers
└── docs/                         # Architecture docs, guides, ADRs & development notes
```

Dependency direction: `apps/app → (design_system, platform, api, engines, domain)`, `engines → domain`, `domain → none`.

---

## Known Limitations

- **Keep Screen Awake & Volume Keys**: Currently implemented on Android only; gracefully no-op on iOS.
- **E-Ink Tuning**: Uses a fixed high-contrast E-Ink theme without runtime contrast/gamma sliders.
- **In-App Brightness**: Implemented as an overlay dimmer rather than modifying the OS system brightness.
- **Certificate Pinning**: Pins the leaf certificate's SHA-256 fingerprint (re-confirmation required upon renewal; no custom CA chain or mTLS).
- **Release Signing**: CI-built Android APKs are debug-signed and iOS artifacts are unsigned; Play Store / TestFlight distribution is not yet configured.

---

## Documentation

*(Most internal engineering documentation is maintained in Simplified Chinese.)*

- **Environment Setup**: [docs/environment-setup.md](docs/environment-setup.md)
- **Reverse Proxy & TLS Guide**: [docs/tls-and-proxy.md](docs/tls-and-proxy.md)
- **Reader Architecture & Settings**: [docs/reader.md](docs/reader.md)
- **Offline Caching & Storage**: [docs/offline-cache.md](docs/offline-cache.md)
- **Accessibility & Adaptive Input**: [docs/a11y-and-input.md](docs/a11y-and-input.md)
- **CI Workflows**: [docs/ci.md](docs/ci.md)
- **Development Notes, Verification Archive & Full Doc Index**: [docs/development-notes.md](docs/development-notes.md)
- **Changelog**: [CHANGELOG.md](CHANGELOG.md)
