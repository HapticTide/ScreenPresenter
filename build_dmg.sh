#!/bin/bash

# ============================================================================
# ScreenPresenter DMG 打包脚本
# ============================================================================
# 用法: ./build_dmg.sh [选项]
#
# 选项:
#   --skip-build    跳过构建步骤，直接使用已有的 .app 文件
#   --notarize      对应用进行公证（需要 Developer ID 证书）
#   --clean         清理所有构建产物
#   --help          显示帮助信息
#
# 示例:
#   ./build_dmg.sh              # 完整构建并生成 DMG（ad-hoc 签名）
#   ./build_dmg.sh --notarize   # 构建、签名、公证并生成 DMG
#   ./build_dmg.sh --skip-build # 使用已有的 .app 生成 DMG
#   ./build_dmg.sh --clean      # 清理构建产物
#
# 公证配置（使用 --notarize 时需要）:
#   需要设置以下环境变量或在下方配置：
#   - DEVELOPER_ID: Developer ID Application 证书名称
#   - APPLE_ID: Apple ID 邮箱
#   - TEAM_ID: Team ID
#   - APP_PASSWORD: App-Specific Password（或使用钥匙串）
# ============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
PROJECT_NAME="ScreenPresenter"
SCHEME_NAME="ScreenPresenter"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$PROJECT_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/Export"
APP_NAME="$PROJECT_NAME.app"
DMG_DIR="$BUILD_DIR/DMG"
DMG_NAME="$PROJECT_NAME"

# ============================================================================
# 公证配置（可选）
# ============================================================================
# 方式 1: 直接在此设置（不推荐，密码会保存在脚本中）
# DEVELOPER_ID="Developer ID Application: Your Name (XXXXXXXXXX)"
# APPLE_ID="your.email@example.com"
# TEAM_ID="XXXXXXXXXX"
# APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"

# 方式 2: 使用环境变量（推荐）
# export DEVELOPER_ID="Developer ID Application: Your Name (XXXXXXXXXX)"
# export APPLE_ID="your.email@example.com"
# export TEAM_ID="XXXXXXXXXX"
# export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"

# 方式 3: 使用钥匙串存储凭据（最安全，推荐）
# 首次运行以下命令存储凭据：
# xcrun notarytool store-credentials "ScreenPresenter-Notarize" \
#     --apple-id "your.email@example.com" \
#     --team-id "XXXXXXXXXX" \
#     --password "xxxx-xxxx-xxxx-xxxx"
# 然后设置：
# NOTARIZE_PROFILE="ScreenPresenter-Notarize"

# 钥匙串配置文件名（如果使用方式 3）
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-}"
# ============================================================================

# 从 Info.plist 获取版本号
# 优先从构建产物中读取，确保版本号与 Xcode 项目设置一致
get_version() {
    # 优先从构建产物获取版本号
    local built_plist="$EXPORT_PATH/$APP_NAME/Contents/Info.plist"
    if [ -f "$built_plist" ]; then
        /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$built_plist" 2>/dev/null && return
    fi
    
    # 备选：从源代码 Info.plist 获取
    local plist="$PROJECT_DIR/$PROJECT_NAME/Info.plist"
    if [ -f "$plist" ]; then
        /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null || echo "1.0.0"
    else
        echo "1.0.0"
    fi
}

# 从 Info.plist 获取 build number
get_build_number() {
    # 优先从构建产物获取 build number
    local built_plist="$EXPORT_PATH/$APP_NAME/Contents/Info.plist"
    if [ -f "$built_plist" ]; then
        /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$built_plist" 2>/dev/null && return
    fi
    
    # 备选：从源代码 Info.plist 获取
    local plist="$PROJECT_DIR/$PROJECT_NAME/Info.plist"
    if [ -f "$plist" ]; then
        /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist" 2>/dev/null || echo "1"
    else
        echo "1"
    fi
}

