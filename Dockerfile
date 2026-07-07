FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required dependencies for OpenWrt 25.12 build
RUN apt-get update && apt-get install -y \
    build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
    gettext git libncurses-dev libssl-dev python3 python3-distutils \
    python3-setuptools python3-yaml rsync swig unzip zlib1g-dev file wget \
    time ccache sudo ca-certificates libelf-dev bash-completion \
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
