# ScreenPresenter 自动更新设置指南

本文档介绍如何配置和使用基于 Sparkle + GitHub 的自动更新功能。

## 📋 概述

ScreenPresenter 使用 [Sparkle](https://sparkle-project.org/) 框架实现自动更新，支持：

- ✅ 自动检查更新（可配置检查间隔）
- ✅ 手动检查更新（菜单项）
- ✅ Ed25519 安全签名
- ✅ **GitHub 私有仓库分发**（本项目重点）

## 🔐 私有仓库配置（重要）

由于 `AIAugmentLab/ScreenPresenter` 是私有仓库，需要配置 GitHub Personal Access Token (PAT)。

### 创建 GitHub Token

1. 访问 [GitHub Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens)
2. 点击 "Generate new token (classic)"
3. 选择权限：
   - `repo` (Full control of private repositories)
4. 生成并复制 Token

### 配置 Token

**方法 1: 环境变量（推荐用于开发）**

```bash
# 在 ~/.zshrc 或 ~/.bashrc 中添加
export GITHUB_TOKEN="ghp_xxxxxxxxxxxx"
```

**方法 2: 首次启动时配置**

应用首次启动时，如果检测到私有仓库且无 Token，会提示用户输入。

**方法 3: 代码中设置**

```swift
UpdateManager.shared.setGitHubToken("ghp_xxxxxxxxxxxx")
```

## 🚀 快速开始

### 1. 添加 Sparkle 依赖

在 Xcode 中添加 Sparkle 包：

```
File → Add Package Dependencies
URL: https://github.com/sparkle-project/Sparkle
Version: 2.0.0 或更高
```

或者在 `Package.swift` 中添加：

```swift
dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
]
```

### 2. 生成签名密钥

```bash
# 安装 Sparkle 命令行工具
brew install --cask sparkle

# 生成 Ed25519 密钥对
generate_keys

# 输出示例:
# A network reachable DSA public key was written to '~/.config/Sparkle/eddsa_public_key'.
# A signing private key was written to '~/.config/Sparkle/eddsa_private_key'.
```

⚠️ **重要**：私钥必须安全保存，不要提交到代码仓库！

### 3. 配置 Info.plist

将公钥填入 `Info.plist`：

```xml
<key>SUPublicEDKey</key>
<string>你的公钥内容</string>

<key>SUFeedURL</key>
<string>https://raw.githubusercontent.com/AIAugmentLab/ScreenPresenter/main/appcast.xml</string>
```

### 4. 创建版本发布

```bash
# 运行发布脚本
./release.sh 1.0.1

# 脚本会：
# 1. 更新版本号
# 2. 构建 Release 版本
# 3. 创建 ZIP 包
# 4. 使用私钥签名
# 5. 输出签名信息
```

### 5. 更新 appcast.xml

将签名信息填入 `appcast.xml`：

```xml
<enclosure 
    url="https://github.com/AIAugmentLab/ScreenPresenter/releases/download/1.0.1/ScreenPresenter.zip"
    sparkle:edSignature="签名字符串"
/>
```

### 6. 发布到 GitHub

```bash
# 创建 Release 并上传文件
gh release create 1.0.1 build/ScreenPresenter.zip \
    --title "1.0.1" \
    --notes "Release notes here"

# 提交更新后的 appcast.xml
git add appcast.xml
git commit -m "Release 1.0.1"
git push
```

## ⚙️ 配置选项

### Info.plist 配置项

| 键 | 说明 | 默认值 |
|---|---|---|
| `SUFeedURL` | appcast.xml 的 URL | 必填 |
| `SUPublicEDKey` | Ed25519 公钥 | 必填 |
| `SUEnableAutomaticChecks` | 自动检查更新 | true |
| `SUScheduledCheckInterval` | 检查间隔（秒） | 86400（1天） |

### 代码配置

```swift
// 启用/禁用自动检查
UpdateManager.shared.automaticallyChecksForUpdates = true

// 设置检查间隔（秒）
UpdateManager.shared.updateCheckInterval = 3600 // 1小时

// 启用自动下载
UpdateManager.shared.automaticallyDownloadsUpdates = true
```

## 📁 文件结构

```
ScreenPresenter/
├── appcast.xml              # 版本描述文件
├── release.sh               # 发布脚本
├── ScreenPresenter/
│   ├── Info.plist          # 包含 Sparkle 配置
│   └── Core/Utilities/
│       └── UpdateManager.swift  # 更新管理器
└── docs/
    └── AUTO_UPDATE_SETUP.md     # 本文档
```

## 🔧 故障排除

### 检查更新无响应

1. 确认 `SUFeedURL` 配置正确
2. 检查 appcast.xml 是否可访问
3. 查看控制台日志（`Console.app` 或 Xcode 控制台）

### 签名验证失败

1. 确认公钥与私钥匹配
2. 重新签名 ZIP 文件
3. 更新 appcast.xml 中的签名

### 私有仓库下载失败

1. 确认 Token 有 `repo` 权限
2. 检查 Token 是否过期
3. 确认下载 URL 格式正确

## 📚 参考资料

- [Sparkle 官方文档](https://sparkle-project.org/documentation/)
- [Sparkle GitHub](https://github.com/sparkle-project/Sparkle)
- [GitHub Releases API](https://docs.github.com/en/rest/releases)

## 🆕 更新日志

- **2026-01-06**: 初始版本，支持基本自动更新功能
