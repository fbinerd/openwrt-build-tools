#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="/home/developer/openwrt"

cd "$OPENWRT_DIR"

echo "[1/7] Verificando árvore OpenWrt..."
test -f scripts/config || {
    echo "ERRO: árvore OpenWrt inválida."
    exit 1
}

echo "[2/7] Preparando configuração..."
make defconfig

echo "[3/7] Habilitando initramfs..."
./scripts/config --enable CONFIG_TARGET_ROOTFS_INITRAMFS
./scripts/config --disable CONFIG_TARGET_ROOTFS_SQUASHFS
./scripts/config --disable CONFIG_TARGET_ROOTFS_EXT4FS

echo "[4/7] Mantendo o device já configurado..."
make defconfig

echo "[5/7] Compilando..."
make -j"$(nproc)" V=s

echo "[6/7] Procurando imagens geradas..."
find bin/targets -type f \
    \( -iname '*initramfs*.itb' -o \
       -iname '*initramfs*.bin' -o \
       -iname '*mr80x*initramfs*' \) \
    -printf '%p\n'

echo "[7/7] Concluído."
