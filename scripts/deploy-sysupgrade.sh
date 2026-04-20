#!/bin/bash
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <router_ip> [ssh_user]"
    echo "Example: $0 10.0.4.123"
    exit 1
fi

ROUTER_IP="$1"
SSH_USER="${2:-root}"
ROUTER_PASS="${ROUTER_PASS:-r0ut3r}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE="$PROJECT_DIR/openwrt/bin/targets/ar71xx/tiny/openwrt-ar71xx-tiny-tl-wr740n-v6-squashfs-sysupgrade.bin"
REMOTE_IMAGE="/tmp/$(basename "$IMAGE")"
SSH_OPTS=(
    -o HostKeyAlgorithms=+ssh-rsa
    -o PubkeyAcceptedAlgorithms=+ssh-rsa
    -o StrictHostKeyChecking=accept-new
)
SCP_OPTS=(
    -O
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

echo "Uploading firmware to ${SSH_USER}@${ROUTER_IP}:${REMOTE_IMAGE} ..."
if command -v sshpass >/dev/null 2>&1; then
    SSHPASS="$ROUTER_PASS" sshpass -e scp "${SCP_OPTS[@]}" "${SSH_OPTS[@]}" "$IMAGE" "${SSH_USER}@${ROUTER_IP}:${REMOTE_IMAGE}"
else
    echo "Warning: 'sshpass' not found, password will be requested in terminal."
    scp "${SCP_OPTS[@]}" "${SSH_OPTS[@]}" "$IMAGE" "${SSH_USER}@${ROUTER_IP}:${REMOTE_IMAGE}"
fi

echo "Running sysupgrade with config preservation (-c) ..."
if command -v sshpass >/dev/null 2>&1; then
    SSHPASS="$ROUTER_PASS" sshpass -e ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ROUTER_IP}" "sysupgrade -c '${REMOTE_IMAGE}'"
else
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ROUTER_IP}" "sysupgrade -c '${REMOTE_IMAGE}'"
fi

echo "Command sent. Router should reboot next."
