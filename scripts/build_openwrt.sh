#!/bin/bash
# Internal automation script for OpenWrt 18.06
set -e

# Disable interactive credential prompts for public repositories
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OPENWRT_DIR="${OPENWRT_DIR:-$PROJECT_DIR/openwrt}"
PATCH_DIR="${PATCH_DIR:-$PROJECT_DIR/patches/openwrt}"
DL_CACHE_DIR="${DL_CACHE_DIR:-/home/developer/dl_cache}"
MODE="${OWT_MODE:-normal}"
MAKE_JOBS="${OWT_MAKE_JOBS:-}"

if [ "$MODE" != "normal" ] && [ "$MODE" != "clean" ]; then
    echo "ERROR: invalid OWT_MODE '$MODE' (expected normal or clean)."
    exit 1
fi

if [ -n "$MAKE_JOBS" ] && { ! [[ "$MAKE_JOBS" =~ ^[0-9]+$ ]] || [ "$MAKE_JOBS" -le 0 ]; }; then
    echo "ERROR: invalid OWT_MAKE_JOBS '$MAKE_JOBS' (expected positive integer)."
    exit 1
fi

if [ -n "$MAKE_JOBS" ]; then
    MAKE_CMD=(make "-j$MAKE_JOBS")
else
    MAKE_CMD=(make)
fi

run_make() {
    "${MAKE_CMD[@]}" "$@"
}

# Enter local OpenWrt source tree
cd "$OPENWRT_DIR"

# Step 0: verify source tree
if [ ! -f "Makefile" ]; then
    echo "ERROR: openwrt directory is empty."
    echo "Run OpenWrt bootstrap/clone on host first."
    exit 1
fi

# Link external download cache
if [ ! -L dl ]; then
    echo "--- Linking external download cache ---"
    rm -rf dl
    ln -s "$DL_CACHE_DIR" dl
fi

if [ "$MODE" = "normal" ]; then
    echo "--- Normal mode: reusing existing workspace without cleanup/bootstrap ---"
    echo "Workspace mounted at: $OPENWRT_DIR"
    echo "Download cache at: $DL_CACHE_DIR"
    echo "Opening interactive shell."
    exec /bin/bash
fi

echo "--- Clean mode: bootstrapping from fresh clone and applying patches ---"
echo "--- Step 0.1: Applying local patches in openwrt ---"
"$PROJECT_DIR/scripts/apply-openwrt-patches.sh" "$OPENWRT_DIR" "$PATCH_DIR"

echo "--- Step 0.2: Cleaning stale customfeed metadata ---"
rm -rf feeds/customfeed feeds/customfeed.tmp feeds/customfeed.index feeds/customfeed.targetindex

echo "--- Step 1: Updating feeds ---"
./scripts/feeds update -a

echo "--- Step 2: Installing feeds ---"
./scripts/feeds install -a

echo "--- Step 3: Downloading base sources ---"
if [ ! -f .config ]; then
    run_make defconfig
fi
run_make download

echo "--- Step 4: Enabling customfeed tunnel packages ---"
# Remove legacy external eoip app integration that conflicts with current customfeed-based flow.
rm -rf feeds/luci/applications/luci-app-eoip
rm -f package/feeds/luci/luci-app-eoip
rm -rf package/openwrt-linux-eoip

# Keep config idempotent if script is rerun.
sed -i \
    -e '/^CONFIG_PACKAGE_kmod-eoip=/d' \
    -e '/^CONFIG_PACKAGE_luci-app-eoip=/d' \
    -e '/^CONFIG_PACKAGE_eoip=/d' \
    -e '/^CONFIG_PACKAGE_luci-proto-eoip=/d' \
    -e '/^CONFIG_PACKAGE_vxlan=/d' \
    -e '/^CONFIG_PACKAGE_luci-proto-vxlan=/d' \
    .config

echo "CONFIG_PACKAGE_eoip=y" >> .config
echo "CONFIG_PACKAGE_luci-proto-eoip=y" >> .config
echo "CONFIG_PACKAGE_vxlan=y" >> .config
echo "CONFIG_PACKAGE_luci-proto-vxlan=y" >> .config

run_make defconfig

echo "--- Setup completed successfully! ---"
exec /bin/bash