# 辅助函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助信息
show_help() {
    echo "============================================================================"
    echo "ScreenPresenter DMG 打包脚本"
    echo "============================================================================"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --skip-build    跳过构建步骤，直接使用已有的 .app 文件"
    echo "  --notarize      对应用进行公证（需要 Developer ID 证书）"
    echo "  --clean         清理所有构建产物"
    echo "  --help          显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0              # 完整构建并生成 DMG（ad-hoc 签名，本机测试用）"
    echo "  $0 --notarize   # 构建、签名、公证并生成 DMG（分发用）"
    echo "  $0 --skip-build # 使用已有的 .app 生成 DMG"
    echo "  $0 --clean      # 清理构建产物"
    echo ""
    echo "公证配置（使用 --notarize 时需要）:"
    echo ""
    echo "  方式 1: 使用环境变量"
    echo "    export DEVELOPER_ID=\"Developer ID Application: Your Name (XXXXXXXXXX)\""
    echo "    export APPLE_ID=\"your.email@example.com\""
    echo "    export TEAM_ID=\"XXXXXXXXXX\""
    echo "    export APP_PASSWORD=\"xxxx-xxxx-xxxx-xxxx\""
    echo ""
    echo "  方式 2: 使用钥匙串（推荐）"
    echo "    首次运行:"
    echo "    xcrun notarytool store-credentials \"ScreenPresenter-Notarize\" \\"
    echo "        --apple-id \"your.email@example.com\" \\"
    echo "        --team-id \"XXXXXXXXXX\" \\"
    echo "        --password \"xxxx-xxxx-xxxx-xxxx\""
    echo ""
    echo "    然后设置:"
    echo "    export NOTARIZE_PROFILE=\"ScreenPresenter-Notarize\""
    echo ""
}

# 清理构建产物
clean_build() {
    log_info "清理构建产物..."
    rm -rf "$BUILD_DIR"
    rm -rf "$PROJECT_DIR/DerivedData"
    log_success "清理完成"
}

# 生成 DMG 图标（从应用图标资源创建 icns）
generate_dmg_icon() {
    log_info "生成 DMG 图标..."
    
    ICON_DIR="$BUILD_DIR/DMGIcon.iconset"
    ICON_SRC="$PROJECT_DIR/$PROJECT_NAME/Resources/Assets.xcassets/AppIcon.appiconset"
    ICNS_PATH="$BUILD_DIR/VolumeIcon.icns"
    
    # 创建 iconset 目录
    mkdir -p "$ICON_DIR"
    
    # 复制并重命名图标文件（macOS iconset 要求的命名格式）
    cp "$ICON_SRC/icon_16x16.png" "$ICON_DIR/icon_16x16.png"
    cp "$ICON_SRC/icon_16x16@2x.png" "$ICON_DIR/icon_16x16@2x.png"
    cp "$ICON_SRC/icon_32x32.png" "$ICON_DIR/icon_32x32.png"
    cp "$ICON_SRC/icon_32x32@2x.png" "$ICON_DIR/icon_32x32@2x.png"
    cp "$ICON_SRC/icon_128x128.png" "$ICON_DIR/icon_128x128.png"
    cp "$ICON_SRC/icon_128x128@2x.png" "$ICON_DIR/icon_128x128@2x.png"
    cp "$ICON_SRC/icon_256x256.png" "$ICON_DIR/icon_256x256.png"
    cp "$ICON_SRC/icon_256x256@2x.png" "$ICON_DIR/icon_256x256@2x.png"
    cp "$ICON_SRC/icon_512x512.png" "$ICON_DIR/icon_512x512.png"
    cp "$ICON_SRC/icon_512x512@2x.png" "$ICON_DIR/icon_512x512@2x.png"
    
    # 使用 iconutil 生成 icns 文件
    iconutil -c icns "$ICON_DIR" -o "$ICNS_PATH"
    
    if [ -f "$ICNS_PATH" ]; then
        log_success "DMG 图标生成成功: $ICNS_PATH"
    else
        log_warning "DMG 图标生成失败，将使用默认图标"
    fi
    
    # 清理临时 iconset 目录
    rm -rf "$ICON_DIR"
}

