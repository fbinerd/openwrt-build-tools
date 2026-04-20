#!/bin/bash
set -euo pipefail

OPENWRT_DIR="${1:-/home/developer/project/openwrt}"
PATCH_DIR="${2:-/home/developer/project/patches/openwrt}"
CUSTOM_FEED_LINE="src-git customfeed https://github.com/fbinerd/openwrt-custom-feed.git;openwrt-18.06"

if [ ! -d "$OPENWRT_DIR" ]; then
    echo "ERRO: diretorio OpenWrt nao encontrado: $OPENWRT_DIR"
    exit 1
fi

if [ ! -d "$PATCH_DIR" ]; then
    echo "INFO: diretorio de patches nao existe: $PATCH_DIR"
fi

# 1) Aplicar patches (se houver)
shopt -s nullglob
PATCHES=( "$PATCH_DIR"/*.patch )
shopt -u nullglob

if [ ${#PATCHES[@]} -gt 0 ]; then
    echo "Aplicando patches de $PATCH_DIR ..."
    for p in "${PATCHES[@]}"; do
        patch_name="$(basename "$p")"
        echo "- Patch: $patch_name"

        if (cd "$OPENWRT_DIR" && patch --dry-run -p1 < "$p" >/dev/null 2>&1); then
            (cd "$OPENWRT_DIR" && patch -p1 < "$p" >/dev/null)
            echo "  aplicado"
            continue
        fi

        if (cd "$OPENWRT_DIR" && patch -R --dry-run -p1 < "$p" >/dev/null 2>&1); then
            echo "  ja aplicado (skip)"
            continue
        fi

        echo "ERRO: nao foi possivel aplicar $p"
        (cd "$OPENWRT_DIR" && patch --dry-run -p1 < "$p") || true
        exit 1
    done
else
    echo "INFO: nenhum patch encontrado em $PATCH_DIR"
fi

# 2) Nunca tocar em feeds.conf.default.
# Garantir somente feeds.conf com o feed customizado.
if [ ! -f "$OPENWRT_DIR/feeds.conf" ]; then
    if [ -f "$OPENWRT_DIR/feeds.conf.default" ]; then
        cp "$OPENWRT_DIR/feeds.conf.default" "$OPENWRT_DIR/feeds.conf"
    else
        : > "$OPENWRT_DIR/feeds.conf"
    fi
fi

sed -i \
    -e '/^src-git[[:space:]]\+nanofeed[[:space:]]/d' \
    -e '/^src-git[[:space:]]\+customfeed[[:space:]]/d' \
    "$OPENWRT_DIR/feeds.conf"
printf '%s\n' "$CUSTOM_FEED_LINE" >> "$OPENWRT_DIR/feeds.conf"

echo "feeds.conf atualizado com customfeed."
echo "Patches processados com sucesso."
