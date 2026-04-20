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
IMAGE="$PROJECT_DIR/openwrt/bin/targets/ar71xx/tiny/openwrt-ar71xx-tiny-tl-wr740n-v6-squashfs-sysupgrade.bin"
REMOTE_IMAGE="/tmp/$(basename "$IMAGE")"
SSH_OPTS=(
    -o HostKeyAlgorithms=+ssh-rsa
    -o PubkeyAcceptedAlgorithms=+ssh-rsa
    -o StrictHostKeyChecking=accept-new
)

if ! [[ "$ROUTER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "Invalid IP: $ROUTER_IP"
    exit 1
fi

if [ ! -f "$IMAGE" ]; then
    echo "Image not found:"
    echo "  $IMAGE"
    exit 1
fi

echo "Uploading firmware and running sysupgrade in a single SSH session..."
REMOTE_CMD="cat > '${REMOTE_IMAGE}' && sysupgrade -c '${REMOTE_IMAGE}'"
if command -v sshpass >/dev/null 2>&1; then
    SSHPASS="$ROUTER_PASS" sshpass -e ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ROUTER_IP}" "$REMOTE_CMD" < "$IMAGE"
else
    echo "Warning: 'sshpass' not found, password will be requested once in terminal."
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ROUTER_IP}" "$REMOTE_CMD" < "$IMAGE"
fi

echo "Command sent. Router should reboot next."
