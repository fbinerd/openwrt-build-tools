#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/load-env.sh"

OPENWRT_DIR="${1:-$PROJECT_DIR/openwrt}"
PATCH_DIR="${2:-$PROJECT_DIR/patches/openwrt}"
OPENWRT_BRANCH="${OPENWRT_BRANCH:-openwrt-25.12}"
CUSTOM_FEED_LINE="src-git-full customfeed https://github.com/fbinerd/openwrt-custom-feed.git;${OPENWRT_BRANCH}"

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
# Ensure feeds.conf exists and always includes official feeds baseline.
if [ ! -f "$OPENWRT_DIR/feeds.conf" ]; then
    if [ -f "$OPENWRT_DIR/feeds.conf.default" ]; then
        cp "$OPENWRT_DIR/feeds.conf.default" "$OPENWRT_DIR/feeds.conf"
    else
        : > "$OPENWRT_DIR/feeds.conf"
    fi
fi

# If feeds.conf does not include official LuCI feed, re-seed from feeds.conf.default.
if [ -f "$OPENWRT_DIR/feeds.conf.default" ] && ! grep -qE '^src-git[[:space:]]+luci[[:space:]]' "$OPENWRT_DIR/feeds.conf"; then
    echo "INFO: feeds.conf missing official feeds baseline; restoring from feeds.conf.default"
    cp "$OPENWRT_DIR/feeds.conf.default" "$OPENWRT_DIR/feeds.conf"
fi

sed -i \
    -e '/^src-git[[:space:]]\+nanofeed[[:space:]]/d' \
    -e '/^src-git[[:space:]]\+customfeed[[:space:]]/d' \
    -e '/^src-git-full[[:space:]]\+customfeed[[:space:]]/d' \
    "$OPENWRT_DIR/feeds.conf"

if [ "${ENABLE_CUSTOM_FEED:-0}" = "1" ] || [ "${ENABLE_CUSTOM_FEED:-}" = "true" ]; then
    printf '%s\n' "$CUSTOM_FEED_LINE" >> "$OPENWRT_DIR/feeds.conf"
    echo "feeds.conf updated with customfeed."
else
    echo "Custom feed is disabled. Skipping customfeed injection."
fi
echo "Patch processing completed successfully."
