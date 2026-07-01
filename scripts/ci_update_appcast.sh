#!/bin/bash

#
# ci_update_appcast.sh
# ScreenPresenter
#
# Created by Sun on 2026/7/1.
#
# CI 用 appcast 更新器（参数化，不依赖本地环境）
#
# 就地更新仓库内 appcast.xml 的单个 item：
#   - sparkle:edSignature / length（Sparkle Ed25519 签名与包大小）
#   - sparkle:version（构建号，Sparkle 的升级判据，必须单调递增）
#   - sparkle:shortVersionString / <title>（展示版本号）
#   - <pubDate>（发布时间，RFC 2822）
#   - <enclosure url>（GitHub Release 下载直链）
#   - CDATA 描述（版本标题 + 发布说明列表）
#
# 用法（全部通过环境变量传参，避免命令行泄露）：
#   APPCAST_PATH=appcast.xml \
#   VERSION=1.2.1 BUILD_NUMBER=202607011014 \
#   ED_SIGNATURE=... LENGTH=15206425 \
#   DOWNLOAD_URL=https://github.com/.../ScreenPresenter-1.2.1.zip \
#   NOTES_FILE=/path/to/notes.txt \
#   ./scripts/ci_update_appcast.sh
#

set -euo pipefail

# ============================================
# 参数校验
# ============================================
: "${APPCAST_PATH:?需要 APPCAST_PATH}"
: "${VERSION:?需要 VERSION}"
: "${BUILD_NUMBER:?需要 BUILD_NUMBER}"
: "${ED_SIGNATURE:?需要 ED_SIGNATURE}"
: "${LENGTH:?需要 LENGTH}"
: "${DOWNLOAD_URL:?需要 DOWNLOAD_URL}"
NOTES_FILE="${NOTES_FILE:-}"

if [ ! -f "$APPCAST_PATH" ]; then
    echo "❌ 找不到 appcast 文件: $APPCAST_PATH" >&2
    exit 1
fi

PUB_DATE="$(LC_ALL=C date -R 2>/dev/null || LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')"

# 跨平台就地替换（BSD sed 需要 -i ''，GNU sed 用 -i）
sed_inplace() {
    if sed --version >/dev/null 2>&1; then
        sed -i "$@"
    else
        sed -i '' "$@"
    fi
}

# 转义 sed 替换串中的分隔符与特殊字符（用 | 作分隔符）
escape_repl() {
    printf '%s' "$1" | sed -e 's/[&|]/\\&/g'
}
# ============================================
# 更新标量字段
# ============================================
ED_SIGNATURE_ESC="$(escape_repl "$ED_SIGNATURE")"
DOWNLOAD_URL_ESC="$(escape_repl "$DOWNLOAD_URL")"
PUB_DATE_ESC="$(escape_repl "$PUB_DATE")"

# 签名与长度
sed_inplace "s|sparkle:edSignature=\"[^\"]*\"|sparkle:edSignature=\"$ED_SIGNATURE_ESC\"|g" "$APPCAST_PATH"
sed_inplace "s|length=\"[^\"]*\"|length=\"$LENGTH\"|g" "$APPCAST_PATH"

# 构建号（升级判据）与展示版本号
sed_inplace "s|<sparkle:version>[^<]*</sparkle:version>|<sparkle:version>$BUILD_NUMBER</sparkle:version>|g" "$APPCAST_PATH"
sed_inplace "s|<sparkle:shortVersionString>[^<]*</sparkle:shortVersionString>|<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>|g" "$APPCAST_PATH"

# item 标题与发布时间
sed_inplace "s|<title>Version [^<]*</title>|<title>Version $VERSION</title>|g" "$APPCAST_PATH"
sed_inplace "s|<pubDate>[^<]*</pubDate>|<pubDate>$PUB_DATE_ESC</pubDate>|g" "$APPCAST_PATH"

# enclosure 下载直链（兼容旧的 api.github.com / github.com 两种历史写法）
sed_inplace "s|url=\"https://api.github.com/repos/[^\"]*/releases/assets/[0-9]*\"|url=\"$DOWNLOAD_URL_ESC\"|g" "$APPCAST_PATH"
sed_inplace "s|url=\"https://github.com/[^\"]*/releases/download/[^\"]*\"|url=\"$DOWNLOAD_URL_ESC\"|g" "$APPCAST_PATH"

# CDATA 描述里的版本号（形如 “ScreenPresenter 1.2.0”）
sed_inplace "s/ScreenPresenter [0-9][0-9.]*</ScreenPresenter $VERSION</g" "$APPCAST_PATH"

# ============================================
# 重建 CDATA 里的更新条目列表（仅当提供 NOTES_FILE）
# NOTES_FILE 每行一条更新说明（不含前导 "- "）
# ============================================
if [ -n "$NOTES_FILE" ] && [ -f "$NOTES_FILE" ]; then
    # XML 转义（顺序：& 必须最先）
    escape_xml() {
        local t="$1"
        t="${t//&/&amp;}"
        t="${t//</&lt;}"
        t="${t//>/&gt;}"
        printf '%s' "$t"
    }

    # 生成新的 <ul>...</ul> 列表内容（写入临时文件供 awk 读取）
    li_tmp="$(mktemp)"
    while IFS= read -r line; do
        # 去掉可能存在的前导 "- " 和首尾空白
        line="${line#- }"
        line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -z "$line" ] && continue
        printf '                    <li>%s</li>\n' "$(escape_xml "$line")" >> "$li_tmp"
    done < "$NOTES_FILE"

    # 若没有任何有效条目，兜底一条，避免生成空 <ul>
    if [ ! -s "$li_tmp" ]; then
        printf '                    <li>常规维护与稳定性优化</li>\n' >> "$li_tmp"
    fi

    # 用新列表替换 <ul> 与 </ul> 之间的旧 <li> 行
    out_tmp="$(mktemp)"
    awk -v lifile="$li_tmp" '
        BEGIN { in_ul = 0 }
        /<ul>/ {
            print
            in_ul = 1
            while ((getline l < lifile) > 0) print l
            close(lifile)
            next
        }
        /<\/ul>/ { in_ul = 0; print; next }
        { if (!in_ul) print }
    ' "$APPCAST_PATH" > "$out_tmp"
    mv "$out_tmp" "$APPCAST_PATH"
    rm -f "$li_tmp"
fi

echo "✅ appcast.xml 已更新：version=$VERSION build=$BUILD_NUMBER length=$LENGTH"
