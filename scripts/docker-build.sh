#!/bin/bash

# Use BuildKit to reduce build transport issues
export DOCKER_BUILDKIT=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Capture real UID/GID (works even when called with sudo)
REAL_UID=${SUDO_UID:-$(id -u)}
REAL_GID=${SUDO_GID:-$(id -g)}

# Paths
OPENWRT_SRC="$PROJECT_DIR/openwrt"
DOWNLOAD_DIR="$PROJECT_DIR/dl"
OPENWRT_REPO_URL="${OPENWRT_REPO_URL:-https://github.com/openwrt/openwrt.git}"
OPENWRT_BRANCH="${OPENWRT_BRANCH:-openwrt-18.06}"
CONTAINER_PROJECT_DIR="${CONTAINER_PROJECT_DIR:-/home/developer/project}"
CONTAINER_DL_CACHE_DIR="${CONTAINER_DL_CACHE_DIR:-/home/developer/dl_cache}"
MODE="${1:-normal}"

if [ "$MODE" != "normal" ] && [ "$MODE" != "clean" ]; then
    echo "Usage: $0 [normal|clean]"
    exit 1
fi

# 1) Optional clean mode
if [ "$MODE" = "clean" ]; then
    echo "'clean' mode detected. Removing local OpenWrt workspace and download cache..."
    rm -rf "$OPENWRT_SRC" "$DOWNLOAD_DIR"
fi

# Auto-install Docker if missing
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Starting automatic installation..."
    sudo apt-get update
    sudo apt-get install -y docker.io

    sudo systemctl start docker
    sudo systemctl enable docker

    sudo usermod -aG docker ${USER}

    echo "Docker installed. Note: permanent group permissions require logout/login."
    echo "Using 'sudo docker' for this immediate run."
    DOCKER_CMD="sudo docker"
else
    if docker ps &> /dev/null; then
        DOCKER_CMD="docker"
    else
        DOCKER_CMD="sudo docker"
    fi
fi

if [ "$MODE" = "normal" ]; then
    if $DOCKER_CMD ps --format '{{.Names}}' | grep -qx 'openwrt_build'; then
        echo "Container 'openwrt_build' is already running. Opening shell..."
        exec $DOCKER_CMD exec -it openwrt_build /bin/bash
    fi

    if $DOCKER_CMD ps -a --format '{{.Names}}' | grep -qx 'openwrt_build'; then
        echo "Container 'openwrt_build' exists but is stopped. Starting and attaching..."
        exec $DOCKER_CMD start -ai openwrt_build
    fi
fi

# Ensure host cache/work dirs exist
mkdir -p "$OPENWRT_SRC"
mkdir -p "$DOWNLOAD_DIR"

# Ensure OpenWrt source exists (official clone)
if [ ! -f "$OPENWRT_SRC/Makefile" ]; then
    echo "--- Cloning OpenWrt (${OPENWRT_BRANCH}) into $OPENWRT_SRC ---"
    rm -rf "$OPENWRT_SRC"
    git clone --depth 1 --branch "$OPENWRT_BRANCH" "$OPENWRT_REPO_URL" "$OPENWRT_SRC"
fi

chmod +x "$PROJECT_DIR/scripts/build_openwrt.sh"

# 2) Build Docker image
$DOCKER_CMD build -t openwrt-18.06-builder \
    --build-arg USER_ID="$REAL_UID" \
    --build-arg GROUP_ID="$REAL_GID" \
    "$PROJECT_DIR"

if [ $? -ne 0 ]; then
    echo "Docker image build failed. Check messages above."
    exit 1
fi

# 3) Run container build
if [ "$MODE" = "clean" ] && $DOCKER_CMD ps -a --format '{{.Names}}' | grep -qx 'openwrt_build'; then
    echo "Found existing container 'openwrt_build'. Removing it (clean mode)..."
    $DOCKER_CMD rm -f openwrt_build >/dev/null
fi

$DOCKER_CMD run --rm -it \
    -v "$PROJECT_DIR":"$CONTAINER_PROJECT_DIR" \
    -v "$DOWNLOAD_DIR":"$CONTAINER_DL_CACHE_DIR" \
    -e DL_CACHE_DIR="$CONTAINER_DL_CACHE_DIR" \
    -e OWT_MODE="$MODE" \
    -w "$CONTAINER_PROJECT_DIR" \
    --name openwrt_build \
    openwrt-18.06-builder \
    scripts/build_openwrt.sh

RUN_RC=$?
if [ $RUN_RC -ne 0 ]; then
    echo "Container run failed with exit code $RUN_RC."
    exit $RUN_RC
fi

echo "Leaving OpenWrt build environment."
