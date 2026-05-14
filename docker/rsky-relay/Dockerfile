# Dockerfile for rsky-relay — AT Protocol relay (blacksky-algorithms/rsky)
#
# Multi-stage build: compiles from source, ships a minimal runtime.
# The rsky-relay binary crawls PDS hosts and serves a firehose via
# com.atproto.sync.subscribeRepos.
#
# Build context should be the rsky workspace root (not rsky-relay/).
#
# Patches in patches/ are applied before compilation to fix hardcoding
# issues that prevent rsky-relay from working in a local Docker topology:
#   01: Bind to 0.0.0.0 instead of 127.0.0.1
#   02: RELAY_CRAWL_SCHEME env var (default: wss)
#   03: RELAY_PLC_URL env var (default: https://plc.directory)
#   04: RELAY_DISCOVERY_ALLOW_HTTP env var (default: false)
#   05: RELAY_PORT env var (default: 9000/9001)
#
# These patches are backward-compatible — all defaults preserve upstream behavior.

# ── Builder ──────────────────────────────────────────────────────────────────
FROM rust:bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/rsky
COPY . .

# Apply topology compatibility patches.
# Patches are ordered and must apply cleanly; build fails if any patch fails.
COPY patches/ /tmp/rsky-patches/
RUN for patch in /tmp/rsky-patches/[0-9]*.patch; do \
        echo "Applying $(basename "$patch")..." && \
        patch -p1 --no-backup-if-mismatch < "$patch" || \
        { echo "FATAL: patch $(basename "$patch") failed" >&2; exit 1; }; \
    done && \
    rm -rf /tmp/rsky-patches

RUN cargo build --release -p rsky-relay 2>&1

# ── Runtime ──────────────────────────────────────────────────────────────────
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    wget \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/src/rsky/target/release/rsky-relay /usr/local/bin/rsky-relay

RUN mkdir -p /data/db && chmod -R 777 /data
VOLUME ["/data"]

# Working directory is /data so SQLite databases (relay.db, plc_directory.db)
# land in the persistent volume alongside the fjall KV store.
WORKDIR /data

ENV RELAY_DB_PATH=/data/db

ENTRYPOINT ["rsky-relay"]
CMD ["--help"]
