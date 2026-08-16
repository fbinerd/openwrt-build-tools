#!/bin/bash
# Non-interactive build for GitHub Actions: same bootstrap as build_openwrt.sh's
# clean mode (patches, feeds, download), but ends in a real `make` instead of
# an interactive shell, and copies a named router-configs/*.config in first.
set -e

export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OPENWRT_DIR="${OPENWRT_DIR:-$PROJECT_DIR/openwrt}"
PATCH_DIR="${PATCH_DIR:-$PROJECT_DIR/patches/openwrt}"
DL_CACHE_DIR="${DL_CACHE_DIR:-/home/developer/dl_cache}"
MAKE_JOBS="${OWT_MAKE_JOBS:-$(nproc)}"
DEVICE_CONFIG="${DEVICE_CONFIG:?ERROR: set DEVICE_CONFIG to a router-configs/*.config path}"

run_make() {
    make -j"$MAKE_JOBS" "$@"
}

cd "$OPENWRT_DIR"

if [ ! -f Makefile ]; then
    echo "ERROR: openwrt directory is empty."
    exit 1
fi

if [ ! -L dl ]; then
    echo "--- Linking external download cache ---"
    rm -rf dl
    ln -s "$DL_CACHE_DIR" dl
fi

echo "--- Step 0.1: Applying local patches ---"
"$PROJECT_DIR/scripts/apply-openwrt-patches.sh" "$OPENWRT_DIR" "$PATCH_DIR"

echo "--- Step 0.2: Cleaning stale customfeed metadata ---"
rm -rf feeds/customfeed feeds/customfeed.tmp feeds/customfeed.index feeds/customfeed.targetindex

echo "--- Step 1: Updating feeds ---"
./scripts/feeds update -a

echo "--- Step 2: Installing feeds ---"
./scripts/feeds install -a

echo "--- Step 3: Applying device .config ($DEVICE_CONFIG) ---"
cp "$PROJECT_DIR/$DEVICE_CONFIG" .config
run_make defconfig

echo "--- Step 4: Downloading sources ---"
run_make download

echo "--- Step 5: Building (V=s, -j$MAKE_JOBS) ---"
run_make V=s

echo "--- Build finished ---"
find bin/targets -maxdepth 2 -type f | sort
