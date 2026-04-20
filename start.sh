#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"

run_script() {
    local script="$1"
    shift || true

    if [ ! -x "$SCRIPTS_DIR/$script" ]; then
        echo "ERRO: script nao encontrado ou sem permissao: $SCRIPTS_DIR/$script"
        exit 1
    fi

    "$SCRIPTS_DIR/$script" "$@"
}

print_help() {
    cat <<'EOF'
Uso:
  ./start.sh                  # abre menu interativo
  ./start.sh docker [clean]   # executa build via Docker
  ./start.sh ipk <ip> <pkg> [usuario]
  ./start.sh sysupgrade <ip> [usuario]
  ./start.sh diagnose <ip> [usuario] [secao_uci_vxlan]
  ./start.sh patches          # aplica patches em openwrt
EOF
}

if [ "${1:-}" = "docker" ]; then
    shift
    run_script "docker-build.sh" "${1:-}"
    exit 0
fi

if [ "${1:-}" = "ipk" ]; then
    shift
    run_script "deploy-ipk.sh" "$@"
    exit 0
fi

if [ "${1:-}" = "sysupgrade" ]; then
    shift
    run_script "deploy-sysupgrade.sh" "$@"
    exit 0
fi

if [ "${1:-}" = "diagnose" ]; then
    shift
    run_script "vxlan-diagnose.sh" "$@"
    exit 0
fi

if [ "${1:-}" = "patches" ]; then
    run_script "apply-openwrt-patches.sh" "$ROOT_DIR/openwrt" "$ROOT_DIR/patches/openwrt"
    exit 0
fi

if [ -n "${1:-}" ]; then
    print_help
    exit 1
fi

while true; do
    cat <<'EOF'

=== OPENWRT BUILD TOOLS CLI ===
1) Docker build (normal)
2) Docker build (clean)
3) Deploy sysupgrade
4) Build+deploy IPK
5) VXLAN diagnose
6) Apply openwrt patches
7) Sair
EOF

    read -rp "Escolha uma opcao: " opt

    case "$opt" in
        1)
            run_script "docker-build.sh"
            ;;
        2)
            run_script "docker-build.sh" "clean"
            ;;
        3)
            read -rp "IP do roteador: " ip
            read -rp "Usuario SSH [root]: " user
            user="${user:-root}"
            run_script "deploy-sysupgrade.sh" "$ip" "$user"
            ;;
        4)
            read -rp "IP do roteador: " ip
            read -rp "Nome do pacote (ex: eoip): " pkg
            read -rp "Usuario SSH [root]: " user
            user="${user:-root}"
            run_script "deploy-ipk.sh" "$ip" "$pkg" "$user"
            ;;
        5)
            read -rp "IP do roteador: " ip
            read -rp "Usuario SSH [root]: " user
            user="${user:-root}"
            read -rp "Secao UCI vxlan (opcional): " sec
            if [ -n "$sec" ]; then
                run_script "vxlan-diagnose.sh" "$ip" "$user" "$sec"
            else
                run_script "vxlan-diagnose.sh" "$ip" "$user"
            fi
            ;;
        6)
            run_script "apply-openwrt-patches.sh" "$ROOT_DIR/openwrt" "$ROOT_DIR/patches/openwrt"
            ;;
        7)
            echo "Saindo."
            exit 0
            ;;
        *)
            echo "Opcao invalida."
            ;;
    esac
done
