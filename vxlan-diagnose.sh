#!/bin/bash
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 3 ]; then
    echo "Uso: $0 <ip_do_roteador> [usuario_ssh] [secao_uci_vxlan]"
    echo "Exemplo: $0 10.0.4.123"
    echo "Exemplo: $0 10.0.4.123 root vxlan"
    exit 1
fi

ROUTER_IP="$1"
SSH_USER="${2:-root}"
UCI_SECTION="${3:-}"
ROUTER_PASS="${ROUTER_PASS:-r0ut3r}"

SSH_OPTS=(
    -o HostKeyAlgorithms=+ssh-rsa
    -o PubkeyAcceptedAlgorithms=+ssh-rsa
    -o StrictHostKeyChecking=accept-new
)

REPORT_DIR="/media/storage/opw1/reports"
mkdir -p "$REPORT_DIR"
TS="$(date +%Y%m%d-%H%M%S)"
REPORT_FILE="$REPORT_DIR/vxlan-diagnose-${ROUTER_IP}-${TS}.txt"

run_ssh() {
    if command -v sshpass >/dev/null 2>&1; then
        SSHPASS="$ROUTER_PASS" sshpass -e ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ROUTER_IP}" "$@"
    else
        ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ROUTER_IP}" "$@"
    fi
}

collect_remote() {
    run_ssh "sh -s -- '$UCI_SECTION'" <<'EOSH'
set -eu
REQ_SECTION="${1:-}"

echo "===== SYSTEM ====="
date
uname -a
ubus call system board 2>/dev/null || true
echo

echo "===== PACKAGES ====="
opkg list-installed | grep -E '(^kmod-vxlan|^vxlan|vxlan-nano|luci-proto-vxlan)' || true
echo

echo "===== VXLAN PROTO SCRIPT ====="
ls -l /lib/netifd/proto/vxlan.sh 2>/dev/null || echo "missing: /lib/netifd/proto/vxlan.sh"
head -n 220 /lib/netifd/proto/vxlan.sh 2>/dev/null || true
echo

echo "===== NETWORK VXLAN UCI ====="
uci show network | grep -E "proto='vxlan'|\\.peeraddr=|\\.ipaddr=|\\.remote=|\\.local=|\\.vid=|\\.vni=|\\.port=|\\.tunlink=|\\.ifname=|\\.bridge=|\\.ttl=|\\.tos=|\\.rxcsum=|\\.txcsum=|\\.dst=|\\.src=" || true
echo

SECTIONS="$(uci show network | sed -n "s/^network\.\([^.]*\)\.proto='vxlan'/\1/p")"

if [ -n "$REQ_SECTION" ]; then
    SECTIONS="$REQ_SECTION"
fi

if [ -z "$SECTIONS" ]; then
    echo "===== IFSTATUS ====="
    echo "No UCI sections with proto=vxlan found"
    echo
else
    for s in $SECTIONS; do
        echo "===== IFSTATUS: $s ====="
        ifstatus "$s" 2>&1 || true
        echo

        REMOTE="$(uci -q get network.$s.peeraddr || true)"
        [ -z "$REMOTE" ] && REMOTE="$(uci -q get network.$s.remote || true)"
        [ -z "$REMOTE" ] && REMOTE="$(uci -q get network.$s.dst || true)"
        if [ -n "$REMOTE" ]; then
            echo "===== ROUTE GET: $s remote=$REMOTE ====="
            ip route get "$REMOTE" 2>&1 || true
            echo
        fi
    done
fi

echo "===== LINK STATE ====="
ip link show 2>/dev/null | grep -E 'vxlan|zevx|vxlan-' || true
echo

echo "===== ROUTES ====="
ip route show 2>/dev/null || true
echo

echo "===== LOGREAD VXLAN ====="
logread | grep -Ei 'vxlan|customfeed|netifd|MISSING_ADDRESS|NO_WAN_LINK|VXLAN_' || true
echo

echo "===== DMESG VXLAN ====="
dmesg | grep -Ei 'vxlan|netlink|rtnl' || true
echo
EOSH
}

analyze_report() {
    local f="$1"
    local problems=0
    local current_errors=0

    echo
    echo "===== DIAGNOSTICO AUTOMATICO ====="

    if ! grep -q "/lib/netifd/proto/vxlan.sh" "$f"; then
        echo "- Falta o script de protocolo: /lib/netifd/proto/vxlan.sh"
        problems=$((problems + 1))
    fi

    if ! grep -q "^kmod-vxlan" "$f"; then
        echo "- kmod-vxlan parece ausente (modulo kernel necessario)"
        problems=$((problems + 1))
    fi

    if grep -q "No UCI sections with proto=vxlan found" "$f"; then
        echo "- Nao existe secao UCI com proto=vxlan"
        problems=$((problems + 1))
    fi

    if grep -q '"code": "MISSING_ADDRESS"' "$f"; then
        echo "- Erro atual MISSING_ADDRESS: peeraddr/remote nao configurado"
        problems=$((problems + 1))
        current_errors=$((current_errors + 1))
    fi

    if grep -q '"code": "NO_WAN_LINK"' "$f"; then
        echo "- Erro atual NO_WAN_LINK: tunlink/rota underlay indisponivel"
        problems=$((problems + 1))
        current_errors=$((current_errors + 1))
    fi

    if grep -q '"code": "VXLAN_DNS_RESOLVE_FAILED"' "$f"; then
        echo "- Erro atual VXLAN_DNS_RESOLVE_FAILED: hostname do peer nao resolvido"
        problems=$((problems + 1))
        current_errors=$((current_errors + 1))
    fi

    if grep -q '"up": false' "$f"; then
        echo "- Estado atual: existe secao vxlan com up=false (ver bloco IFSTATUS)"
        problems=$((problems + 1))
        current_errors=$((current_errors + 1))
    fi

    if grep -qE "network\\.[^.]+\\.proto='vxlan'" "$f" && grep -qE "network\\.[^.]+\\.ifname='[^']+'" "$f" && ! grep -q "proto_config_add_string \"ifname\"" "$f"; then
        echo "- option ifname definida mas o backend /lib/netifd/proto/vxlan.sh nao suporta ifname"
        problems=$((problems + 1))
    fi

    if grep -qE "network\\.[^.]+\\.proto='vxlan'" "$f" && grep -qE "network\\.[^.]+\\.tunlink='br-" "$f"; then
        echo "- Aviso: tunlink usa device bridge (br-*). Prefira interface logica UCI (ex: 'lan'/'wwan')."
    fi

    if [ "$problems" -eq 0 ]; then
        echo "- Nao achei erro obvio por regex; revisar IFSTATUS e LOGREAD no relatorio."
    elif [ "$current_errors" -eq 0 ]; then
        echo "- Observacao: alertas vieram de heuristicas/historico; sem codigo de erro atual no IFSTATUS."
    fi
}

echo "Coletando diagnostico de VXLAN em ${SSH_USER}@${ROUTER_IP} ..."
if ! collect_remote >"$REPORT_FILE"; then
    echo "Falha ao coletar diagnostico remoto."
    exit 1
fi

echo "Relatorio salvo em:"
echo "  $REPORT_FILE"

analyze_report "$REPORT_FILE"
