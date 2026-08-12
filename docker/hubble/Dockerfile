# Dockerfile for Hubble — full-network atproto repo mirror (microcosm.blue)
#
# Multi-stage build: compiles from source, ships a minimal runtime.
# Hubble backfills and live-syncs repos directly from a PDS (or relay),
# preferring the STAR-lite v0 export (application/x.microcosm.star-lite)
# when a host offers it.
#
# Build context should be the Hubble repo root (https://tangled.org/microcosm.blue/hubble),
# not this directory.
#
# Requires nightly rustc: the crate uses if-let chains in match guards,
# which are not yet on stable even under the 2024 edition.
#
# Patches in patches/ are applied before compilation to fix hardcoding that
# prevents Hubble from working in a local Docker topology without TLS:
#   01: HUBBLE_ALLOW_HTTP env var — use http/ws instead of https/wss for
#       upstream (PDS/relay) requests, including the subscribeRepos socket
#   02: HUBBLE_PLC_URL / --plc-url — point did:plc resolution at a local PLC
#       instead of the hardcoded https://plc.directory
#
# Both patches are backward-compatible: omitting the flags/env vars preserves
# upstream behavior (https/wss only, plc.directory).

# ── Builder ──────────────────────────────────────────────────────────────────
FROM rust:bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    cmake \
    clang \
    llvm \
    libclang-dev \
    && rm -rf /var/lib/apt/lists/*

RUN rustup toolchain install nightly && rustup default nightly

WORKDIR /usr/src/hubble
COPY . .

# Apply topology compatibility patches.
# Patches are ordered and must apply cleanly; build fails if any patch fails.
COPY patches/ /tmp/hubble-patches/
RUN for patch in /tmp/hubble-patches/[0-9]*.patch; do \
        echo "Applying $(basename "$patch")..." && \
        patch -p1 --no-backup-if-mismatch < "$patch" || \
        { echo "FATAL: patch $(basename "$patch") failed" >&2; exit 1; }; \
    done && \
    rm -rf /tmp/hubble-patches

RUN cargo build --release -p hubble 2>&1

# ── Runtime ──────────────────────────────────────────────────────────────────
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    wget \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/src/hubble/target/release/hubble /usr/local/bin/hubble

RUN mkdir -p /data && chmod -R 777 /data
VOLUME ["/data"]

WORKDIR /data

EXPOSE 3000 9000

ENTRYPOINT ["hubble"]
CMD ["--help"]
