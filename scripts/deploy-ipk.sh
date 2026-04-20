#!/bin/bash
set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    echo "Uso: $0 <ip_do_roteador> <nome_do_pacote> [usuario_ssh]"
    echo "Exemplo: $0 10.0.4.123 eoip"
    echo
    echo "Variaveis opcionais:"
    echo "  ROUTER_PASS=<senha>        (padrao: r0ut3r)"
    echo "  OPENWRT_DIR=<path>         (padrao: <repo>/openwrt)"
    echo "  JOBS=<n>                   (padrao: nproc)"
    echo "  NO_CLEAN=1                 (nao roda target clean)"
    echo "  PKG_TARGET=<target_make>   (ex.: package/feeds/customfeed/eoip)"
    exit 1
fi

ROUTER_IP="$1"
PACKAGE="$2"
SSH_USER="${3:-root}"
ROUTER_PASS="${ROUTER_PASS:-r0ut3r}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OPENWRT_DIR="${OPENWRT_DIR:-$PROJECT_DIR/openwrt}"
JOBS="${JOBS:-$(nproc)}"

SSH_OPTS=(
    -o HostKeyAlgorithms=+ssh-rsa
    -o PubkeyAcceptedAlgorithms=+ssh-rsa
    -o StrictHostKeyChecking=accept-new
)
SCP_OPTS=(-O)

if ! [[ "$ROUTER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "IP invalido: $ROUTER_IP"
    exit 1
fi

if [ ! -d "$OPENWRT_DIR" ]; then
    echo "Diretorio OpenWrt nao encontrado: $OPENWRT_DIR"
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

echo "Compilando pacote '$PACKAGE' usando target '$TARGET_BASE' ..."
cd "$OPENWRT_DIR"

if [ "${NO_CLEAN:-0}" = "1" ]; then
    make "${TARGET_BASE}/compile" V=s -j"$JOBS"
else
    make "${TARGET_BASE}/clean" "${TARGET_BASE}/compile" V=s -j"$JOBS"
fi

IPK="$(find "$OPENWRT_DIR/bin/packages" -type f -name "${PACKAGE}_*.ipk" ! -name "*-dbg*" -printf '%T@ %p\n' 2>/dev/null \
    | sort -n | tail -n1 | cut -d' ' -f2-)"

if [ -z "${IPK:-}" ] || [ ! -f "$IPK" ]; then
    echo "Nao encontrei IPK para '$PACKAGE' em $OPENWRT_DIR/bin/packages"
    echo "Dica: informe o target manual com PKG_TARGET=..."
    exit 1
fi

REMOTE_IPK="/tmp/$(basename "$IPK")"

echo "Enviando IPK: $IPK -> ${SSH_USER}@${ROUTER_IP}:${REMOTE_IPK}"
if command -v sshpass >/dev/null 2>&1; then
    SSHPASS="$ROUTER_PASS" sshpass -e scp "${SCP_OPTS[@]}" "${SSH_OPTS[@]}" "$IPK" "${SSH_USER}@${ROUTER_IP}:${REMOTE_IPK}"
else
    echo "Aviso: 'sshpass' nao encontrado, sera solicitada senha no terminal."
    scp "${SCP_OPTS[@]}" "${SSH_OPTS[@]}" "$IPK" "${SSH_USER}@${ROUTER_IP}:${REMOTE_IPK}"
fi

echo "Instalando pacote no roteador ..."
REMOTE_CMD="opkg install --force-reinstall '${REMOTE_IPK}' && opkg list-installed | grep '^${PACKAGE} ' || true"
if command -v sshpass >/dev/null 2>&1; then
    SSHPASS="$ROUTER_PASS" sshpass -e ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ROUTER_IP}" "$REMOTE_CMD"
else
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ROUTER_IP}" "$REMOTE_CMD"
fi

echo "Concluido."
