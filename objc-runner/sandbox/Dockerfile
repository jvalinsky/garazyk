# Objective-C Code Execution Sandbox
# Builds GNUstep with libobjc2 (v2 runtime) from source for ARC support

FROM ubuntu:22.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    clang \
    cmake \
    git \
    libffi-dev \
    libxml2-dev \
    libxslt1-dev \
    libgnutls28-dev \
    libicu-dev \
    libcurl4-gnutls-dev \
    libblocksruntime-dev \
    libdispatch-dev \
    ninja-build \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set clang as default compiler
ENV CC=clang
ENV CXX=clang++
ENV CFLAGS="-fblocks"
ENV LDFLAGS="-ldispatch"

WORKDIR /build

# Build libobjc2 (GNUstep v2 runtime with ARC support)
RUN git clone --depth 1 https://github.com/gnustep/libobjc2.git && \
    cd libobjc2 && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -G Ninja && \
    ninja && ninja install && \
    ldconfig

# Build GNUstep Make
RUN git clone --depth 1 https://github.com/gnustep/tools-make.git && \
    cd tools-make && \
    ./configure --with-library-combo=ng-gnu-gnu && \
    make && make install

# Source GNUstep environment
ENV GNUSTEP_MAKEFILES=/usr/local/share/GNUstep/Makefiles
RUN echo ". /usr/local/share/GNUstep/Makefiles/GNUstep.sh" >> /etc/bash.bashrc

# Build GNUstep Base (Foundation)
RUN git clone --depth 1 https://github.com/gnustep/libs-base.git && \
    cd libs-base && \
    . /usr/local/share/GNUstep/Makefiles/GNUstep.sh && \
    ./configure --disable-tls --disable-xslt --disable-icu --disable-xml && \
    make -j$(nproc) && make install && \
    ldconfig

# Clean up build files to reduce image size
RUN rm -rf /build

# Create sandbox user (non-root)
RUN useradd -m -s /bin/bash -u 1000 sandbox

# Create working directories
RUN mkdir -p /sandbox /output && \
    chown sandbox:sandbox /sandbox /output

# Copy execution script
COPY execute.sh /usr/local/bin/execute.sh
RUN chmod +x /usr/local/bin/execute.sh

# Switch to non-root user
USER sandbox
WORKDIR /sandbox

# Set GNUstep environment for sandbox user
ENV GNUSTEP_MAKEFILES=/usr/local/share/GNUstep/Makefiles

# Default entrypoint
ENTRYPOINT ["/usr/local/bin/execute.sh"]
