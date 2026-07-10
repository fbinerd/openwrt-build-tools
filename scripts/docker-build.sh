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
OPENWRT_BRANCH="${OPENWRT_BRANCH:-openwrt-25.12}"
BUILDER_IMAGE_NAME="openwrt-${OPENWRT_BRANCH}-builder"
ENABLE_CUSTOM_FEED="${ENABLE_CUSTOM_FEED:-0}"
CONTAINER_PROJECT_DIR="${CONTAINER_PROJECT_DIR:-/home/developer/project}"
CONTAINER_DL_CACHE_DIR="${CONTAINER_DL_CACHE_DIR:-/home/developer/dl_cache}"
MODE="${1:-normal}"
ROUTER_CONFIGS_DIR="${ROUTER_CONFIGS_DIR:-$PROJECT_DIR/router-configs}"
SELECTED_ROUTER_CONFIG="${2:-}"
DEFAULT_ROUTER_CONFIG="${DEFAULT_ROUTER_CONFIG:-$ROUTER_CONFIGS_DIR/default.config}"
MAKE_JOBS="${MAKE_JOBS:-}"
CLEAN_TOOLS="${CLEAN_TOOLS:-ask}"

if [ "$MODE" != "normal" ] && [ "$MODE" != "clean" ]; then
    echo "Usage: $0 [normal|clean] [router_name_or_config_file]"
    exit 1
fi

has_compiled_tools() {
    [ -d "$OPENWRT_SRC/staging_dir/host" ] && return 0
    [ -d "$OPENWRT_SRC/staging_dir/hostpkg" ] && return 0
    [ -d "$OPENWRT_SRC/staging_dir/toolchain" ] && return 0
    [ -d "$OPENWRT_SRC/build_dir/host" ] && return 0
    [ -d "$OPENWRT_SRC/build_dir/hostpkg" ] && return 0
    [ -d "$OPENWRT_SRC/build_dir/toolchain" ] && return 0
    compgen -G "$OPENWRT_SRC/build_dir/tool-*" >/dev/null && return 0
    compgen -G "$OPENWRT_SRC/staging_dir/toolchain-*" >/dev/null && return 0
    compgen -G "$OPENWRT_SRC/build_dir/toolchain-*" >/dev/null && return 0
    return 1
}

pick_clean_tools_interactive() {
    local answer
    read -rp "Compiled tools/toolchain detected. Delete all compiled tools/toolchain as well? [y/N]: " answer
    case "$answer" in
        y|Y|yes|YES)
            CLEAN_TOOLS=1
            ;;
        *)
            CLEAN_TOOLS=0
            ;;
    esac
}

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

