#!/bin/bash
set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 4 ]; then
    echo "Usage: $0 <router_ip> <package_name> [ssh_user] [ssh_password]"
    echo "Example: $0 10.0.4.123 eoip"
    echo "Example: $0 10.0.4.123 eoip root r0ut3r"
    echo
    echo "Optional environment variables:"
    echo "  ROUTER_PASS=<password>     (default: r0ut3r)"
    echo "  OPENWRT_DIR=<path>         (default: <repo>/openwrt)"
    echo "  JOBS=<n>                   (default: nproc)"
    echo "  NO_CLEAN=1                 (skip clean target)"
    echo "  PKG_TARGET=<make_target>   (e.g.: package/feeds/customfeed/eoip)"
    exit 1
fi

ROUTER_IP="$1"
PACKAGE="$2"
SSH_USER="${3:-root}"
ROUTER_PASS="${4:-${ROUTER_PASS:-r0ut3r}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OPENWRT_DIR="${OPENWRT_DIR:-$PROJECT_DIR/openwrt}"
JOBS="${JOBS:-$(nproc)}"

SSH_OPTS=(
    -o HostKeyAlgorithms=+ssh-rsa
    -o PubkeyAcceptedAlgorithms=+ssh-rsa
    -o StrictHostKeyChecking=accept-new
)

if ! [[ "$ROUTER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "Invalid IP: $ROUTER_IP"
    exit 1
fi

if [ ! -d "$OPENWRT_DIR" ]; then
    echo "OpenWrt directory not found: $OPENWRT_DIR"
    exit 1
fi

find_pkg_target() {
    local pkg="$1"
    local makefile rel feed

    if [ -n "${PKG_TARGET:-}" ]; then
        echo "$PKG_TARGET"
        return 0
    fi

    makefile="$(find "$OPENWRT_DIR/feeds" -type f -path "*/$pkg/Makefile" | head -n1 || true)"
    if [ -n "$makefile" ]; then
        rel="${makefile#"$OPENWRT_DIR/feeds/"}"
        feed="${rel%%/*}"
        echo "package/feeds/$feed/$pkg"
        return 0
    fi

    echo "package/$pkg"
    return 0
}

TARGET_BASE="$(find_pkg_target "$PACKAGE")"

echo "Building package '$PACKAGE' using target '$TARGET_BASE' ..."
cd "$OPENWRT_DIR"

if [ "${NO_CLEAN:-0}" = "1" ]; then
    make "${TARGET_BASE}/compile" V=s -j"$JOBS"
else
    make "${TARGET_BASE}/clean" "${TARGET_BASE}/compile" V=s -j"$JOBS"
fi

IPK="$(find "$OPENWRT_DIR/bin" -type f -name "${PACKAGE}_*.ipk" ! -name "*-dbg*" -printf '%T@ %p\n' 2>/dev/null \
    | sort -n | tail -n1 | cut -d' ' -f2-)"

if [ -z "${IPK:-}" ] || [ ! -f "$IPK" ]; then
    echo "Could not find IPK for '$PACKAGE' in $OPENWRT_DIR/bin"
    echo "Tip: provide target manually with PKG_TARGET=..."
    exit 1
fi

REMOTE_IPK="/tmp/$(basename "$IPK")"

echo "Uploading IPK and installing in a single SSH session..."
REMOTE_CMD="cat > '${REMOTE_IPK}' && opkg install --force-reinstall '${REMOTE_IPK}' && opkg list-installed | grep '^${PACKAGE} ' || true"
if command -v sshpass >/dev/null 2>&1; then
    SSHPASS="$ROUTER_PASS" sshpass -e ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ROUTER_IP}" "$REMOTE_CMD" < "$IPK"
else
    echo "Warning: 'sshpass' not found, password will be requested once in terminal."
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ROUTER_IP}" "$REMOTE_CMD" < "$IPK"
fi

echo "Done."
