#!/bin/bash

#
# release.sh
# ScreenPresenter 一键发布脚本
#
# 用法:
#   ./release.sh <version>
#   例如: ./release.sh 1.0.0
#
# 功能:
#   1. 构建 Release 版本
#   2. 创建 ZIP 包
#   3. Sparkle Ed25519 签名
#   4. 更新本地 appcast.xml
#   5. 上传到 GitHub Releases
#   6. 回填 appcast.xml 下载链接为 Release 公网地址
#
# 前置要求:
#   1. brew install --cask sparkle
#   2. brew install gh (GitHub CLI)
#   3. gh auth login (登录 GitHub)
#   4. 已运行 generate_keys 生成签名密钥
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 日志函数
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_step() { echo -e "${CYAN}▶️  $1${NC}"; }

# 检查参数
if [ -z "$1" ]; then
    log_error "请提供版本号"
    echo ""
    echo "用法: $0 <version>"
    echo "例如: $0 1.0.0"
    echo ""
    exit 1
fi

VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
APP_NAME="ScreenPresenter"
BUILD_DIR="$PROJECT_DIR/build"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
APPCAST_PATH="$PROJECT_DIR/appcast.xml"

# Sparkle 工具路径
SPARKLE_BIN="/opt/homebrew/Caskroom/sparkle/2.8.1/bin"
SIGN_UPDATE="$SPARKLE_BIN/sign_update"

# GitHub 仓库（优先从 origin 自动解析）
REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
    GITHUB_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
else
    GITHUB_REPO="HapticTide/ScreenPresenter"
fi

echo ""
echo "=========================================="
echo -e "${CYAN}🚀 ScreenPresenter 发布脚本${NC}"
echo "=========================================="
echo "版本: $VERSION"
echo ""

# ============================================
# 步骤 1: 检查依赖
# ============================================
log_step "检查依赖..."

if ! command -v gh &> /dev/null; then
    log_error "未安装 GitHub CLI (gh)"
    echo "请运行: brew install gh && gh auth login"
    exit 1
fi

if ! gh auth status &> /dev/null; then
    log_error "GitHub CLI 未登录"
    echo "请运行: gh auth login"
    exit 1
fi

if [ ! -f "$SIGN_UPDATE" ]; then
    log_error "未找到 Sparkle sign_update 工具"
    echo "请运行: brew install --cask sparkle"
    exit 1
fi

log_success "依赖检查通过"

# ============================================
# 步骤 2: 清理构建目录
# ============================================
log_step "清理构建目录..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
log_success "构建目录已清理"

# ============================================
# 步骤 3: 构建应用
# ============================================
log_step "构建 Release 版本..."

# 更新 Xcode 项目中的版本号
cd "$PROJECT_DIR"

# 计算 Build 号（当前时间格式: YYYYMMDDHHMM）
BUILD_NUMBER=$(date +%Y%m%d%H%M)

# 直接修改 project.pbxproj 中的版本号（不使用 agvtool，避免覆盖 Info.plist 中的变量）
PBXPROJ_PATH="$PROJECT_DIR/$APP_NAME.xcodeproj/project.pbxproj"
sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/g" "$PBXPROJ_PATH"
sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" "$PBXPROJ_PATH"

log_info "版本号: $VERSION, Build: $BUILD_NUMBER"

# 使用 xcodebuild build 而不是 archive，让 Xcode 自动签名
# 不再使用 CODE_SIGN_IDENTITY="-" 强制 ad-hoc 签名
BUILD_CMD=(
    xcodebuild clean build
    -project "$PROJECT_DIR/$APP_NAME.xcodeproj"
    -scheme "$APP_NAME"
    -configuration Release
    -derivedDataPath "$BUILD_DIR/DerivedData"
    ENABLE_HARDENED_RUNTIME=YES
    ONLY_ACTIVE_ARCH=NO
)

