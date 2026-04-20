#!/bin/bash
# Script de automação interna para o OpenWrt 18.06
set -e

# Evita prompts de credenciais para repositórios públicos
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/true

# Entra na pasta do código-fonte que agora é uma subpasta do projeto
cd /home/developer/project/openwrt

# Passo 0: Verifica se o código-fonte está presente
if [ ! -f "Makefile" ]; then
    echo "ERRO: Pasta openwrt está vazia."
    echo "Execute 'git submodule update --init' no host."
    exit 1
fi

echo "--- Passo 0.1: Aplicando patches locais em openwrt ---"
/home/developer/project/scripts/apply-openwrt-patches.sh /home/developer/project/openwrt /home/developer/project/patches/openwrt

# Cria o link simbólico para a pasta de downloads montada em local neutro
if [ ! -L dl ]; then
    echo "--- Vinculando pasta de downloads externa ---"
    rm -rf dl # Remove diretório vazio caso o git clone o tenha criado
    ln -s /home/developer/dl_cache dl
fi

echo "--- Passo 1: Atualizando feeds ---"
./scripts/feeds update -a

echo "--- Passo 2: Instalando feeds ---"
./scripts/feeds install -a

echo "--- Passo 3: Baixando fontes base ---"
# Garante um .config mínimo para o download inicial
if [ ! -f .config ]; then
    make defconfig
fi
make download

echo "--- Passo 4: Instalando dependência openwrt-linux-eoip (Kernel Module) ---"
if [ ! -d package/openwrt-linux-eoip ]; then
    # Conforme README: colocar em openwrt/package/
    git clone https://github.com/bogdik/openwrt-linux-eoip.git package/openwrt-linux-eoip
fi

echo "--- Passo 5: Instalando luci-app-eoip seguindo o README ---"
# 1. Coloca o repositório no caminho do feed de LuCI
mkdir -p feeds/luci/applications/luci-app-eoip
if [ ! -d feeds/luci/applications/luci-app-eoip/.git ]; then
    git clone https://github.com/bogdik/luci-app-eoip.git feeds/luci/applications/luci-app-eoip
fi

# 2. Cria o link simbólico conforme o README
mkdir -p package/feeds/luci/
ln -sf ../../../feeds/luci/applications/luci-app-eoip package/feeds/luci/luci-app-eoip

# Habilita os pacotes no .config
echo "CONFIG_PACKAGE_kmod-eoip=y" >> .config
echo "CONFIG_PACKAGE_luci-app-eoip=y" >> .config

# Atualiza a configuração para validar as novas dependências
make defconfig

echo "--- Setup concluído com sucesso! ---"
exec /bin/bash
