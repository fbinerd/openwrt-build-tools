#!/bin/bash
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 3 ]; then
    echo "Usage: $0 <router_ip> [ssh_user] [ssh_password]"
    echo "Example: $0 10.0.4.123"
    echo "Example: $0 10.0.4.123 root r0ut3r"
    exit 1
fi

ROUTER_IP="$1"
SSH_USER="${2:-root}"
ROUTER_PASS="${3:-${ROUTER_PASS:-r0ut3r}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SSH_OPTS=(
    -o HostKeyAlgorithms=+ssh-rsa
    -o PubkeyAcceptedAlgorithms=+ssh-rsa
    -o StrictHostKeyChecking=accept-new
)

if ! [[ "$ROUTER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "Invalid IP: $ROUTER_IP"
    exit 1
fi

IMAGE="${IMAGE:-}"
if [ -z "$IMAGE" ]; then
    IMAGE="$(find "$PROJECT_DIR/openwrt/bin/targets" -type f \( -name "*sysupgrade.bin" -o -name "*sysupgrade.img" -o -name "*sysupgrade.tar" -o -name "*combined-squashfs.img.gz" -o -name "*sysupgrade.img.gz" \) -printf '%T@ %p\n' 2>/dev/null \
        | sort -n | tail -n1 | cut -d' ' -f2- || true)"
fi

if [ -z "$IMAGE" ] || [ ! -f "$IMAGE" ]; then
    echo "ERROR: Sysupgrade image not found in openwrt/bin/targets/."
    echo "Please specify the image path explicitly using IMAGE=... $0 ..."
    exit 1
fi

REMOTE_IMAGE="/tmp/$(basename "$IMAGE")"

echo "Uploading firmware and running sysupgrade in a single SSH session..."
REMOTE_CMD="cat > '${REMOTE_IMAGE}' && sysupgrade -c '${REMOTE_IMAGE}'"
if command -v sshpass >/dev/null 2>&1; then
    SSHPASS="$ROUTER_PASS" sshpass -e ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ROUTER_IP}" "$REMOTE_CMD" < "$IMAGE"
else
    echo "Warning: 'sshpass' not found, password will be requested once in terminal."
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ROUTER_IP}" "$REMOTE_CMD" < "$IMAGE"
fi

echo "Command sent. Router should reboot next."
