#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/load-env.sh"

OPENWRT_DIR="${OPENWRT_DIR:-$PROJECT_DIR/openwrt}"
DL_DIR="${DL_DIR:-$PROJECT_DIR/dl}"
REPORTS_DIR="${REPORTS_DIR:-$PROJECT_DIR/reports}"
CONTAINER_NAME="${CONTAINER_NAME:-openwrt_build}"
OPENWRT_BRANCH="${OPENWRT_BRANCH:-openwrt-25.12}"
IMAGE_NAME="${IMAGE_NAME:-openwrt-${OPENWRT_BRANCH}-builder}"
ASSUME_YES="${1:-}"

if ! command -v docker >/dev/null 2>&1; then
    DOCKER_CMD="sudo docker"
else
    if docker ps >/dev/null 2>&1; then
        DOCKER_CMD="docker"
    else
        DOCKER_CMD="sudo docker"
    fi
fi

if [ "$ASSUME_YES" != "--yes" ]; then
    cat <<EOF
This will purge local build runtime data for this project:
  - Docker container: $CONTAINER_NAME
  - Docker image:     $IMAGE_NAME
  - Directory:        $OPENWRT_DIR
  - Directory:        $DL_DIR
  - Directory:        $REPORTS_DIR

This action is destructive for local build/cache data.
EOF
    read -rp "Continue? [y/N]: " ans
    case "$ans" in
        y|Y|yes|YES) ;;
        *) echo "Purge cancelled."; exit 0 ;;
    esac
fi

if $DOCKER_CMD ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "Removing container: $CONTAINER_NAME"
    $DOCKER_CMD rm -f "$CONTAINER_NAME" >/dev/null
fi

if $DOCKER_CMD image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "Removing image: $IMAGE_NAME"
    $DOCKER_CMD rmi -f "$IMAGE_NAME" >/dev/null
fi

echo "Removing local directories..."
rm -rf "$OPENWRT_DIR" "$DL_DIR" "$REPORTS_DIR"
mkdir -p "$DL_DIR" "$REPORTS_DIR"

echo "Purge completed."
