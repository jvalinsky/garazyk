# Dockerfile for zlay — AT Protocol relay in Zig (zzstoatzz.io/zlay)
#
# Multi-stage build: compiles natively inside the container's architecture.
# Uses Debian (glibc) because zig's C++ codegen for musl
# produces illegal instructions in RocksDB's LRU cache.
#
# This overlay uses the stable Zig 0.16.0 release instead of the
# nightly build referenced in the upstream Dockerfile (which 404s
# after nightly rotation). The uring networking patch is skipped
# because zlay uses Io.Threaded (not Evented/io_uring).
#
# Builds natively (no --platform=linux/amd64) to avoid Rosetta 2
# translate-c BSS overflow on Apple Silicon when processing RocksDB
# C headers.

# ── Builder ──────────────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS builder
RUN apt-get update && apt-get install -y --no-install-recommends curl xz-utils ca-certificates && rm -rf /var/lib/apt/lists/*

# Install Zig — pick the right binary for the container's architecture
RUN ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in \
        amd64)  ZIG_ARCH=x86_64 ;; \
        arm64)  ZIG_ARCH=aarch64 ;; \
        *)      echo "unsupported arch: $ARCH" && exit 1 ;; \
    esac && \
    curl -fSL "https://ziglang.org/download/0.16.0/zig-${ZIG_ARCH}-linux-0.16.0.tar.xz" \
    | tar xJ -C /opt && \
    ln -s "/opt/zig-${ZIG_ARCH}-linux-0.16.0/zig" /usr/local/bin/zig

WORKDIR /build

# fetch dependencies first (cacheable — only changes when build.zig.zon changes)
COPY build.zig build.zig.zon ./
RUN zig build --fetch-only 2>/dev/null || true

# then copy source and build
COPY src/ src/
COPY patches/ patches/
# Note: uring-networking.patch is NOT applied — zlay uses Io.Threaded, not Evented
RUN zig build -Doptimize=ReleaseSafe -Dcpu=baseline

# ── Runtime ──────────────────────────────────────────────────────────────────
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates wget && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/zig-out/bin/zlay /usr/local/bin/zlay
RUN mkdir -p /data/events /data/collection-index
ENV RELAY_DATA_DIR=/data/events
EXPOSE 3000 3001
ENTRYPOINT ["/usr/local/bin/zlay"]
