#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${OPENWRT_DIR:-/home/fabiano/opw/openwrt}"
ROOTFS_CPIO="${ROOTFS_CPIO:-/home/fabiano/opw/openwrt-build-tools/tools/firmware-lab/work/experimento/initramfs/mr80x-v5-oem-initramfs.cpio.gz}"
DL_DIR="${DL_DIR:-/home/fabiano/opw/openwrt-build-tools/dl}"

cd "$OPENWRT_DIR"

echo "[1/7] Verificando árvore OpenWrt..."
test -x scripts/config/conf || {
    echo "ERRO: árvore OpenWrt inválida."
    exit 1
}

echo "[1.5/7] Verificando initramfs externo..."
test -f "$ROOTFS_CPIO" || {
    echo "ERRO: cpio externo não encontrado: $ROOTFS_CPIO"
    exit 1
}

mkdir -p "$DL_DIR"
export DL_DIR

echo "[2/7] Preparando configuração..."
if [ -f tmp/.config.old ]; then
	cp tmp/.config.old .config
elif [ -f .config.old ]; then
	cp .config.old .config
fi

echo "[3/7] Habilitando initramfs..."
python3 - "$ROOTFS_CPIO" <<'PY'
import pathlib, sys

rootfs_cpio = sys.argv[1]
config = pathlib.Path(".config")
data = config.read_text()

for key, value in [
    ("CONFIG_TARGET_qualcommax", "y"),
    ("CONFIG_TARGET_qualcommax_ipq50xx", "y"),
    ("CONFIG_TARGET_qualcommax_ipq50xx_DEVICE_mercusys_mr80x-v5", "y"),
    ("CONFIG_TARGET_ROOTFS_INITRAMFS", "y"),
    ("CONFIG_EXTERNAL_CPIO", f'"{rootfs_cpio}"'),
]:
    data = "\n".join(
        line for line in data.splitlines()
        if not line.startswith(f"{key}=") and line != f"# {key} is not set"
    ) + "\n"
    data += f"{key}={value}\n"

for key in ["CONFIG_TARGET_ROOTFS_SQUASHFS", "CONFIG_TARGET_ROOTFS_EXT4FS"]:
    data = "\n".join(
        line for line in data.splitlines()
        if not line.startswith(f"{key}=") and line != f"# {key} is not set"
    ) + "\n"
    data += f"# {key} is not set\n"

config.write_text(data)
PY

echo "[4/7] Confirmando alvos na configuração..."
grep -nE '^(CONFIG_TARGET_qualcommax|CONFIG_TARGET_qualcommax_ipq50xx|CONFIG_TARGET_qualcommax_ipq50xx_DEVICE_mercusys_mr80x-v5|CONFIG_TARGET_ROOTFS_INITRAMFS|CONFIG_EXTERNAL_CPIO|CONFIG_TARGET_SUBTARGET|CONFIG_TARGET_PROFILE)=' .config || true

echo "[5/7] Compilando..."
make DL_DIR="$DL_DIR" -j"$(nproc)" V=s target/linux/compile

echo "[6/7] Procurando imagens geradas..."
find bin/targets -type f \
    \( -iname '*initramfs*.itb' -o \
       -iname '*initramfs*.bin' -o \
       -iname '*mr80x*initramfs*' \) \
    -printf '%p\n'

echo "[6.5/7] Verificando cpio configurado..."
grep -nE '^(CONFIG_TARGET_ROOTFS_INITRAMFS|CONFIG_EXTERNAL_CPIO)=' .config || true

echo "[7/7] Concluído."
