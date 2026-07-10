#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/load-env.sh"
OPENWRT_CONFIG="${OPENWRT_CONFIG:-$PROJECT_DIR/openwrt/.config}"
DEST_DIR="${DEST_DIR:-$PROJECT_DIR/router-configs}"

if [ ! -f "$OPENWRT_CONFIG" ]; then
    echo "ERROR: OpenWrt .config not found: $OPENWRT_CONFIG"
    exit 1
fi

mkdir -p "$DEST_DIR"

profile="$(sed -n 's/^CONFIG_TARGET_PROFILE="\(.*\)"/\1/p' "$OPENWRT_CONFIG" | head -n1)"
device="${profile#DEVICE_}"

board="$(sed -n 's/^CONFIG_TARGET_BOARD="\(.*\)"/\1/p' "$OPENWRT_CONFIG" | head -n1)"
subtarget="$(sed -n 's/^CONFIG_TARGET_SUBTARGET="\(.*\)"/\1/p' "$OPENWRT_CONFIG" | head -n1)"

if [ -z "$device" ] || [ "$device" = "$profile" ]; then
    if [ -n "$board" ] && [ -n "$subtarget" ]; then
        device="${board}-${subtarget}"
    elif [ -n "$board" ]; then
        device="$board"
    else
        device="unknown-device"
    fi
fi

device="$(printf '%s' "$device" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//')"

detect_brand() {
    case "$1" in
        tl-*|archer-*|cpe-*|re-*|wa-*|wr-*|mr-*) echo "tplink" ;;
        rb*|hap-*|hex-*|wap-*|mAP-*|cAP-*|routerboard-*) echo "mikrotik" ;;
        dir-*|dwr-*|dap-*) echo "dlink" ;;
        wrt*|ea*|x*ac*) echo "linksys" ;;
        wnr*|wndr*|r6*|r7*|r8*) echo "netgear" ;;
        whr-*|wzr-*) echo "buffalo" ;;
        gl-*) echo "glinet" ;;
        *) echo "openwrt" ;;
    esac
}

brand="$(detect_brand "$device")"
outfile="$DEST_DIR/${brand}_${device}.config"

cp "$OPENWRT_CONFIG" "$outfile"
echo "Router config backup created:"
echo "  $outfile"
