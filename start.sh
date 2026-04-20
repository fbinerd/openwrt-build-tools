#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"

run_script() {
    local script="$1"
    shift || true

    if [ ! -x "$SCRIPTS_DIR/$script" ]; then
        echo "ERROR: script not found or not executable: $SCRIPTS_DIR/$script"
        exit 1
    fi

    "$SCRIPTS_DIR/$script" "$@"
}

print_help() {
    cat <<'EOT'
Usage:
  ./start.sh                  # open interactive menu
  ./start.sh docker [normal|clean] [router_name_or_config_file]
  ./start.sh ipk <ip> <pkg> [user]
  ./start.sh sysupgrade <ip> [user]
  ./start.sh diagnose <ip> [user] [vxlan_uci_section]
  ./start.sh patches          # apply patches in openwrt
EOT
}

if [ "${1:-}" = "docker" ]; then
    shift
    run_script "docker-build.sh" "$@"
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
    cat <<'EOT'

=== OPENWRT BUILD TOOLS CLI ===
1) Docker build (normal)
2) Docker build (clean)
3) Deploy sysupgrade
4) Build + deploy IPK
5) VXLAN diagnose
6) Apply openwrt patches
7) Exit
EOT

    read -rp "Choose an option: " opt

    case "$opt" in
        1)
            run_script "docker-build.sh"
            ;;
        2)
            run_script "docker-build.sh" "clean"
            ;;
        3)
            read -rp "Router IP: " ip
            read -rp "SSH user [root]: " user
            user="${user:-root}"
            run_script "deploy-sysupgrade.sh" "$ip" "$user"
            ;;
        4)
            read -rp "Router IP: " ip
            read -rp "Package name (e.g. eoip): " pkg
            read -rp "SSH user [root]: " user
            user="${user:-root}"
            run_script "deploy-ipk.sh" "$ip" "$pkg" "$user"
            ;;
        5)
            read -rp "Router IP: " ip
            read -rp "SSH user [root]: " user
            user="${user:-root}"
            read -rp "VXLAN UCI section (optional): " sec
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
            echo "Exiting."
            exit 0
            ;;
        *)
            echo "Invalid option."
            ;;
    esac
done
