FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install all system dependencies that build.sh expects
RUN apt-get update && apt-get install -y \
    p7zip-full \
    wget \
    icoutils \
    imagemagick \
    desktop-file-utils \
    libfuse2 \
    file \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Use the existing ubuntu user (UID 1000) to match typical host user
USER ubuntu
WORKDIR /home/ubuntu

# Pre-install NVM and Node.js LTS so builds are faster
ENV NVM_DIR=/home/ubuntu/.nvm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash \
    && . "$NVM_DIR/nvm.sh" \
    && nvm install --lts

# appimagetool AppImages can't use FUSE inside Docker
ENV APPIMAGE_EXTRACT_AND_RUN=1

COPY entrypoint.sh /entrypoint.sh
WORKDIR /build
ENTRYPOINT ["/entrypoint.sh"]
