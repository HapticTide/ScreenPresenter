# Contributing

感谢你关注 ScreenPresenter。提交改动前，请先确认本地能完成基础构建。

## 开发环境

- macOS 13.0+
- Xcode 16.4+
- Swift 6.0+

## 本地构建

```bash
xcodebuild -project ScreenPresenter.xcodeproj \
  -scheme ScreenPresenter \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Pull Request

- 保持改动范围聚焦，避免混入无关格式化。
- 修改 Swift 文件后，仅对改动文件执行 `swiftformat <file>`。
- 新增用户可见文案时，请同步中英文 `Localizable.strings`。
- PR 描述中写清楚验证方式；如果无法验证，请说明原因。

## 发布

维护者发布流程见 [docs/RELEASE.md](docs/RELEASE.md)。
