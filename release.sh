#!/bin/bash

#
# release.sh
# ScreenPresenter 发布脚本
#
# 用法:
#   ./release.sh <version>
#   例如: ./release.sh 1.0.1
#
# 前置要求:
#   1. 安装 Sparkle: brew install --cask sparkle
#   2. 生成签名密钥: generate_keys (Sparkle 工具)
#   3. 设置环境变量:
#      - SPARKLE_PRIVATE_KEY: Ed25519 私钥路径
#      - GITHUB_TOKEN: GitHub Personal Access Token (可选，用于私有仓库)
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# 检查参数
if [ -z "$1" ]; then
    log_error "请提供版本号"
    echo "用法: $0 <version>"
    echo "例如: $0 1.0.1"
    exit 1
fi

VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
APP_NAME="ScreenPresenter"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/Export"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

# Sparkle 工具路径
SPARKLE_BIN="/usr/local/bin"
GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"
SIGN_UPDATE="$SPARKLE_BIN/sign_update"

log_info "开始构建 $APP_NAME v$VERSION..."

# ============================================
# 步骤 1: 清理构建目录
# ============================================
log_info "清理构建目录..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ============================================
# 步骤 2: 更新版本号
# ============================================
log_info "更新版本号到 $VERSION..."

# 更新 Info.plist 中的版本号
PLIST_PATH="$PROJECT_DIR/$APP_NAME/Info.plist"
if [ -f "$PLIST_PATH" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST_PATH"
    
    # 计算 Build 号（可以使用日期或递增数字）
    BUILD_NUMBER=$(date +%Y%m%d%H%M)
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST_PATH"
    
    log_success "版本号已更新: $VERSION ($BUILD_NUMBER)"
else
    log_warning "未找到 Info.plist，跳过版本号更新"
fi

# ============================================
# 步骤 3: 构建应用
# ============================================
log_info "构建 Release 版本..."

xcodebuild archive \
    -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    | xcpretty || {
        log_error "构建失败"
        exit 1
    }

log_success "构建完成"

# ============================================
# 步骤 4: 导出应用
# ============================================
log_info "导出应用..."

# 创建导出选项 plist
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>manual</string>
</dict>
</plist>
EOF

# 从 archive 中复制 .app
cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$BUILD_DIR/"
APP_PATH="$BUILD_DIR/$APP_NAME.app"

log_success "应用导出完成: $APP_PATH"

# ============================================
# 步骤 5: 创建 ZIP（用于 Sparkle 更新）
# ============================================
log_info "创建 ZIP 包..."

cd "$BUILD_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$APP_NAME.zip"
cd "$PROJECT_DIR"

log_success "ZIP 创建完成: $ZIP_PATH"

# ============================================
# 步骤 6: 签名更新包（Sparkle Ed25519）
# ============================================
if [ -f "$SIGN_UPDATE" ]; then
    log_info "使用 Sparkle 签名更新包..."
    
    if [ -n "$SPARKLE_PRIVATE_KEY" ] && [ -f "$SPARKLE_PRIVATE_KEY" ]; then
        SIGNATURE=$("$SIGN_UPDATE" "$ZIP_PATH" -f "$SPARKLE_PRIVATE_KEY")
        log_success "签名完成"
        echo ""
        echo "=========================================="
        echo "Ed25519 签名信息:"
        echo "$SIGNATURE"
        echo "=========================================="
        echo ""
    else
        log_warning "未设置 SPARKLE_PRIVATE_KEY 环境变量，跳过签名"
        log_info "提示: 运行 generate_keys 生成密钥对"
    fi
else
    log_warning "未找到 sign_update 工具，跳过签名"
    log_info "提示: brew install --cask sparkle"
fi

# ============================================
# 步骤 7: 创建 DMG（可选）
# ============================================
if command -v create-dmg &> /dev/null; then
    log_info "创建 DMG..."
    
    create-dmg \
        --volname "$APP_NAME" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 150 180 \
        --app-drop-link 450 180 \
        "$DMG_PATH" \
        "$APP_PATH" || true
    
    if [ -f "$DMG_PATH" ]; then
        log_success "DMG 创建完成: $DMG_PATH"
    fi
else
    log_warning "未安装 create-dmg，跳过 DMG 创建"
    log_info "提示: brew install create-dmg"
fi

# ============================================
# 步骤 8: 输出发布信息
# ============================================
echo ""
echo "=========================================="
echo -e "${GREEN}🎉 构建完成！${NC}"
echo "=========================================="
echo ""
echo "版本: $VERSION"
echo "文件:"
echo "  - ZIP: $ZIP_PATH"
[ -f "$DMG_PATH" ] && echo "  - DMG: $DMG_PATH"
echo ""
echo "下一步操作:"
echo "  1. 将 ZIP 文件上传到 GitHub Releases (tag: $VERSION)"
echo "  2. 更新 appcast.xml 中的版本信息和签名"
echo "  3. 提交并推送 appcast.xml"
echo ""

# 如果设置了 GITHUB_TOKEN，可以自动创建 Release
if [ -n "$GITHUB_TOKEN" ]; then
    log_info "检测到 GITHUB_TOKEN，可以使用 gh CLI 自动发布"
    echo "  gh release create $VERSION $ZIP_PATH --title \"$VERSION\" --notes \"Release $VERSION\""
fi

log_success "完成！"
