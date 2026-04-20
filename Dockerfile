FROM ubuntu:18.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required dependencies for OpenWrt 18.06 build
RUN apt-get update && apt-get install -y \
    build-essential libncurses5-dev gawk gettext libssl-dev unzip zlib1g-dev \
    libpam0g-dev libgnutls28-dev libidn2-dev libssh2-1-dev liblzma-dev libsnmp-dev \
    file python python3 git wget subversion libtree-perl ca-certificates libelf-dev \
    bash-completion time rsync ccache sudo \
    && apt-get clean

# Receive host UID/GID to avoid permission mismatch on mounted volumes
ARG USER_ID=1000
ARG GROUP_ID=1000

# Create non-root user when UID is not 0
RUN if [ "$USER_ID" -ne 0 ]; then \
    (groupadd -g ${GROUP_ID} developer || groupadd developer || true) && \
    (useradd -l -u ${USER_ID} -g ${GROUP_ID} -m developer || useradd -m developer || true); \
    fi && \
    echo "developer ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER developer
WORKDIR /home/developer/project

# Terminal defaults for menuconfig
ENV TERM=xterm-256color

CMD ["/bin/bash"]
