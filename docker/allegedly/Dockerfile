# Dockerfile for Allegedly — PLC mirror/wrapper (microcosm.blue)
#
# Multi-stage build: compiles from source, ships a minimal runtime.
# The Allegedly binary wraps a reference PLC server, providing TLS
# termination, rate limiting, and write-forwarding.
#
# Build context should be the Allegedly repo root.

# ── Builder ──────────────────────────────────────────────────────────────────
FROM rust:bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/allegedly
COPY . .

RUN cargo install --path . --bin allegedly --root /usr/local --locked 2>&1

# ── Runtime ──────────────────────────────────────────────────────────────────
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    wget \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/allegedly /usr/local/bin/allegedly

ENTRYPOINT ["allegedly"]
CMD ["--help"]
