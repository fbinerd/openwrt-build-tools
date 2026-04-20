#!/bin/bash
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Uso: $0 <ip_do_roteador> [usuario_ssh]"
    echo "Exemplo: $0 10.0.4.123"
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
    echo "IP invalido: $ROUTER_IP"
    exit 1
fi

if [ ! -f "$IMAGE" ]; then
    echo "Imagem nao encontrada:"
    echo "  $IMAGE"
    exit 1
fi

echo "Enviando firmware para ${SSH_USER}@${ROUTER_IP}:${REMOTE_IMAGE} ..."
if command -v sshpass >/dev/null 2>&1; then
    SSHPASS="$ROUTER_PASS" sshpass -e scp "${SCP_OPTS[@]}" "${SSH_OPTS[@]}" "$IMAGE" "${SSH_USER}@${ROUTER_IP}:${REMOTE_IMAGE}"
else
    echo "Aviso: 'sshpass' nao encontrado, sera solicitada senha no terminal."
    scp "${SCP_OPTS[@]}" "${SSH_OPTS[@]}" "$IMAGE" "${SSH_USER}@${ROUTER_IP}:${REMOTE_IMAGE}"
fi

echo "Executando sysupgrade com preservacao de configuracoes (-c)..."
if command -v sshpass >/dev/null 2>&1; then
    SSHPASS="$ROUTER_PASS" sshpass -e ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ROUTER_IP}" "sysupgrade -c '${REMOTE_IMAGE}'"
else
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ROUTER_IP}" "sysupgrade -c '${REMOTE_IMAGE}'"
fi

echo "Comando enviado. O roteador deve reiniciar em seguida."