# 设置 DMG 卷图标
set_dmg_icon() {
    local MOUNT_DIR="$1"
    local ICNS_PATH="$BUILD_DIR/VolumeIcon.icns"
    
    if [ ! -f "$ICNS_PATH" ]; then
        log_warning "找不到图标文件: $ICNS_PATH，跳过设置 DMG 图标"
        return
    fi
    
    log_info "设置 DMG 卷图标..."
    log_info "  源文件: $ICNS_PATH"
    log_info "  目标目录: $MOUNT_DIR"
    
    # 复制图标到卷根目录
    if cp "$ICNS_PATH" "$MOUNT_DIR/.VolumeIcon.icns"; then
        log_info "  图标文件已复制"
    else
        log_error "  复制图标文件失败"
        return
    fi
    
    # 验证文件已复制
    if [ -f "$MOUNT_DIR/.VolumeIcon.icns" ]; then
        log_info "  验证: 图标文件存在于 $MOUNT_DIR/.VolumeIcon.icns"
    else
        log_error "  验证失败: 图标文件不存在"
        return
    fi
    
    # 设置卷的自定义图标标志
    if SetFile -a C "$MOUNT_DIR"; then
        log_info "  已设置自定义图标标志"
    else
        log_warning "  设置自定义图标标志失败（SetFile）"
    fi
    
    # 同步确保写入
    sync
    
    log_success "DMG 卷图标设置完成"
}

# 为文件设置自定义图标（使用资源 fork）
set_file_icon() {
    local TARGET_FILE="$1"
    local ICNS_PATH="$BUILD_DIR/VolumeIcon.icns"
    
    if [ ! -f "$ICNS_PATH" ]; then
        log_warning "找不到图标文件，跳过设置文件图标"
        return
    fi
    
    log_info "为 DMG 文件设置自定义图标..."
    
    # 方法：使用 DeRez/Rez 将 icns 嵌入到文件的资源 fork
    # 或者使用 sips 和自定义资源
    
    # 创建临时目录
    TEMP_RSRC="$BUILD_DIR/temp_rsrc"
    mkdir -p "$TEMP_RSRC"
    
    # 使用 iconutil 需要的格式或直接用 sips
    # 更简单的方法：使用 Finder 的 AppleScript
    osascript << EOF
use framework "AppKit"
use scripting additions

set iconPath to POSIX file "$ICNS_PATH"
set targetPath to POSIX file "$TARGET_FILE"

-- 加载图标
set iconImage to current application's NSImage's alloc()'s initWithContentsOfFile:"$ICNS_PATH"

if iconImage is not missing value then
    -- 使用 NSWorkspace 设置图标
    set workspace to current application's NSWorkspace's sharedWorkspace()
    set result to workspace's setIcon:iconImage forFile:"$TARGET_FILE" options:0
    if result then
        log "图标设置成功"
    else
        log "图标设置失败"
    end if
end if
EOF
    
    # 清理
    rm -rf "$TEMP_RSRC"
    
    log_success "DMG 文件图标设置完成"
}

# ============================================================================
# 公证相关函数
# ============================================================================

# 检查公证所需的配置
check_notarize_config() {
    log_info "检查公证配置..."
    
    # 检查是否使用钥匙串配置文件
    if [ -n "$NOTARIZE_PROFILE" ]; then
        log_info "使用钥匙串配置文件: $NOTARIZE_PROFILE"
        return 0
    fi
    
    # 检查环境变量
    if [ -z "$DEVELOPER_ID" ]; then
        log_error "未设置 DEVELOPER_ID 环境变量"
        log_error "格式: Developer ID Application: Your Name (XXXXXXXXXX)"
        return 1
    fi
    
    if [ -z "$APPLE_ID" ]; then
        log_error "未设置 APPLE_ID 环境变量"
        return 1
    fi
    
    if [ -z "$TEAM_ID" ]; then
        log_error "未设置 TEAM_ID 环境变量"
        return 1
    fi
    
    if [ -z "$APP_PASSWORD" ]; then
        log_error "未设置 APP_PASSWORD 环境变量"
        log_error "请在 https://appleid.apple.com 创建 App-Specific Password"
        return 1
    fi
    
    log_success "公证配置检查通过"
    return 0
}