if command -v xcpretty &> /dev/null; then
    set -o pipefail
    "${BUILD_CMD[@]}" 2>&1 | xcpretty || {
        log_error "构建失败"
        exit 1
    }
    set +o pipefail
else
    log_warning "未安装 xcpretty，使用原始 xcodebuild 输出"
    "${BUILD_CMD[@]}" || {
        log_error "构建失败"
        exit 1
    }
fi

log_success "构建完成"

# ============================================
# 步骤 4: 导出应用
# ============================================
log_step "导出应用..."

# 查找构建产物
APP_BUILD_PATH=$(find "$BUILD_DIR/DerivedData" -name "$APP_NAME.app" -type d | head -1)

if [ -z "$APP_BUILD_PATH" ] || [ ! -d "$APP_BUILD_PATH" ]; then
    log_error "构建失败：找不到 $APP_NAME.app"
    exit 1
fi

# 复制到 build 目录
cp -R "$APP_BUILD_PATH" "$BUILD_DIR/"

# 验证签名（Xcode 应该已经正确签名了）
log_info "验证签名..."
codesign --verify --verbose=2 "$BUILD_DIR/$APP_NAME.app"

# 验证 Sparkle framework 签名
SPARKLE_FRAMEWORK="$BUILD_DIR/$APP_NAME.app/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_FRAMEWORK" ]; then
    codesign --verify --verbose=2 "$SPARKLE_FRAMEWORK" || {
        log_error "Sparkle.framework 签名验证失败"
        exit 1
    }
fi

log_success "应用导出完成"

# ============================================
# 步骤 5: 创建 ZIP
# ============================================
log_step "创建 ZIP 包..."

cd "$BUILD_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$APP_NAME.zip"
cd "$PROJECT_DIR"

ZIP_SIZE=$(stat -f%z "$ZIP_PATH")
ZIP_SIZE_MB=$(echo "scale=2; $ZIP_SIZE / 1024 / 1024" | bc)
log_success "ZIP 创建完成 (${ZIP_SIZE_MB} MB)"

# ============================================
# 步骤 6: Sparkle 签名
# ============================================
log_step "使用 Sparkle 签名..."

SIGN_OUTPUT=$("$SIGN_UPDATE" "$ZIP_PATH" 2>&1)

# 解析签名和长度
ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
ED_LENGTH=$(echo "$SIGN_OUTPUT" | grep -o 'length="[^"]*"' | cut -d'"' -f2)

if [ -z "$ED_SIGNATURE" ]; then
    log_error "签名失败"
    echo "$SIGN_OUTPUT"
    exit 1
fi

log_success "签名完成"
echo "  签名: ${ED_SIGNATURE:0:50}..."
echo "  长度: $ED_LENGTH"

# ============================================
# 步骤 7: 更新本地 appcast.xml
# ============================================
log_step "更新本地 appcast.xml..."

# 获取当前日期（RFC 2822 格式）
PUB_DATE=$(date -R)

# 注意：BUILD_NUMBER 已在步骤3中设置为时间戳格式

# 更新 appcast.xml 中的签名和长度
sed -i '' "s|sparkle:edSignature=\"[^\"]*\"|sparkle:edSignature=\"$ED_SIGNATURE\"|g" "$APPCAST_PATH"
sed -i '' "s|length=\"[^\"]*\"|length=\"$ED_LENGTH\"|g" "$APPCAST_PATH"

# 更新版本号（sparkle:version 使用 Build 号时间戳）
sed -i '' "s|<sparkle:version>[^<]*</sparkle:version>|<sparkle:version>$BUILD_NUMBER</sparkle:version>|g" "$APPCAST_PATH"
sed -i '' "s|<sparkle:shortVersionString>[^<]*</sparkle:shortVersionString>|<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>|g" "$APPCAST_PATH"

# 更新 item 标题为版本号
sed -i '' "s|<title>Version [^<]*</title>|<title>Version $VERSION</title>|g" "$APPCAST_PATH"

# 更新发布日期
sed -i '' "s|<pubDate>[^<]*</pubDate>|<pubDate>$PUB_DATE</pubDate>|g" "$APPCAST_PATH"

