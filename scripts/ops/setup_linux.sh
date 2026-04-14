#!/bin/bash
set -e

# Update package lists
sudo apt-get update

# Install build dependencies
sudo apt-get install -y \
    build-essential \
    clang \
    cmake \
    git \
    gnustep \
    gnustep-devel \
    gobjc \
    libblocksruntime-dev \
    libdispatch-dev \
    libgnustep-base-dev \
    libssl-dev \
    libqrencode-dev \
    libsqlite3-dev \
    zlib1g-dev

# Print versions
clang --version
cmake --version
gnustep-config --version
