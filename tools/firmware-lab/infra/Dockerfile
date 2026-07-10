FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install core system tools, compilers, compression utilities, and analysis tools
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    wget \
    curl \
    rsync \
    file \
    binutils \
    binwalk \
    squashfs-tools \
    squashfs-tools-ng \
    mtd-utils \
    u-boot-tools \
    fakeroot \
    cpio \
    xxd \
    vim \
    nano \
    less \
    tree \
    jq \
    bc \
    gdb \
    gdb-multiarch \
    qemu-user-static \
    p7zip-full \
    unzip \
    zip \
    gzip \
    bzip2 \
    xz-utils \
    lzma \
    lzop \
    zstd \
    tar \
    ccache \
    flex \
    bison \
    pkg-config \
    cmake \
    autoconf \
    automake \
    libtool \
    patchelf \
    device-tree-compiler \
    zlib1g-dev \
    liblzma-dev \
    liblzo2-dev \
    libbz2-dev \
    libssl-dev \
    libelf-dev \
    libarchive-dev \
    libncurses-dev \
    python3 \
    python3-dev \
    python3-pip \
    python3-setuptools \
    python3-wheel \
    python3-capstone \
    python3-venv \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install latest stable Radare2 from source
RUN git clone --depth 1 https://github.com/radareorg/radare2.git /tmp/radare2 && \
    /tmp/radare2/sys/install.sh && \
    rm -rf /tmp/radare2

# Install ubi-reader for UBI filesystem extraction support in binwalk
RUN pip3 install --no-cache-dir \
    ubi-reader \
    pycryptodome \
    pyelftools \
    capstone \
    keystone-engine \
    lief
    
# Capture host UID/GID to prevent file permission issues on mounted volumes
ARG USER_ID=1000
ARG GROUP_ID=1000

# Create developer user matching host UID/GID
RUN if [ "$USER_ID" -ne 0 ]; then \
    (groupadd -g ${GROUP_ID} developer || groupadd developer || true) && \
    (useradd -l -u ${USER_ID} -g ${GROUP_ID} -m developer || useradd -m developer || true); \
    fi && \
    echo "developer ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER developer
WORKDIR /home/developer/analis

# Default terminal variables
ENV TERM=xterm-256color

CMD ["/bin/bash"]
