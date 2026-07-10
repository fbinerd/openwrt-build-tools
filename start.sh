#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"

. "$SCRIPTS_DIR/load-env.sh"

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
  ./start.sh ipk <ip> <pkg> [user] [password]
  ./start.sh sysupgrade <ip> [user] [password]
  ./start.sh deploy-ipk <ip> <pkg> [user] [password]
  ./start.sh deploy-sysupgrade <ip> [user] [password]
  ./start.sh patches          # apply patches in openwrt
  ./start.sh backup-config    # backup openwrt/.config to router-configs/
  ./start.sh purge            # remove local docker/runtime/cache data
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

if [ "${1:-}" = "deploy-ipk" ]; then
    shift
    run_script "deploy-ipk.sh" "$@"
    exit 0
fi

if [ "${1:-}" = "sysupgrade" ]; then
    shift
    run_script "deploy-sysupgrade.sh" "$@"
    exit 0
fi

if [ "${1:-}" = "deploy-sysupgrade" ]; then
    shift
    run_script "deploy-sysupgrade.sh" "$@"
    exit 0
fi


if [ "${1:-}" = "patches" ]; then
    run_script "apply-openwrt-patches.sh" "$ROOT_DIR/openwrt" "$ROOT_DIR/patches/openwrt"
    exit 0
fi

if [ "${1:-}" = "backup-config" ]; then
    run_script "backup-router-config.sh"
    exit 0
fi

if [ "${1:-}" = "purge" ]; then
    shift || true
    run_script "purge-workspace.sh" "$@"
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
5) Apply openwrt patches
6) Backup router .config profile
7) Purge local runtime/cache data
8) Exit
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
            read -rp "SSH username (login user) [root]: " user
            user="${user:-root}"
            run_script "deploy-sysupgrade.sh" "$ip" "$user"
            ;;
        4)
            read -rp "Router IP: " ip
            read -rp "Package name (e.g. eoip): " pkg
            read -rp "SSH username (login user) [root]: " user
            user="${user:-root}"
            run_script "deploy-ipk.sh" "$ip" "$pkg" "$user"
            ;;
        5)
            run_script "apply-openwrt-patches.sh" "$ROOT_DIR/openwrt" "$ROOT_DIR/patches/openwrt"
            ;;
        6)
            run_script "backup-router-config.sh"
            ;;
        7)
            run_script "purge-workspace.sh"
            ;;
        8)
            echo "Exiting."
            exit 0
            ;;
        *)
            echo "Invalid option."
            ;;
    esac
done
