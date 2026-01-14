# Build ATProtoPDS with GNUstep from source
FROM ubuntu:22.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# 1. Install System Dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    clang \
    cmake \
    git \
    make \
    curl \
    wget \
    pkg-config \
    libffi-dev \
    libxml2-dev \
    libgnutls28-dev \
    libicu-dev \
    libxslt1-dev \
    libssl-dev \
    libsqlite3-dev \
    zlib1g-dev \
    libdispatch-dev \
    libblocksruntime-dev \
    libkqueue-dev \
    libpthread-workqueue-dev \
    libqrencode-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# 2. Build GNUstep Make
# Since it's not a submodule, we download it.
RUN wget https://github.com/gnustep/tools-make/archive/refs/tags/make-2_9_2.tar.gz && \
    tar -xzf make-2_9_2.tar.gz && \
    cd tools-make-make-2_9_2 && \
    ./configure --with-layout=gnustep \
    --enable-objc-nonfragile-abi \
    --enable-multithreading \
    --with-library-combo=ng-gnu-gnu && \
    make install

# Set environment variables for building the rest
ENV GNUSTEP_MAKEFILES=/usr/GNUstep/System/Library/Makefiles
ENV PATH="/usr/GNUstep/System/Tools:${PATH}"
ENV LIBRARY_PATH="/usr/GNUstep/Local/Library/Libraries:/usr/GNUstep/System/Library/Libraries:${LIBRARY_PATH}"
ENV LD_LIBRARY_PATH="/usr/GNUstep/Local/Library/Libraries:/usr/GNUstep/System/Library/Libraries:${LD_LIBRARY_PATH}"
ENV CPATH="/usr/GNUstep/Local/Library/Headers:/usr/GNUstep/System/Library/Headers:${CPATH}"

# 3. Build libobjc2 (Objective-C Runtime)
# We use the submodule in reference/libobjc2
COPY reference/libobjc2 /src/libobjc2
RUN cd /src/libobjc2 && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DTESTS=OFF && \
    make -j$(nproc) install

# 4. Build GNUstep Base
# We use the submodule in reference/gnustep-base
COPY reference/gnustep-base /src/gnustep-base
RUN cd /src/gnustep-base && \
    ./configure --with-library-combo=ng-gnu-gnu && \
    make -j$(nproc) install

# 5. Build ATProtoPDS Server
WORKDIR /app
COPY . .

# We build specifically the server target in Release mode
# Note: We must point to our custom built GNUstep
RUN . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && \
    cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_OBJC_COMPILER=/usr/bin/clang \
    -DCMAKE_PREFIX_PATH=/usr/GNUstep/System:/usr/GNUstep/Local \
    -DOBJC_RUNTIME:FILEPATH=/usr/GNUstep/Local/Library/Libraries/libobjc.so \
    -DLIBRARY_OUTPUT_PATH=/app/build/lib \
    -DCMAKE_LIBRARY_PATH=/usr/GNUstep/Local/Library/Libraries:/usr/GNUstep/System/Library/Libraries \
    -DBUILD_TESTS=OFF \
    -DBUILD_FUZZERS=OFF && \
    cmake --build build --target atprotopds-server --parallel $(nproc)

# Expose the default PDS port
EXPOSE 2583

# Run the server
ENTRYPOINT ["./build/bin/atprotopds"]
CMD ["serve"]
