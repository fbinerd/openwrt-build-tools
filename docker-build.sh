#!/bin/bash

# Força o uso do BuildKit para evitar erros de comunicação (closed pipe)
export DOCKER_BUILDKIT=1

# Captura o UID e GID reais de quem chamou o script, mesmo se usar sudo
REAL_UID=${SUDO_UID:-$(id -u)}
REAL_GID=${SUDO_GID:-$(id -g)}

# Caminhos
OPENWRT_SRC="$(pwd)/openwrt"
DOWNLOAD_DIR="$(pwd)/dl"

# 1. Tratamento do atributo 'clean'
if [ "$1" == "clean" ]; then
    echo "Ação 'clean' detectada. Resetando repositório openwrt..."
    # Em submodules, é melhor usar o git clean do que apagar a pasta
    if [ -d "$OPENWRT_SRC/.git" ] || [ -f "$OPENWRT_SRC/.git" ]; then
        cd "$OPENWRT_SRC" && git clean -fdx && git checkout . && cd ..
    else
        rm -rf "$OPENWRT_SRC" && mkdir -p "$OPENWRT_SRC"
    fi
fi

# Verifica se o Docker está instalado. Se não estiver, realiza a instalação automática.
if ! command -v docker &> /dev/null; then
    echo "Docker não encontrado no sistema. Iniciando instalação..."
    sudo apt-get update
    sudo apt-get install -y docker.io

    # Garante que o serviço do Docker esteja rodando e habilitado para iniciar com o sistema
    sudo systemctl start docker
    sudo systemctl enable docker

    # Adiciona o usuário atual ao grupo docker para permitir execução de comandos sem sudo
    sudo usermod -aG docker ${USER}

    echo "Docker instalado! Nota: permissões permanentes exigem logout/login."
    echo "Para esta execução imediata, utilizaremos 'sudo docker'."
    DOCKER_CMD="sudo docker"
else
    # Testa se o usuário atual tem permissão para rodar docker, se não, usa sudo
    if docker ps &> /dev/null; then
        DOCKER_CMD="docker"
    else
        DOCKER_CMD="sudo docker"
    fi
fi

# Garante que a pasta de downloads existe no host para persistência
mkdir -p "$OPENWRT_SRC"
mkdir -p "$DOWNLOAD_DIR"

# Garante que o Submodule do OpenWrt está inicializado e atualizado
if [ ! -f "$OPENWRT_SRC/Makefile" ]; then
    echo "--- Inicializando Submodule OpenWrt ---"
    git submodule update --init --recursive
fi

# Garante que o script de automação interna tem permissão de execução
chmod +x build_openwrt.sh

# 1. Constrói a imagem Docker (procura o Dockerfile na pasta atual)
$DOCKER_CMD build -t openwrt-18.06-builder \
    --build-arg USER_ID="$REAL_UID" \
    --build-arg GROUP_ID="$REAL_GID" .

if [ $? -ne 0 ]; then
    echo "Erro na construção da imagem. Verifique as mensagens acima."
    exit 1
fi

# 2. Executa o container
# Mapeia a pasta atual (raiz) e a pasta de downloads separadamente para persistência
$DOCKER_CMD run --rm -it \
    -v "$(pwd)":/home/developer/project \
    -v "$DOWNLOAD_DIR":/home/developer/dl_cache \
    --name openwrt_build \
    openwrt-18.06-builder \
    /home/developer/project/build_openwrt.sh

echo "Saindo do ambiente de compilação OpenWrt."