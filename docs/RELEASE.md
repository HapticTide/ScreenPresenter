# 发布流程

本文档面向维护者，记录 GitHub Release 与 Sparkle 自动更新的发布方式。

## 版本号

版本号使用 `X.Y.Z` 格式，tag 不带 `v` 前缀，例如 `1.2.0`。

## GitHub Actions 自动 Release

推送版本 tag 后会触发 `.github/workflows/release.yml`，自动构建 unsigned ZIP/DMG，并创建 GitHub Release：

```bash
git tag 1.2.0
git push origin 1.2.0
```

也可以在 GitHub Actions 页面手动运行 Release workflow，并输入版本号。

GitHub Actions 的自动 Release 产物用于开源分发和验证，默认不更新 Sparkle appcast。

## Sparkle 正式发布

需要更新 `appcast.xml` 时，在本地使用一键发布脚本：

```bash
# 交互式
./release_oneclick.sh

# 非交互
./release_oneclick.sh 1.2.0 --yes
```

脚本会串联处理：

- 更新版本元数据
- 构建 Release app
- 创建 ZIP
- 使用 Sparkle Ed25519 签名
- 更新 `appcast.xml`
- 创建 GitHub Release
- 回填下载地址

## 发布前检查

- 工作区只包含本次发布需要提交的改动。
- `gh auth status` 已登录目标 GitHub 账号。
- 本机已安装 Sparkle，并能访问 `sign_update`。
- 本机已安装 `xcbeautify`，发布脚本会优先使用它格式化 `xcodebuild` 输出。

## 发布后检查

```bash
git show --no-patch --decorate 1.2.0
rg -n "sparkle:shortVersionString|sparkle:version|enclosure|edSignature" appcast.xml
gh release view 1.2.0
```
