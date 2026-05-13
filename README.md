# ScreenPresenter

[![CI](https://github.com/HapticTide/ScreenPresenter/actions/workflows/ci.yml/badge.svg)](https://github.com/HapticTide/ScreenPresenter/actions/workflows/ci.yml)
[![Release](https://github.com/HapticTide/ScreenPresenter/actions/workflows/release.yml/badge.svg)](https://github.com/HapticTide/ScreenPresenter/actions/workflows/release.yml)
[![License](https://img.shields.io/github/license/HapticTide/ScreenPresenter)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)](#系统要求)

ScreenPresenter 是一款 macOS 原生设备投屏工具，支持同时展示 iOS 与 Android 设备屏幕，并提供高还原度的设备边框渲染与内嵌 Markdown 编辑器。

## 截图

| 双设备主界面 | 单设备主界面 |
|---|---|
| ![双设备主界面](screenshots/1.png) | ![单设备主界面](screenshots/2.png) |

| 文档编辑 | 分屏查看 |
|---|---|
| ![文档编辑](screenshots/3.png) | ![文档查看](screenshots/4.png) |

| 双设备投屏中 | 偏好设置-通用 |
|---|---|
| ![双设备投屏中](screenshots/5.png) | ![偏好设置-通用](screenshots/6.png) |

| 偏好设置-捕获 | 偏好设置-权限 |
|---|---|
| ![偏好设置-捕获](screenshots/7.png) | ![偏好设置-权限](screenshots/8.png) |

## 核心特性

- iOS 投屏：CoreMediaIO + AVFoundation（QuickTime 同路径）
- Android 投屏：scrcpy 码流 + VideoToolbox 硬件解码
- Metal 渲染：CVDisplayLink 驱动高帧率渲染
- 双设备展示：同窗同时展示 iOS/Android，支持布局切换
- 设备边框：按设备型号渲染动态岛/刘海/打孔屏/侧键等特征
- Markdown 编辑器：多标签、语法高亮、主题切换、查找替换、预览模式
- 本地化：简体中文 / English

## 系统要求

- macOS 13.0+
- Xcode 16.4+（开发构建）
- Apple Silicon / Intel Mac

## 安装

从 [GitHub Releases](https://github.com/HapticTide/ScreenPresenter/releases) 下载最新版本，解压 ZIP 或打开 DMG 后，将 `ScreenPresenter.app` 拖入 `/Applications`。

### 打开未签名构建

GitHub Actions 自动构建的开源产物未进行 Developer ID 签名和公证。首次打开时，如果 macOS 提示“无法验证开发者”或阻止启动，请确认应用来源可信后执行：

```bash
xattr -dr com.apple.quarantine /Applications/ScreenPresenter.app
open /Applications/ScreenPresenter.app
```

如果你把 App 放在其他目录，请把命令中的路径替换为实际路径，例如：

```bash
xattr -dr com.apple.quarantine ~/Downloads/ScreenPresenter.app
open ~/Downloads/ScreenPresenter.app
```

## 快速开始

### iOS

1. 使用 USB 连接 iOS 设备并在设备上点击“信任此电脑”。
2. 确保设备已解锁。
3. 首次启动时授予 ScreenPresenter 摄像头权限（用于系统投屏采集链路）。

### Android

1. 在开发者选项中开启“USB 调试”。
2. 使用 USB 连接设备，并在设备上确认调试授权。
3. App 内置 `adb` / `scrcpy-server`，默认无需额外安装工具链。

## 文档编辑器

文档编辑器位于主窗口内，适用于投屏过程中的旁路记录、脚本、演示稿编辑。

### 实现来源

- 基于 [MarkEdit](https://github.com/MarkEdit-app/MarkEdit) 与 [MarkEdit-preview](https://github.com/MarkEdit-app/MarkEdit-preview) 实现。
- 在原项目基础上结合 ScreenPresenter 场景做了精简与调整（嵌入式集成、菜单与快捷键行为、偏好项与会话逻辑等）。

### 关键行为

- 打开文件时，若当前只有一个空白未改动标签页，会直接复用该标签页。
- 启动 App 时会自动恢复上次打开的文档（不存在文件会自动跳过）。
- 未保存状态会在标签上显示标记（新建未落盘与已落盘未保存都支持）。
- `⌘W` 关闭当前文档标签页（不再关闭 App）。

### 常用快捷键

| 功能 | 快捷键 |
|---|---|
| 显示/隐藏文档编辑器 | `⌘⇧M` |
| 编辑/预览模式切换 | `⌘⇧V` |
| 查找 | `⌘F` |
| 查找和替换 | `⌥⌘F` |
| 查找下一个/上一个 | `⌘G` / `⇧⌘G` |
| 用所选内容查找 | `⌘E` |
| 选择所有相同项 | `⌥⌘E` |
| 选择下个相同项 | `⌘D` |
| 跳到所选内容 | `⌘J` |

## 偏好设置说明

- 音频捕获默认关闭。
- 当音频捕获关闭时，设备面板隐藏全部音频相关 UI（包括音频开关与音量控件）。
- 音频捕获开关为“重启 App 后生效”。偏好设置中已提供黄色提示文案。

## 自动更新

项目使用 Sparkle 自动更新。

- 更新源：`https://raw.githubusercontent.com/HapticTide/ScreenPresenter/main/appcast.xml`
- 安装包来源：GitHub Releases（公开仓库）

## 构建

```bash
xcodebuild -project ScreenPresenter.xcodeproj \
  -scheme ScreenPresenter \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

CI 使用同样的无签名构建路径，见 `.github/workflows/ci.yml`。

## 参与贡献

请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。PR 会触发 GitHub Actions 构建校验；当前主工程 scheme 未配置 test action，因此 CI 以 macOS app 编译为主。

维护者发布流程见 [docs/RELEASE.md](docs/RELEASE.md)。

## 变更记录

- [docs/CHANGELOG.md](docs/CHANGELOG.md)

## 许可证

本项目采用 [MIT License](LICENSE)。