# 使用 Developer ID 签名应用
sign_for_distribution() {
    local APP_PATH="$1"
    
    log_info "使用 Developer ID 签名应用..."
    
    # 检查证书
    if ! security find-identity -v -p codesigning | grep -q "$DEVELOPER_ID"; then
        log_error "找不到证书: $DEVELOPER_ID"
        log_error "请确保证书已安装到钥匙串中"
        log_error "可用的签名证书:"
        security find-identity -v -p codesigning
        return 1
    fi
    
    # Entitlements 文件路径
    local ENTITLEMENTS_PATH="$PROJECT_DIR/$PROJECT_NAME/$PROJECT_NAME.entitlements"
    
    # 深度签名应用（先签名内部框架和可执行文件）
    log_info "签名内部组件..."
    
    # 签名 Frameworks
    find "$APP_PATH/Contents/Frameworks" -name "*.framework" -type d 2>/dev/null | while read framework; do
        log_info "  签名: $(basename "$framework")"
        codesign --force --options runtime \
            --sign "$DEVELOPER_ID" \
            --timestamp \
            "$framework"
    done
    
    # 签名 dylib
    find "$APP_PATH/Contents" -name "*.dylib" -type f 2>/dev/null | while read dylib; do
        log_info "  签名: $(basename "$dylib")"
        codesign --force --options runtime \
            --sign "$DEVELOPER_ID" \
            --timestamp \
            "$dylib"
    done
    
    # 签名主应用
    log_info "签名主应用..."
    codesign --force --options runtime \
        --sign "$DEVELOPER_ID" \
        --entitlements "$ENTITLEMENTS_PATH" \
        --timestamp \
        "$APP_PATH"
    
    # 验证签名
    log_info "验证签名..."
    if codesign --verify --deep --strict "$APP_PATH"; then
        log_success "签名验证通过"
    else
        log_error "签名验证失败"
        return 1
    fi
    
    # 检查 Gatekeeper
    log_info "检查 Gatekeeper 评估..."
    if spctl --assess --verbose "$APP_PATH" 2>&1; then
        log_success "Gatekeeper 评估通过"
    else
        log_warning "Gatekeeper 评估未通过（公证后将通过）"
    fi
    
    return 0
}

