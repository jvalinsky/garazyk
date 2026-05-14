# Dockerfile for rsky-wintermute — AT Protocol firehose indexer (blacksky-algorithms/rsky)
#
# Multi-stage Rust build. Wintermute consumes the firehose, backfills repos,
# and indexes records into PostgreSQL (bsky dataplane schema).
#
# Build context should be the rsky workspace root (not rsky-wintermute/).
#
# The bsky schema must already exist in PostgreSQL — the bsky-dataplane sidecar
# creates it via Kysely migrations. Wintermute uses ON CONFLICT for all INSERTs,
# so it's safe to start even if the dataplane is still running migrations.
#
# Patches in patches/ are applied before compilation to fix hardcoding
# issues that prevent wintermute from working in a local Docker topology:
#   01: ws:// scheme support (wintermute hardcodes wss:// for relay connections)
#
# This patch is backward-compatible — bare hostnames still default to wss://.

# ── Builder ──────────────────────────────────────────────────────────────────
FROM rust:bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    libpq-dev \
    cmake \
    make \
    clang \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/rsky
COPY . .

# Apply topology compatibility patches.
# Patches are ordered and must apply cleanly; build fails if any patch fails.
COPY patches/ /tmp/wintermute-patches/
RUN for patch in /tmp/wintermute-patches/[0-9]*.patch; do \
        echo "Applying $(basename "$patch")..." && \
        patch -p1 --no-backup-if-mismatch < "$patch" || \
        { echo "FATAL: patch $(basename "$patch") failed" >&2; exit 1; }; \
    done && \
    rm -rf /tmp/wintermute-patches

RUN cargo build --release -p rsky-wintermute 2>&1

# ── Runtime ──────────────────────────────────────────────────────────────────
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    libpq5 \
    postgresql-client \
    wget \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/src/rsky/target/release/wintermute /usr/local/bin/wintermute
COPY --from=builder /usr/src/rsky/docker/wintermute/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

RUN mkdir -p /data && chmod -R 777 /data
VOLUME ["/data"]

WORKDIR /data

ENV METRICS_PORT=9090
ENV RUST_LOG=info

EXPOSE 9090

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
