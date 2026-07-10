#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$BASE_DIR/work/experimento"

ORIGINAL_UBI="${ORIGINAL_UBI:-$WORK_DIR/Mercusus.mtd11.0-rootfs.bin}"
ROOTFS_DIR="${ROOTFS_DIR:-$(find "$BASE_DIR/work/extracted" -type d -name squashfs-root | head -n 1)}"
OUT_DIR="${OUT_DIR:-$WORK_DIR/rebuilt}"

NEW_SQUASHFS="$OUT_DIR/rootfs.new.squashfs"
PADDED_SQUASHFS="$OUT_DIR/rootfs.new.padded.lebs"
OUT_UBI="$OUT_DIR/OpenWrt.mtd11.0-rootfs-rootlogin.ubi"

PEB_SIZE=131072
DATA_OFFSET=4096
LEB_SIZE=126976
START_PEB=32
COUNT=160
MAX_ROOTFS_SIZE=$((LEB_SIZE * COUNT))
EXCLUDES=(
  BR
  CA
  RU
  US
  US_UN_1
)

mkdir -p "$OUT_DIR"

echo "[1/7] Conferindo arquivos..."
test -f "$ORIGINAL_UBI"
test -d "$ROOTFS_DIR"

echo "[2/7] Backup de metadados..."
sha256sum "$ORIGINAL_UBI" | tee "$OUT_DIR/original.sha256"
grep '^root:' "$ROOTFS_DIR/etc/passwd"
grep '^root:' "$ROOTFS_DIR/etc/shadow"

echo "[3/7] Criando novo SquashFS..."
rm -f "$NEW_SQUASHFS" "$PADDED_SQUASHFS"

mksquashfs "$ROOTFS_DIR" "$NEW_SQUASHFS" \
  -noappend \
  -comp xz \
  -Xbcj arm \
  -Xdict-size 100% \
  -b 262144 \
  -all-root \
  -no-xattrs \
  -e "${EXCLUDES[@]}"

NEW_SIZE="$(stat -c '%s' "$NEW_SQUASHFS")"

echo "Novo SquashFS: $NEW_SIZE bytes"
echo "Capacidade do volume ubi_rootfs: $MAX_ROOTFS_SIZE bytes"

if [ "$NEW_SIZE" -gt "$MAX_ROOTFS_SIZE" ]; then
  echo "ERRO: novo SquashFS ficou maior que o volume ubi_rootfs."
  exit 1
fi

echo "[4/7] Padding com 0xFF até ocupar exatamente os LEBs..."
cp "$NEW_SQUASHFS" "$PADDED_SQUASHFS"
truncate -s "$MAX_ROOTFS_SIZE" "$PADDED_SQUASHFS"

python3 - "$PADDED_SQUASHFS" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
data = p.read_bytes()
first_ff = data.find(b'\x00' * 4096)

# trocar zeros adicionados pelo truncate por 0xFF somente depois do tamanho real
# o tamanho real é obtido pelo arquivo rootfs.new.squashfs
real = Path(str(p).replace(".padded.lebs", ".squashfs")).stat().st_size

with p.open("r+b") as f:
    f.seek(real)
    f.write(b"\xff" * (p.stat().st_size - real))
PY

echo "[5/7] Copiando UBI original e substituindo somente dados dos LEBs do ubi_rootfs..."
cp -a "$ORIGINAL_UBI" "$OUT_UBI"

python3 - "$OUT_UBI" "$PADDED_SQUASHFS" <<'PY'
import sys
from pathlib import Path

ubi = Path(sys.argv[1])
payload = Path(sys.argv[2]).read_bytes()

PEB_SIZE = 131072
DATA_OFFSET = 4096
LEB_SIZE = 126976
START_PEB = 32
COUNT = 160

expected = LEB_SIZE * COUNT
if len(payload) != expected:
    raise SystemExit(f"payload size errado: {len(payload)} != {expected}")

with ubi.open("r+b") as f:
    for i in range(COUNT):
        peb = START_PEB + i
        src_off = i * LEB_SIZE
        dst_off = peb * PEB_SIZE + DATA_OFFSET
        f.seek(dst_off)
        f.write(payload[src_off:src_off + LEB_SIZE])

print("Dados do ubi_rootfs substituídos com sucesso.")
PY

echo "[6/7] Verificando imagem reconstruída..."
file "$OUT_UBI" | tee "$OUT_DIR/rebuilt_file.txt"
sha256sum "$OUT_UBI" | tee "$OUT_DIR/rebuilt.sha256"

echo "[7/7] Extraindo SquashFS da imagem reconstruída para teste rápido..."
python3 - "$OUT_UBI" "$OUT_DIR/rootfs.recheck.squashfs" <<'PY'
import sys
from pathlib import Path

inp = Path(sys.argv[1])
out = Path(sys.argv[2])

PEB_SIZE = 131072
DATA_OFFSET = 4096
LEB_SIZE = 126976
START_PEB = 32
COUNT = 160

with inp.open("rb") as f, out.open("wb") as g:
    for peb in range(START_PEB, START_PEB + COUNT):
        f.seek(peb * PEB_SIZE + DATA_OFFSET)
        g.write(f.read(LEB_SIZE))

print(out)
PY

unsquashfs -s "$OUT_DIR/rootfs.recheck.squashfs" | tee "$OUT_DIR/rebuilt_squashfs_info.txt"

echo
echo "Imagem pronta:"
echo "$OUT_UBI"
echo
echo "Senha root configurada no SquashFS:"
grep '^root:' "$ROOTFS_DIR/etc/shadow"
