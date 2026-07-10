#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_ROOTFS="$BASE_DIR/work/experimento/extract_safe/squashfs-rootfs"
DEFAULT_OUT_DIR="$BASE_DIR/work/experimento/initramfs"

ROOTFS_DIR="${ROOTFS_DIR:-$DEFAULT_ROOTFS}"
OUT_DIR="${OUT_DIR:-$DEFAULT_OUT_DIR}"
IMAGE_NAME="${IMAGE_NAME:-mr80x-v5-oem-initramfs}"

CPIO_OUT="$OUT_DIR/$IMAGE_NAME.cpio"
CPIO_GZ_OUT="$OUT_DIR/$IMAGE_NAME.cpio.gz"
MANIFEST_OUT="$OUT_DIR/$IMAGE_NAME.manifest.txt"

mkdir -p "$OUT_DIR"

if [ ! -d "$ROOTFS_DIR" ]; then
	echo "ERRO: ROOTFS_DIR não existe: $ROOTFS_DIR" >&2
	exit 1
fi

if [ ! -f "$ROOTFS_DIR/etc/passwd" ] || [ ! -f "$ROOTFS_DIR/etc/shadow" ]; then
	echo "ERRO: o rootfs não parece completo: faltam /etc/passwd ou /etc/shadow" >&2
	exit 1
fi

echo "[1/5] Coletando metadados do rootfs..."
{
	echo "ROOTFS_DIR=$ROOTFS_DIR"
	echo "OUT_DIR=$OUT_DIR"
	echo "IMAGE_NAME=$IMAGE_NAME"
	echo
	echo "passwd:"
	grep '^root:' "$ROOTFS_DIR/etc/passwd" || true
	echo
	echo "shadow:"
	grep '^root:' "$ROOTFS_DIR/etc/shadow" || true
	echo
	echo "login.sh:"
	if [ -f "$ROOTFS_DIR/bin/login.sh" ]; then
		sed -n '1,80p' "$ROOTFS_DIR/bin/login.sh"
	else
		echo "(ausente)"
	fi
} > "$MANIFEST_OUT"

echo "[2/5] Removendo artefatos anteriores..."
rm -f "$CPIO_OUT" "$CPIO_GZ_OUT"

echo "[3/5] Gerando initramfs cpio..."
(
	cd "$ROOTFS_DIR"
	find . | LC_ALL=C sort | cpio --reproducible -o -H newc -R 0:0 > "$CPIO_OUT"
)

echo "[4/5] Compactando..."
gzip -9n -c "$CPIO_OUT" > "$CPIO_GZ_OUT"

echo "[5/5] Validando saída..."
ls -lh "$CPIO_OUT" "$CPIO_GZ_OUT" "$MANIFEST_OUT"
printf '\nArquivo pronto para uso como INITRAMFS_SOURCE externo:\n%s\n' "$CPIO_OUT"
printf 'Arquivo comprimido:\n%s\n' "$CPIO_GZ_OUT"