# 提交应用进行公证
notarize_app() {
    local DMG_PATH="$1"
    
    log_info "提交 DMG 进行公证..."
    log_info "这可能需要几分钟时间，请耐心等待..."
    
    local NOTARIZE_OUTPUT
    local SUBMISSION_ID
    
    # 使用 notarytool 提交
    if [ -n "$NOTARIZE_PROFILE" ]; then
        # 使用钥匙串配置文件
        NOTARIZE_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
            --keychain-profile "$NOTARIZE_PROFILE" \
            --wait 2>&1)
    else
        # 使用环境变量
        NOTARIZE_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
            --apple-id "$APPLE_ID" \
            --team-id "$TEAM_ID" \
            --password "$APP_PASSWORD" \
            --wait 2>&1)
    fi
    
    echo "$NOTARIZE_OUTPUT"
    
    # 检查结果
    if echo "$NOTARIZE_OUTPUT" | grep -q "status: Accepted"; then
        log_success "公证成功！"
        
        # 获取 Submission ID
        SUBMISSION_ID=$(echo "$NOTARIZE_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
        
        # 装订公证票据
        log_info "装订公证票据到 DMG..."
        if xcrun stapler staple "$DMG_PATH"; then
            log_success "公证票据装订成功"
        else
            log_warning "装订失败，但应用已经公证成功"
        fi
        
        return 0
    else
        log_error "公证失败"
        
        # 尝试获取详细日志
        SUBMISSION_ID=$(echo "$NOTARIZE_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
        if [ -n "$SUBMISSION_ID" ]; then
            log_info "获取详细公证日志..."
            if [ -n "$NOTARIZE_PROFILE" ]; then
                xcrun notarytool log "$SUBMISSION_ID" \
                    --keychain-profile "$NOTARIZE_PROFILE"
            else
                xcrun notarytool log "$SUBMISSION_ID" \
                    --apple-id "$APPLE_ID" \
                    --team-id "$TEAM_ID" \
                    --password "$APP_PASSWORD"
            fi
        fi
        
        return 1
    fi
}

# 验证公证状态
verify_notarization() {
    local DMG_PATH="$1"
    
    log_info "验证公证状态..."
    
    # 检查票据
    if xcrun stapler validate "$DMG_PATH" 2>&1 | grep -q "The validate action worked"; then
        log_success "公证票据验证通过"
        return 0
    else
        log_warning "公证票据验证失败"
        return 1
    fi
}

# ============================================================================
# 构建函数
# ============================================================================

# 构建应用
build_app() {
    log_info "开始构建 $PROJECT_NAME (Release)..."
    
    # 创建构建目录
    mkdir -p "$BUILD_DIR"
    
    # Entitlements 文件路径
    ENTITLEMENTS_PATH="$PROJECT_DIR/$PROJECT_NAME/$PROJECT_NAME.entitlements"
    
    # 构建命令
    # 使用 Xcode 项目配置的自动签名（Apple Development 证书）
    # 不再覆盖 CODE_SIGN_IDENTITY，让 Xcode 自己处理
    BUILD_CMD="xcodebuild clean build \
        -project \"$PROJECT_DIR/$PROJECT_NAME.xcodeproj\" \
        -scheme \"$SCHEME_NAME\" \
        -configuration Release \
        -derivedDataPath \"$BUILD_DIR/DerivedData\" \
        ENABLE_HARDENED_RUNTIME=YES \
        ONLY_ACTIVE_ARCH=NO"
    
    # 检查 xcpretty 是否可用，如果可用则使用它美化输出
    if command -v xcpretty &> /dev/null; then
        eval "$BUILD_CMD" | xcpretty --color
    else
        log_info "提示: 安装 xcpretty (gem install xcpretty) 可获得更简洁的构建输出"
        eval "$BUILD_CMD"
    fi
    
    # 查找构建产物
    APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "$APP_NAME" -type d | head -1)
    
    if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
        log_error "构建失败：找不到 $APP_NAME"
        exit 1
    fi
    
    # 复制到导出目录
    mkdir -p "$EXPORT_PATH"
    rm -rf "$EXPORT_PATH/$APP_NAME"
    cp -R "$APP_PATH" "$EXPORT_PATH/"
    
    # 验证签名（Xcode 应该已经正确签名了）
    log_info "验证签名..."
    codesign --verify --verbose=2 "$EXPORT_PATH/$APP_NAME"
    
    # 验证 Sparkle framework 签名
    SPARKLE_FRAMEWORK="$EXPORT_PATH/$APP_NAME/Contents/Frameworks/Sparkle.framework"
    if [ -d "$SPARKLE_FRAMEWORK" ]; then
        codesign --verify --verbose=2 "$SPARKLE_FRAMEWORK" || {
            log_error "Sparkle.framework 签名验证失败"
            exit 1
        }
    fi
    
    log_success "构建完成: $EXPORT_PATH/$APP_NAME"
}
# 创建 DMG
create_dmg() {
    log_info "创建 DMG 安装包..."
    
    APP_PATH="$EXPORT_PATH/$APP_NAME"
    
    if [ ! -d "$APP_PATH" ]; then
        log_error "找不到应用: $APP_PATH"
        log_info "请先运行不带 --skip-build 参数的脚本进行构建"
        exit 1
    fi
    
    # 卸载可能残留的 DMG 挂载
    log_info "检查并清理残留的 DMG 挂载..."
    hdiutil detach "/Volumes/$DMG_NAME" -force 2>/dev/null || true
    
    # 从构建产物获取版本号和 build number
    VERSION=$(get_version)
    BUILD_NUMBER=$(get_build_number)
    DMG_FINAL_NAME="${PROJECT_NAME}_${VERSION}_${BUILD_NUMBER}.dmg"
    log_info "检测到版本号: $VERSION, Build: $BUILD_NUMBER"
    
    # 清理旧的 DMG 目录和临时文件
    rm -rf "$DMG_DIR"
    rm -f "$BUILD_DIR/temp_$DMG_NAME.dmg"
    mkdir -p "$DMG_DIR"
    
    # 复制应用到 DMG 目录
    cp -R "$APP_PATH" "$DMG_DIR/"
    
    # 创建 Applications 文件夹的符号链接
    ln -s /Applications "$DMG_DIR/Applications"
    
    # 预先复制卷图标到 DMG 源目录（这样图标会包含在 DMG 中）
    ICNS_PATH="$BUILD_DIR/VolumeIcon.icns"
    if [ -f "$ICNS_PATH" ]; then
        cp "$ICNS_PATH" "$DMG_DIR/.VolumeIcon.icns"
        log_info "已预置卷图标文件"
    else
        log_warning "找不到图标文件: $ICNS_PATH"
    fi
    
    # 计算 DMG 大小 (应用大小 + 额外空间)
    APP_SIZE=$(du -sm "$DMG_DIR" | cut -f1)
    DMG_SIZE=$((APP_SIZE + 20))  # 额外 20MB 空间
    
    # 临时 DMG 路径
    TEMP_DMG="$BUILD_DIR/temp_$DMG_NAME.dmg"
    FINAL_DMG="$BUILD_DIR/$DMG_FINAL_NAME"
    
    # 删除旧的 DMG 文件
    rm -f "$TEMP_DMG"
    rm -f "$FINAL_DMG"
    
    log_info "创建临时 DMG (大小: ${DMG_SIZE}MB)..."
    
    # 创建空白 DMG
    hdiutil create \
        -size ${DMG_SIZE}m \
        -volname "$DMG_NAME" \
        -fs HFS+ \
        -fsargs "-c c=64,a=16,e=16" \
        "$TEMP_DMG"
    
    # 挂载临时 DMG
    log_info "挂载并配置 DMG..."
    MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG" | grep "/Volumes/" | sed 's/.*\/Volumes/\/Volumes/')
    
    if [ -z "$MOUNT_DIR" ]; then
        log_error "挂载 DMG 失败"
        exit 1
    fi
    
    log_info "DMG 挂载于: $MOUNT_DIR"
    
    # 复制所有文件到挂载的 DMG（包括隐藏文件）
    log_info "复制文件到 DMG..."
    cp -R "$DMG_DIR"/* "$MOUNT_DIR/" 2>/dev/null || true
    cp -R "$DMG_DIR"/.[!.]* "$MOUNT_DIR/" 2>/dev/null || true
    
    # 验证图标文件
    if [ -f "$MOUNT_DIR/.VolumeIcon.icns" ]; then
        log_info "图标文件已复制到 DMG"
        # 设置卷的自定义图标标志
        log_info "设置卷自定义图标标志..."
        SetFile -a C "$MOUNT_DIR"
        log_success "卷图标设置完成"
    else
        log_warning "图标文件未能复制到 DMG"
    fi
    
    # 设置 DMG 窗口属性 (使用 AppleScript)
    log_info "配置 DMG 窗口样式..."
    
    # 等待 Finder 识别卷
    sleep 2
    
    # 使用 AppleScript 设置 DMG 窗口属性
    osascript <<EOF
    tell application "Finder"
        tell disk "$DMG_NAME"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {400, 100, 900, 450}
            set viewOptions to the icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 80
            
            -- 设置图标位置
            set position of item "$APP_NAME" of container window to {130, 180}
            set position of item "Applications" of container window to {370, 180}
            
            close
            open
            update without registering applications
            delay 2
        end tell
    end tell
EOF
    
    # 同步并等待
    sync
    sleep 3
    
    # AppleScript 可能会导致文件系统变化，需要重新复制图标并设置标志
    log_info "设置卷图标..."
    ICNS_PATH="$BUILD_DIR/VolumeIcon.icns"
    if [ -f "$ICNS_PATH" ]; then
        cp "$ICNS_PATH" "$MOUNT_DIR/.VolumeIcon.icns"
        SetFile -a C "$MOUNT_DIR"
        sync
        log_success "卷图标设置完成"
    fi
    
    # 卸载 DMG
    log_info "卸载临时 DMG..."
    hdiutil detach "$MOUNT_DIR" -force || {
        sleep 5
        hdiutil detach "$MOUNT_DIR" -force
    }
    
    # 压缩 DMG
    log_info "压缩最终 DMG..."
    hdiutil convert "$TEMP_DMG" \
        -format UDZO \
        -imagekey zlib-level=9 \
        -o "$FINAL_DMG"
    
    # 清理临时文件
    rm -f "$TEMP_DMG"
    rm -rf "$DMG_DIR"
    
    # 为 DMG 文件本身设置自定义图标
    set_file_icon "$FINAL_DMG"
    
    # 显示结果
    DMG_SIZE_FINAL=$(du -h "$FINAL_DMG" | cut -f1)
    
    log_success "============================================"
    log_success "DMG 创建成功!"
    log_success "============================================"
    log_success "文件: $FINAL_DMG"
    log_success "大小: $DMG_SIZE_FINAL"
    log_success "============================================"
    
    # 打开 Finder 显示 DMG 文件
    open -R "$FINAL_DMG"
}

# 主函数
main() {
    echo ""
    echo "============================================"
    echo "  $PROJECT_NAME DMG 打包工具"
    echo "============================================"
    echo ""
    
    SKIP_BUILD=false
    DO_NOTARIZE=false
    
    # 解析参数
    for arg in "$@"; do
        case $arg in
            --skip-build)
                SKIP_BUILD=true
                ;;
            --notarize)
                DO_NOTARIZE=true
                ;;
            --clean)
                clean_build
                exit 0
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_warning "未知参数: $arg"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 检查 Xcode 命令行工具
    if ! command -v xcodebuild &> /dev/null; then
        log_error "xcodebuild 未找到，请安装 Xcode 命令行工具"
        exit 1
    fi
    
    # 如果需要公证，先检查配置
    if [ "$DO_NOTARIZE" = true ]; then
        if ! check_notarize_config; then
            log_error "公证配置检查失败，退出"
            exit 1
        fi
    fi
    
    # 执行构建流程
    if [ "$SKIP_BUILD" = false ]; then
        build_app
    else
        log_info "跳过构建步骤..."
    fi
    
    # 如果需要公证，使用 Developer ID 重新签名
    if [ "$DO_NOTARIZE" = true ]; then
        if ! sign_for_distribution "$EXPORT_PATH/$APP_NAME"; then
            log_error "Developer ID 签名失败，退出"
            exit 1
        fi
    fi
    
    # 生成 DMG 图标
    generate_dmg_icon
    
    # 创建 DMG
    create_dmg
    
    # 如果需要公证，提交 DMG 进行公证
    if [ "$DO_NOTARIZE" = true ]; then
        # 获取 DMG 路径
        VERSION=$(get_version)
        BUILD_NUMBER=$(get_build_number)
        DMG_FINAL_NAME="${DMG_NAME}_${VERSION}_${BUILD_NUMBER}.dmg"
        FINAL_DMG="$BUILD_DIR/$DMG_FINAL_NAME"
        
        if ! notarize_app "$FINAL_DMG"; then
            log_error "公证失败"
            exit 1
        fi
        
        # 验证公证
        verify_notarization "$FINAL_DMG"
        
        log_success "============================================"
        log_success "公证完成！DMG 已准备好分发"
        log_success "============================================"
    fi
}

# 运行主函数
main "$@"

