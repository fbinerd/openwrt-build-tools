#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OPENWRT_DIR="${1:-$PROJECT_DIR/openwrt}"
PATCH_DIR="${2:-$PROJECT_DIR/patches/openwrt}"
CUSTOM_FEED_LINE="src-git customfeed https://github.com/fbinerd/openwrt-custom-feed.git;openwrt-18.06"

if [ ! -d "$OPENWRT_DIR" ]; then
    echo "ERROR: OpenWrt directory not found: $OPENWRT_DIR"
    exit 1
fi

if [ ! -d "$PATCH_DIR" ]; then
    echo "INFO: patch directory not found: $PATCH_DIR"
fi

# 1) Apply patches (if any)
shopt -s nullglob
PATCHES=( "$PATCH_DIR"/*.patch )
shopt -u nullglob

if [ ${#PATCHES[@]} -gt 0 ]; then
    echo "Applying patches from $PATCH_DIR ..."
    for p in "${PATCHES[@]}"; do
        patch_name="$(basename "$p")"
        echo "- Patch: $patch_name"

        if (cd "$OPENWRT_DIR" && patch --dry-run -p1 < "$p" >/dev/null 2>&1); then
            (cd "$OPENWRT_DIR" && patch -p1 < "$p" >/dev/null)
            echo "  applied"
            continue
        fi

        if (cd "$OPENWRT_DIR" && patch -R --dry-run -p1 < "$p" >/dev/null 2>&1); then
            echo "  already applied (skip)"
            continue
        fi

        echo "ERROR: failed to apply $p"
        (cd "$OPENWRT_DIR" && patch --dry-run -p1 < "$p") || true
        exit 1
    done
else
    echo "INFO: no patches found in $PATCH_DIR"
fi

# 2) Never modify feeds.conf.default.
# Only ensure feeds.conf contains the custom feed.
if [ ! -f "$OPENWRT_DIR/feeds.conf" ]; then
    if [ -f "$OPENWRT_DIR/feeds.conf.default" ]; then
        cp "$OPENWRT_DIR/feeds.conf.default" "$OPENWRT_DIR/feeds.conf"
    else
        : > "$OPENWRT_DIR/feeds.conf"
    fi
fi

sed -i \
    -e '/^src-git[[:space:]]\+nanofeed[[:space:]]/d' \
    -e '/^src-git[[:space:]]\+customfeed[[:space:]]/d' \
    "$OPENWRT_DIR/feeds.conf"
printf '%s\n' "$CUSTOM_FEED_LINE" >> "$OPENWRT_DIR/feeds.conf"

echo "feeds.conf updated with customfeed."
echo "Patch processing completed successfully."
