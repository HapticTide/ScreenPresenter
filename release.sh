#!/bin/bash

#
# release.sh
# ScreenPresenter 一键发布脚本
#
# 用法:
#   ./release.sh <version>
#   例如: ./release.sh 1.0.5
#
# 功能:
#   1. 构建 Release 版本
#   2. 创建 ZIP 包
#   3. Sparkle Ed25519 签名
#   4. 更新本地 appcast.xml
#   5. 更新 Gist 中的 appcast.xml
#   6. 上传到 GitHub Releases
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
    echo "例如: $0 1.0.5"
    echo ""
    exit 1
fi

VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
APP_NAME="ScreenPresenter"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
APPCAST_PATH="$PROJECT_DIR/appcast.xml"

# Sparkle 工具路径
SPARKLE_BIN="/opt/homebrew/Caskroom/sparkle/2.8.1/bin"
SIGN_UPDATE="$SPARKLE_BIN/sign_update"

# Gist 配置
GIST_ID="529546d3936dfdc120e88bdbe21bef55"

# GitHub 仓库
GITHUB_REPO="AIAugmentLab/ScreenPresenter"

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

xcodebuild archive \
    -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | xcpretty || {
        log_error "构建失败"
        exit 1
    }

log_success "构建完成"

# ============================================
# 步骤 4: 导出应用
# ============================================
log_step "导出应用..."

cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$BUILD_DIR/"

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

# 更新下载链接
sed -i '' "s|releases/download/[^/]*/ScreenPresenter.zip|releases/download/$VERSION/ScreenPresenter.zip|g" "$APPCAST_PATH"

# 更新发布日期
sed -i '' "s|<pubDate>[^<]*</pubDate>|<pubDate>$PUB_DATE</pubDate>|g" "$APPCAST_PATH"

log_success "本地 appcast.xml 已更新"

# ============================================
# 步骤 8: 更新 Gist
# ============================================
log_step "更新 Gist 中的 appcast.xml..."

gh gist edit "$GIST_ID" "$APPCAST_PATH" || {
    log_warning "Gist 更新失败，请手动更新"
    log_info "Gist URL: https://gist.github.com/sunimp/$GIST_ID"
}

log_success "Gist 已更新"

# ============================================
# 步骤 9: 上传到 GitHub Releases
# ============================================
log_step "上传到 GitHub Releases..."

# 检查 Release 是否已存在
if gh release view "$VERSION" --repo "$GITHUB_REPO" &> /dev/null; then
    log_warning "Release $VERSION 已存在，将删除并重新创建"
    gh release delete "$VERSION" --repo "$GITHUB_REPO" --yes 2>/dev/null || true
    # 删除对应的 tag
    git tag -d "$VERSION" 2>/dev/null || true
    git push origin ":refs/tags/$VERSION" 2>/dev/null || true
fi

# 创建 Release 并上传（使用 --generate-notes 自动生成更新说明）
gh release create "$VERSION" \
    "$ZIP_PATH" \
    --repo "$GITHUB_REPO" \
    --title "ScreenPresenter $VERSION" \
    --generate-notes

log_success "GitHub Release 创建完成"

# ============================================
# 步骤 10: 更新 appcast.xml 的 description
# ============================================
log_step "从 GitHub Release 获取更新说明..."

# 获取自动生成的 release notes
RELEASE_NOTES=$(gh release view "$VERSION" --repo "$GITHUB_REPO" --json body -q '.body' 2>/dev/null || echo "")

if [ -n "$RELEASE_NOTES" ]; then
    # 将 Markdown 转换为 HTML 并更新到 appcast.xml
    # 对特殊字符进行转义
    ESCAPED_NOTES=$(echo "$RELEASE_NOTES" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    
    # 生成 HTML 格式的 description
    HTML_DESCRIPTION="<h2>🚀 ScreenPresenter $VERSION</h2><pre>$ESCAPED_NOTES</pre>"
    
    # 使用 awk 更新 description（因为包含多行内容）
    awk -v desc="$HTML_DESCRIPTION" '
        /<description>/ { 
            print "            <description>"
            print "                <![CDATA["
            print "                " desc
            print "                ]]>"
            print "            </description>"
            # 跳过原有的 description 内容直到遇到 </description>
            while (getline && !/\<\/description\>/) {}
            next
        }
        { print }
    ' "$APPCAST_PATH" > "${APPCAST_PATH}.tmp" && mv "${APPCAST_PATH}.tmp" "$APPCAST_PATH"
    
    log_success "appcast.xml description 已更新"
    
    # 重新更新 Gist（包含新的 description）
    log_step "重新更新 Gist（包含更新说明）..."
    gh gist edit "$GIST_ID" "$APPCAST_PATH" || {
        log_warning "Gist 更新失败，请手动更新"
    }
    log_success "Gist 已更新"
else
    log_warning "未获取到 Release Notes，跳过 description 更新"
fi

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
echo ""
echo "链接:"
echo "  - Release: https://github.com/$GITHUB_REPO/releases/tag/$VERSION"
echo "  - Gist:    https://gist.github.com/sunimp/$GIST_ID"
echo ""
log_success "用户现在可以通过应用内更新获取新版本！"
echo ""
