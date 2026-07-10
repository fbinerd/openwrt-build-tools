#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_UID=${SUDO_UID:-$(id -u)}
REAL_GID=${SUDO_GID:-$(id -g)}

IMAGE_NAME="binary-analyzer"
CONTAINER_NAME="binary_analysis_session"

# Check if docker is running
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker not found. Please install Docker first."
    exit 1
fi

if docker ps &> /dev/null; then
    DOCKER_CMD="docker"
else
    DOCKER_CMD="sudo docker"
fi

# 1) Build the analysis image
echo "=== Building Binary Analyzer Docker Image ==="
$DOCKER_CMD build -t "$IMAGE_NAME" \
    --build-arg USER_ID="$REAL_UID" \
    --build-arg GROUP_ID="$REAL_GID" \
    "$SCRIPT_DIR"

# 2) Run the container
echo "=== Starting Binary Analysis Environment ==="
echo "Mounting: $SCRIPT_DIR -> /home/developer/analis"
echo

# Print a nice usage guide before launching the shell
cat << 'EOF'
========================================================================
             BINARY & FIRMWARE ANALYSIS ENVIRONMENT
========================================================================
You have entered the analysis container. The host 'analis' directory
is mounted at '/home/developer/analis'. All changes persist.

Useful Tools Available:
  - binwalk             : Scan/extract firmware images (e.g., binwalk -e <file>)
  - radare2 (r2)        : CLI disassembly and reverse engineering (e.g., r2 -A <binary>)
  - file / strings / dd : Inspect metadata, search for ASCII strings, slice files
  - unsquashfs          : Unpack squashfs filesystems
  - qemu-user-static    : Run arm/mips binaries (e.g., qemu-arm ./my_binary)

To start analyzing the Mercusys firmware, try running:
  binwalk -B binaries/MR80X_v5_br-up-eu-ver1-3-1-P1*.bin
========================================================================
EOF

$DOCKER_CMD run --rm -it \
    -v "$SCRIPT_DIR":"/home/developer/analis" \
    --name "$CONTAINER_NAME" \
    "$IMAGE_NAME" \
    /bin/bash
