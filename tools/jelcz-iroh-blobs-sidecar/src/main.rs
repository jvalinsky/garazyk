// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

use std::net::SocketAddr;
use std::path::PathBuf;

use clap::Parser;
use jelcz_iroh_blobs_sidecar::ipc;

#[derive(Parser, Debug)]
#[command(name = "jelcz-iroh-blobs-sidecar")]
#[command(about = "Garazyk Track A iroh-blobs lab sidecar (iroh 1.x)")]
struct Args {
    /// Loopback TCP listen address (default 127.0.0.1:17352).
    #[arg(long, default_value = "127.0.0.1:17352")]
    listen: SocketAddr,

    /// Allow binding non-loopback addresses (Docker lab only).
    #[arg(long, default_value_t = false)]
    bind_all: bool,

    /// Unix domain socket path. When set, serves IPC on UDS instead of TCP.
    #[arg(long)]
    unix: Option<PathBuf>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();

    let args = Args::parse();
    if let Some(path) = args.unix {
        ipc::serve_unix(&path).await
    } else {
        if !args.bind_all && !args.listen.ip().is_loopback() {
            anyhow::bail!(
                "refusing to bind non-loopback address {} (pass --bind-all for Docker lab)",
                args.listen
            );
        }
        ipc::serve_tcp(args.listen).await
    }
}