# Optional router profile selection (interactive when not explicitly provided)
pick_router_config_interactive() {
    local files=()
    local i
    local answer
    local choice

    mkdir -p "$ROUTER_CONFIGS_DIR"

    mapfile -t files < <(find "$ROUTER_CONFIGS_DIR" -maxdepth 1 -type f -name '*.config' -printf '%f\n' | sort)

    read -rp "Do you want to prepare a specific router config? [y/N]: " answer
    case "$answer" in
        y|Y|yes|YES)
            ;;
        *)
            SELECTED_ROUTER_CONFIG=""
            return 0
            ;;
    esac

    if [ ${#files[@]} -eq 0 ]; then
        echo "No .config files found in $ROUTER_CONFIGS_DIR"
        echo "Tip: add files like 'my-router.config' to that folder."
        SELECTED_ROUTER_CONFIG=""
        return 0
    fi

    echo "Available router profiles:"
    for i in "${!files[@]}"; do
        printf "  %d) %s\n" "$((i + 1))" "${files[$i]%.config}"
    done
    echo "  0) none (keep current behavior)"

    read -rp "Choose a profile number (Enter = none): " choice
    if [ -z "$choice" ] || [ "$choice" = "0" ]; then
        SELECTED_ROUTER_CONFIG=""
        return 0
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#files[@]}" ]; then
        echo "Invalid selection. Continuing without router profile."
        SELECTED_ROUTER_CONFIG=""
        return 0
    fi

    SELECTED_ROUTER_CONFIG="${files[$((choice - 1))]}"
}

resolve_router_config_path() {
    local arg="$1"
    local path=""

    [ -z "$arg" ] && return 0

    if [ -f "$arg" ]; then
        path="$arg"
    elif [ -f "$ROUTER_CONFIGS_DIR/$arg" ]; then
        path="$ROUTER_CONFIGS_DIR/$arg"
    elif [ -f "$ROUTER_CONFIGS_DIR/$arg.config" ]; then
        path="$ROUTER_CONFIGS_DIR/$arg.config"
    fi

    if [ -z "$path" ]; then
        echo "ERROR: router config not found: $arg"
        echo "Checked:"
        echo "  - $arg"
        echo "  - $ROUTER_CONFIGS_DIR/$arg"
        echo "  - $ROUTER_CONFIGS_DIR/$arg.config"
        exit 1
    fi

    SELECTED_ROUTER_CONFIG="$path"
}

pick_make_jobs_interactive() {
    local answer

    read -rp "How many CPU cores should make use? (Enter = default make): " answer
    if [ -z "$answer" ]; then
        MAKE_JOBS=""
        return 0
    fi

    if [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -gt 0 ]; then
        MAKE_JOBS="$answer"
        return 0
    fi

    echo "Invalid value. Falling back to default make."
    MAKE_JOBS=""
}

# Ensure host cache/work dirs exist
if [ ! -e "$OPENWRT_SRC" ] && [ -d "$PROJECT_DIR/../openwrt" ]; then
    echo "Found side-by-side OpenWrt workspace at $PROJECT_DIR/../openwrt. Linking it..."
    ln -s "../openwrt" "$OPENWRT_SRC"
fi

mkdir -p "$OPENWRT_SRC"
mkdir -p "$DOWNLOAD_DIR"
mkdir -p "$ROUTER_CONFIGS_DIR"

# 1) Optional clean mode (preserving dl/ always)
if [ "$MODE" = "clean" ] && [ -f "$OPENWRT_SRC/Makefile" ] && [ -d "$OPENWRT_SRC/.git" ]; then
    if [ "$CLEAN_TOOLS" = "ask" ]; then
        if has_compiled_tools; then
            pick_clean_tools_interactive
        else
            CLEAN_TOOLS=0
        fi
    fi

    echo "'clean' mode detected. Resetting local OpenWrt workspace (dl/ preserved)..."
    if [ "$CLEAN_TOOLS" = "1" ]; then
        echo "Removing source artifacts + compiled tools..."
        (
            cd "$OPENWRT_SRC"
            git reset --hard
            git clean -fdx
        )
    else
        echo "Removing source artifacts only (keeping compiled tools/toolchain)..."
        (
            cd "$OPENWRT_SRC"
            git reset --hard
            git clean -fdx \
                -e staging_dir/host \
                -e staging_dir/hostpkg \
                -e staging_dir/toolchain \
                -e 'staging_dir/toolchain-*' \
                -e build_dir/host \
                -e build_dir/hostpkg \
                -e build_dir/toolchain \
                -e 'build_dir/tool-*' \
                -e 'build_dir/toolchain-*'
        )
    fi
fi

# Ensure OpenWrt source exists (official clone)
if [ ! -f "$OPENWRT_SRC/Makefile" ]; then
    echo "--- Cloning OpenWrt (${OPENWRT_BRANCH}) into $OPENWRT_SRC ---"
    rm -rf "$OPENWRT_SRC"
    # OpenWrt 18.06 getver.sh uses a fixed historical base commit (REBOOT=...).
    # Do not use shallow clone, otherwise that commit may be missing and cause:
    # "fatal: Invalid revision range ...".
    git clone --branch "$OPENWRT_BRANCH" "$OPENWRT_REPO_URL" "$OPENWRT_SRC"
fi

if [ -n "$SELECTED_ROUTER_CONFIG" ]; then
    resolve_router_config_path "$SELECTED_ROUTER_CONFIG"
else
    pick_router_config_interactive
fi

if [ -n "$SELECTED_ROUTER_CONFIG" ]; then
    if [ -f "$SELECTED_ROUTER_CONFIG" ]; then
        cp "$SELECTED_ROUTER_CONFIG" "$OPENWRT_SRC/.config"
        echo "Applied router profile: $SELECTED_ROUTER_CONFIG -> $OPENWRT_SRC/.config"
    else
        cp "$ROUTER_CONFIGS_DIR/$SELECTED_ROUTER_CONFIG" "$OPENWRT_SRC/.config"
        echo "Applied router profile: $ROUTER_CONFIGS_DIR/$SELECTED_ROUTER_CONFIG -> $OPENWRT_SRC/.config"
    fi
elif [ -f "$DEFAULT_ROUTER_CONFIG" ]; then
    cp "$DEFAULT_ROUTER_CONFIG" "$OPENWRT_SRC/.config"
    echo "Applied default profile: $DEFAULT_ROUTER_CONFIG -> $OPENWRT_SRC/.config"
else
    echo "No router profile selected and default profile not found:"
    echo "  $DEFAULT_ROUTER_CONFIG"
    echo "Continuing with existing OpenWrt .config."
fi

if [ -z "$MAKE_JOBS" ]; then
    pick_make_jobs_interactive
fi

if [ -n "$MAKE_JOBS" ]; then
    echo "Using parallel make: -j$MAKE_JOBS"
else
    echo "Using default make (no -j override)."
fi

chmod +x "$PROJECT_DIR/scripts/build_openwrt.sh"

# 2) Build Docker image
$DOCKER_CMD build -f "$PROJECT_DIR/containers/openwrt-builder/Dockerfile" -t "$BUILDER_IMAGE_NAME" \
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

# Resolve physical path for mounting (to handle symlinks to side-by-side openwrt)
HOST_OPENWRT_SRC="$(readlink -f "$OPENWRT_SRC" || echo "$OPENWRT_SRC")"

$DOCKER_CMD run --rm -it \
    -v "$PROJECT_DIR":"$CONTAINER_PROJECT_DIR" \
    -v "$HOST_OPENWRT_SRC":"/home/developer/openwrt" \
    -v "$DOWNLOAD_DIR":"$CONTAINER_DL_CACHE_DIR" \
    -e DL_CACHE_DIR="$CONTAINER_DL_CACHE_DIR" \
    -e OWT_MODE="$MODE" \
    -e OWT_MAKE_JOBS="$MAKE_JOBS" \
    -e OPENWRT_BRANCH="$OPENWRT_BRANCH" \
    -e ENABLE_CUSTOM_FEED="$ENABLE_CUSTOM_FEED" \
    -e OPENWRT_DIR="/home/developer/openwrt" \
    -w "$CONTAINER_PROJECT_DIR" \
    --name openwrt_build \
    "$BUILDER_IMAGE_NAME" \
    scripts/build_openwrt.sh

RUN_RC=$?
if [ $RUN_RC -ne 0 ]; then
    echo "Container run failed with exit code $RUN_RC."
    exit $RUN_RC
fi

echo "Leaving OpenWrt build environment."
