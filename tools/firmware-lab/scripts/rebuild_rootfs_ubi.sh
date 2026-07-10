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
ROOT_PASSWORD_HASH="${ROOT_PASSWORD_HASH:-\$1\$mr80x\$yEAHFEuJzKK9hpFTomw4r/}"

PEB_SIZE=131072
DATA_OFFSET=4096
LEB_SIZE=126976
START_PEB=32
# O volume ubi_rootfs do dump Mercusus.mtd11.0-rootfs.bin tem 157 LEBs
# mapeados por VID headers. Usar mais que isso escreve em PEBs livres e deixa
# o SquashFS truncado para o kernel, causando panic no boot.
COUNT=157
MAX_ROOTFS_SIZE=$((LEB_SIZE * COUNT))
EXCLUDES=(
  BR
  CA
  EU_UN_1
  RU
  US
  US_UN_1
  www/webpages/locale/bg_BG
  www/webpages/locale/cs_CZ
  www/webpages/locale/da_DK
  www/webpages/locale/es_ES
  www/webpages/locale/es_MX
  www/webpages/locale/fi_FI
  www/webpages/locale/fr_FR
  www/webpages/locale/hu_HU
  www/webpages/locale/it_IT
  www/webpages/locale/jp_JP
  www/webpages/locale/ko_KR
  www/webpages/locale/nl_NL
  www/webpages/locale/no_NO
  www/webpages/locale/pl_PL
  www/webpages/locale/pt_PT
  www/webpages/locale/ro_RO
  www/webpages/locale/ru_RU
  www/webpages/locale/sk_SK
  www/webpages/locale/sv_SE
  www/webpages/locale/th_TH
  www/webpages/locale/tr_TR
  www/webpages/locale/uk_UA
  www/webpages/locale/vi_VN
  www/webpages/locale/zh_TW
)

mkdir -p "$OUT_DIR"

echo "[1/7] Conferindo arquivos..."
test -f "$ORIGINAL_UBI"
test -d "$ROOTFS_DIR"

echo "[2/7] Backup de metadados..."
sha256sum "$ORIGINAL_UBI" | tee "$OUT_DIR/original.sha256"
grep '^root:' "$ROOTFS_DIR/etc/passwd"
grep '^root:' "$ROOTFS_DIR/etc/shadow"

echo "[2.5/7] Aplicando acesso de manutencao..."
python3 - "$ROOTFS_DIR" "$ROOT_PASSWORD_HASH" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
root_hash = sys.argv[2]

def replace_line(path, prefix, newline):
    p = root / path
    lines = p.read_text().splitlines()
    for i, line in enumerate(lines):
        if line.startswith(prefix):
            lines[i] = newline
            break
    else:
        lines.insert(0, newline)
    p.write_text("\n".join(lines) + "\n")

replace_line("etc/passwd", "root:", "root:x:0:0:root:/root:/bin/ash")
replace_line("etc/shadow", "root:", f"root:{root_hash}:0:0:99999:7:::")

(root / "etc/inittab").write_text(
    "::sysinit:/etc/init.d/rcS S boot\n"
    "::shutdown:/etc/init.d/rcS K shutdown\n"
    "ttyMSM0::askfirst:/bin/ash --login\n"
)

(root / "etc/config/dropbear").write_text(
    "config dropbear\n"
    "\toption enable '1'\n"
    "\toption PasswordAuth 'on'\n"
    "\toption RootPasswordAuth 'on'\n"
    "\toption RootLogin '1'\n"
    "\toption SysAccountLogin '1'\n"
    "\toption Port '22'\n"
)
PY

echo "[3/7] Criando novo SquashFS..."
rm -f "$NEW_SQUASHFS" "$PADDED_SQUASHFS"

mksquashfs "$ROOTFS_DIR" "$NEW_SQUASHFS" \
  -noappend \
  -comp xz \
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
COUNT = 157

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
COUNT = 157

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