log_success "本地 appcast.xml 已更新（待创建 Release 后回填下载链接）"

# ============================================
# 步骤 8: 上传到 GitHub Releases
# ============================================
log_step "上传到 GitHub Releases..."

# 检查 Release 是否已存在
if gh release view "$VERSION" --repo "$GITHUB_REPO" &> /dev/null; then
    log_error "Release $VERSION 已存在，请先手动处理后再重试"
    exit 1
fi

# 从 appcast.xml 提取 description 作为 Release Notes
# 先更新 appcast.xml 中描述里的版本号
sed -i '' "s/ScreenPresenter [0-9.]*</ScreenPresenter $VERSION</g" "$APPCAST_PATH"

# 提取 CDATA 内容并转换为 Markdown
RELEASE_NOTES=$(awk '/<!\[CDATA\[/,/\]\]>/' "$APPCAST_PATH" | \
    sed '1d' | \
    grep -v '\]\]>' | \
    sed 's/<h2>/## /g' | \
    sed 's/<\/h2>//g' | \
    sed 's/<h3>/### /g' | \
    sed 's/<\/h3>//g' | \
    sed 's/<p>//g' | \
    sed 's/<\/p>//g' | \
    sed 's/<ul>//g' | \
    sed 's/<\/ul>//g' | \
    sed 's/<li>/- /g' | \
    sed 's/<\/li>//g' | \
    sed 's/^[[:space:]]*//' | \
    grep -v '^$')

# 创建 Release 并上传
gh release create "$VERSION" \
    "$ZIP_PATH" \
    --repo "$GITHUB_REPO" \
    --title "ScreenPresenter $VERSION" \
    --notes "$RELEASE_NOTES"

log_success "GitHub Release 创建完成"

# ============================================
# 步骤 9: 获取下载链接并更新 appcast.xml
# ============================================
log_step "获取 Release 下载链接..."

# 等待一下确保 Release 创建完成
sleep 2

# 获取 Release 资产信息
ASSET_ID=$(gh api "/repos/$GITHUB_REPO/releases/tags/$VERSION" --jq '.assets[] | select(.name == "ScreenPresenter.zip") | .id' 2>/dev/null)
DOWNLOAD_URL=$(gh api "/repos/$GITHUB_REPO/releases/tags/$VERSION" --jq '.assets[] | select(.name == "ScreenPresenter.zip") | .browser_download_url' 2>/dev/null)

if [ -z "$ASSET_ID" ] || [ -z "$DOWNLOAD_URL" ]; then
    log_error "无法获取 Release 资产信息（ScreenPresenter.zip）"
    exit 1
fi

log_success "Asset ID: $ASSET_ID"
log_info "下载链接: $DOWNLOAD_URL"

# 更新 appcast.xml 的 enclosure 下载地址为公开直链
sed -i '' "s|url=\"https://api.github.com/repos/[^\\\"]*/releases/assets/[0-9]*\"|url=\"$DOWNLOAD_URL\"|g" "$APPCAST_PATH"
sed -i '' "s|url=\"https://github.com/[^\\\"]*/releases/download/[^\"]*\"|url=\"$DOWNLOAD_URL\"|g" "$APPCAST_PATH"

log_success "appcast.xml 下载链接已更新"

# ============================================
# 完成
# ============================================
echo ""
echo "=========================================="
echo -e "${GREEN}🎉 发布完成！${NC}"
echo "=========================================="
echo ""
echo "版本: $VERSION"
echo "文件: $ZIP_PATH"
echo "Asset ID: $ASSET_ID"
echo ""
echo "链接:"
echo "  - Release: https://github.com/$GITHUB_REPO/releases/tag/$VERSION"
echo "  - Appcast: https://raw.githubusercontent.com/$GITHUB_REPO/main/appcast.xml"
echo ""
log_success "用户现在可以通过应用内更新获取新版本！"
echo ""
