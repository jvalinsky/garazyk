# Dockerfile for rsky-pds — Rust AT Protocol PDS (blacksky-algorithms/rsky)
#
# This overlay fixes the upstream Dockerfile:
# - Broken CMD (never actually runs the binary)
# - No diesel CLI for running migrations
# - No wget/curl in runtime for health checks
# - No entrypoint script for migration-before-start

# ── Builder ──────────────────────────────────────────────────────────────────
FROM rust AS builder

WORKDIR /usr/src/rsky

# Copy workspace and all crate manifests for dependency resolution
COPY Cargo.toml Cargo.lock ./
COPY palomar-sync/Cargo.toml palomar-sync/Cargo.toml
COPY rsky-common/Cargo.toml rsky-common/Cargo.toml
COPY rsky-crypto/Cargo.toml rsky-crypto/Cargo.toml
COPY rsky-feedgen/Cargo.toml rsky-feedgen/Cargo.toml
COPY rsky-firehose/Cargo.toml rsky-firehose/Cargo.toml
COPY rsky-identity/Cargo.toml rsky-identity/Cargo.toml
COPY rsky-jetstream-subscriber/Cargo.toml rsky-jetstream-subscriber/Cargo.toml
COPY rsky-labeler/Cargo.toml rsky-labeler/Cargo.toml
COPY rsky-lexicon/Cargo.toml rsky-lexicon/Cargo.toml
COPY rsky-pds/Cargo.toml rsky-pds/Cargo.toml
COPY rsky-relay/Cargo.toml rsky-relay/Cargo.toml
COPY rsky-repo/Cargo.toml rsky-repo/Cargo.toml
COPY rsky-satnav/Cargo.toml rsky-satnav/Cargo.toml
COPY rsky-syntax/Cargo.toml rsky-syntax/Cargo.toml
COPY rsky-video/Cargo.toml rsky-video/Cargo.toml
COPY rsky-wintermute/Cargo.toml rsky-wintermute/Cargo.toml

# Copy real source for library crates that rsky-pds depends on
COPY rsky-common/src rsky-common/src
COPY rsky-crypto/src rsky-crypto/src
COPY rsky-identity/src rsky-identity/src
COPY rsky-lexicon/src rsky-lexicon/src
COPY rsky-repo/src rsky-repo/src
COPY rsky-syntax/src rsky-syntax/src

# Stub out binary workspace members so cargo can resolve the workspace
RUN mkdir -p \
    palomar-sync/src rsky-feedgen/src rsky-firehose/src \
    rsky-jetstream-subscriber/src rsky-labeler/src rsky-relay/src \
    rsky-satnav/src rsky-video/src rsky-wintermute/src && \
    for crate in palomar-sync rsky-feedgen rsky-firehose rsky-jetstream-subscriber \
        rsky-labeler rsky-relay rsky-satnav rsky-video rsky-wintermute; do \
        echo 'fn main() {}' > $crate/src/main.rs; \
    done

# Create an empty src directory to trick Cargo into thinking it's a valid Rust project
RUN mkdir -p rsky-pds/src && echo "fn main() {}" > rsky-pds/src/main.rs

# Install production dependencies and build a release artifact.
RUN cargo build --release --package rsky-pds

# Now copy the real source code and build the final binary
COPY rsky-pds/src rsky-pds/src
COPY rsky-pds/migrations rsky-pds/migrations
COPY rsky-pds/diesel.toml rsky-pds/diesel.toml

# Apply patches for local Docker compatibility
COPY patches/ patches/
RUN for p in patches/*.patch; do \
        echo "Applying $p..." && patch -p1 < "$p" || exit 1; \
    done

RUN cargo build --release --package rsky-pds

# Install diesel CLI for running migrations at startup
RUN cargo install diesel_cli --version 2.2.0 --no-default-features --features postgres

# ── Runtime ──────────────────────────────────────────────────────────────────
FROM debian:bullseye-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates wget libpq5 && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/rsky
COPY --from=builder /usr/src/rsky/target/release/rsky-pds rsky-pds
COPY --from=builder /usr/local/cargo/bin/diesel diesel
COPY --from=builder /usr/src/rsky/rsky-pds/migrations rsky-pds/migrations
COPY --from=builder /usr/src/rsky/rsky-pds/diesel.toml rsky-pds/diesel.toml
COPY entrypoint.sh entrypoint.sh

RUN chmod +x entrypoint.sh

LABEL org.opencontainers.image.source=https://github.com/blacksky-algorithms/rsky

ENV ROCKET_ADDRESS=0.0.0.0
ENV ROCKET_PORT=2583

EXPOSE 2583
ENTRYPOINT ["./entrypoint.sh"]
