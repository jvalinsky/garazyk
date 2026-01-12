#!/bin/bash
set -e

# Non-interactive frontend for apt
export DEBIAN_FRONTEND=noninteractive

# Enforce Clang
export CC=clang
export CXX=clang++

echo ">>> Updating repositories..."
apt-get update

echo ">>> Installing dependencies..."
apt-get install -y \
    build-essential \
    clang \
    git \
    libffi-dev \
    libxml2-dev \
    libgnutls28-dev \
    libicu-dev \
    libcurl4-openssl-dev \
    libblocksruntime-dev \
    libjpeg-dev \
    libtiff-dev \
    libpng-dev \
    autoconf \
    libtool \
    pkg-config \
    valgrind \
    cmake \
    screen \
    wget \
    vim

# Upgrade CMake (Required for libdispatch)
echo ">>> Upgrading CMake..."
wget https://github.com/Kitware/CMake/releases/download/v3.28.1/cmake-3.28.1-linux-x86_64.sh
chmod +x cmake-3.28.1-linux-x86_64.sh
./cmake-3.28.1-linux-x86_64.sh --prefix=/usr --skip-license
rm cmake-3.28.1-linux-x86_64.sh

# Create build directory
mkdir -p ~/gnustep-build
cd ~/gnustep-build

echo ">>> Cloning & Building libkqueue..."
if [ ! -d "libkqueue" ]; then
    git clone https://github.com/mheily/libkqueue.git
fi
cd libkqueue
mkdir -p build
cd build
cmake .. -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
make install
ldconfig
cd ../..

echo ">>> Cloning & Building libpthread_workqueue..."
if [ ! -d "libpwq" ]; then
    git clone https://github.com/mheily/libpwq.git
fi
cd libpwq
mkdir -p build
cd build
# Added -DCMAKE_C_FLAGS="-fcommon" to fix multiple definition errors
cmake .. -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="-fcommon"
make -j$(nproc)
make install
ldconfig
cd ../..

echo ">>> Cloning GNUstep Make..."
if [ ! -d "tools-make" ]; then
    git clone https://github.com/gnustep/tools-make.git
fi

echo ">>> Building GNUstep Make..."
cd tools-make
./configure --with-layout=gnustep --enable-debug-by-default --enable-objc-nonfragile-abi --with-library-combo=ng-gnu-gnu
make
make install
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
cd ..

echo ">>> Cloning LibObjC2..."
if [ ! -d "libobjc2" ]; then
    git clone https://github.com/gnustep/libobjc2.git
fi

echo ">>> Building LibObjC2..."
cd libobjc2
rm -rf build
mkdir -p build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_PREFIX=/usr
make -j$(nproc)
make install
ldconfig
cd ../..

echo ">>> Cloning swift-corelibs-libdispatch..."
if [ ! -d "swift-corelibs-libdispatch" ]; then
    git clone --recursive https://github.com/apple/swift-corelibs-libdispatch.git
fi

echo ">>> Building swift-corelibs-libdispatch..."
cd swift-corelibs-libdispatch
mkdir -p build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DINSTALL_PRIVATE_HEADERS=YES
make -j$(nproc)
make install
ldconfig
cd ../..

echo ">>> Cloning GNUstep Base..."
if [ ! -d "libs-base" ]; then
    git clone https://github.com/gnustep/libs-base.git
fi

echo ">>> Building GNUstep Base..."
# Explicitly verify if we found libdispatch
cd libs-base
./configure \
    --with-ffi-library=/usr/lib/x86_64-linux-gnu \
    --with-ffi-include=/usr/include/x86_64-linux-gnu 
make -j$(nproc)
make install
cd ..

echo ">>> Verifying installation..."
gnustep-config --version
curl-config --version

echo ">>> Done! Source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh to start."
