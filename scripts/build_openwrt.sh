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

if [ "$MODE" != "normal" ] && [ "$MODE" != "clean" ]; then
    echo "ERROR: invalid OWT_MODE '$MODE' (expected normal or clean)."
    exit 1
fi

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

echo "--- Step 1: Updating feeds ---"
./scripts/feeds update -a

echo "--- Step 2: Installing feeds ---"
./scripts/feeds install -a

echo "--- Step 3: Downloading base sources ---"
if [ ! -f .config ]; then
    make defconfig
fi
make download

echo "--- Step 4: Installing openwrt-linux-eoip dependency (kernel module) ---"
if [ ! -d package/openwrt-linux-eoip ]; then
    git clone https://github.com/bogdik/openwrt-linux-eoip.git package/openwrt-linux-eoip
fi

echo "--- Step 5: Installing luci-app-eoip as described in README ---"
mkdir -p feeds/luci/applications/luci-app-eoip
if [ ! -d feeds/luci/applications/luci-app-eoip/.git ]; then
    git clone https://github.com/bogdik/luci-app-eoip.git feeds/luci/applications/luci-app-eoip
fi

mkdir -p package/feeds/luci/
ln -sf ../../../feeds/luci/applications/luci-app-eoip package/feeds/luci/luci-app-eoip

echo "CONFIG_PACKAGE_kmod-eoip=y" >> .config
echo "CONFIG_PACKAGE_luci-app-eoip=y" >> .config

make defconfig

echo "--- Setup completed successfully! ---"
exec /bin/bash
