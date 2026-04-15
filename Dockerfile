FROM ubuntu:18.04

# Evita prompts interativos durante a instalação
ENV DEBIAN_FRONTEND=noninteractive

# Instala as dependências necessárias para o OpenWrt 18.06
# Inclui bibliotecas para ncurses (mconf.c) e ferramentas de build
RUN apt-get update && apt-get install -y \
    build-essential libncurses5-dev gawk gettext libssl-dev unzip zlib1g-dev \
    libpam0g-dev libgnutls28-dev libidn2-dev libssh2-1-dev liblzma-dev libsnmp-dev \
    file python python3 git wget subversion libtree-perl ca-certificates libelf-dev \
    bash-completion time rsync ccache sudo \
    && apt-get clean

# Recebe o UID e GID do host durante o build para evitar conflitos de permissão nos volumes
ARG USER_ID=1000
ARG GROUP_ID=1000

# Cria o grupo e o usuário apenas se o UID não for 0 (root)
# Adicionamos verificações para evitar falhas se o GID já existir no sistema base
RUN if [ "$USER_ID" -ne 0 ]; then \
    (groupadd -g ${GROUP_ID} developer || groupadd developer || true) && \
    (useradd -l -u ${USER_ID} -g ${GROUP_ID} -m developer || useradd -m developer || true); \
    fi && \
    echo "developer ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER developer
WORKDIR /home/developer/project

# Configura o ambiente de terminal para o menuconfig
ENV TERM=xterm-256color

# Comando padrão ao iniciar o container
CMD ["/bin/bash"]