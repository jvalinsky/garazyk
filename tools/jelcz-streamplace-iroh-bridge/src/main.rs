// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

use std::{net::SocketAddr, path::PathBuf};

use clap::Parser;
use jelcz_streamplace_iroh_bridge::{evidence::EvidenceStore, fault_peer, ipc};

#[derive(Debug, Parser)]
#[command(name = "jelcz-streamplace-iroh-bridge")]
#[command(about = "Fail-closed Streamplace live iroh receive bridge")]
struct Args {
    #[command(subcommand)]
    command: Option<Command>,

    /// Loopback-only TCP IPC address (ignored when --unix is supplied).
    #[arg(long, default_value = "127.0.0.1:17353")]
    listen: SocketAddr,

    /// Existing-parent Unix socket path for local IPC.
    #[arg(long)]
    unix: Option<PathBuf>,

    /// Process-persistent, atomic bridge evidence file. Must be beneath /tmp.
    #[arg(long, global = true)]
    evidence_file: Option<PathBuf>,
}

#[derive(Debug, clap::Subcommand)]
enum Command {
    /// Run the local receive-only IPC bridge (Compose/scenario entry point).
    Serve {
        /// Reserved by the scenario contract; this bridge does not consume it.
        #[arg(long)]
        firehose: Option<String>,
        /// Streamer DID to subscribe to in the orchestrated smoke.
        #[arg(long)]
        streamer: Option<String>,
        /// Must be the pinned Streamplace ALPN.
        #[arg(long, default_value = "/iroh/streamplace/1")]
        alpn: String,
        #[arg(long, default_value_t = 8 * 1024 * 1024)]
        max_segment_bytes: usize,
        #[arg(long, default_value_t = 5)]
        max_reconnects: u8,
        /// Permit private-container IPC instead of the standalone loopback default.
        #[arg(long)]
        bind_all: bool,
    },
    /// Emit the Streamplace Track B opt-in acceptance-chain status.
    AcceptanceReport {
        /// Emit the stable JSON schema required by the scenario lane.
        #[arg(long)]
        json: bool,
    },
    /// Run a private, lab-only peer that exercises one rejection path.
    FaultPeer {
        #[arg(long, value_enum)]
        mode: fault_peer::FaultMode,
        #[arg(long)]
        streamer: String,
        #[arg(long, default_value_t = 8 * 1024 * 1024)]
        max_segment_bytes: usize,
        #[arg(long, default_value = "/tmp/jelcz-streamplace-fault-peer.json")]
        state_file: PathBuf,
    },
    /// Emit the running fault peer's ticket for the host-side scenario only.
    FaultTicket {
        #[arg(long)]
        json: bool,
        #[arg(long, default_value = "/tmp/jelcz-streamplace-fault-peer.json")]
        state_file: PathBuf,
    },
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
    let evidence_path = args.evidence_file.unwrap_or_else(|| {
        std::env::var_os("JELCZ_STREAMPLACE_IROH_BRIDGE_EVIDENCE_FILE")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/tmp/jelcz-streamplace-iroh-bridge-evidence.json"))
    });
    if let Some(Command::AcceptanceReport { json }) = args.command.as_ref() {
        if !*json {
            anyhow::bail!("acceptance-report requires --json");
        }
        match EvidenceStore::read(&evidence_path) {
            Ok(report) => {
                let complete = report.has_complete_bridge_owned_evidence();
                println!(
                    "{}",
                    serde_json::json!({
                        "contractVersion": report.contract_version,
                        "bridgeOwnedEvidenceComplete": complete,
                        "sessions": report.sessions,
                        "scope": "bridge transport observations plus capability-bound Jelcz structural MUXL attestations only",
                    })
                );
                if !complete {
                    anyhow::bail!("bridge-owned live evidence is incomplete");
                }
                return Ok(());
            }
            Err(_) => {
                println!(
                    "{}",
                    serde_json::json!({
                        "contractVersion": "jelcz-streamplace-iroh-bridge-evidence/v1",
                        "bridgeOwnedEvidenceComplete": false,
                        "sessions": {},
                        "scope": "bridge transport observations plus capability-bound Jelcz structural MUXL attestations only",
                    })
                );
                anyhow::bail!("bridge evidence is unavailable");
            }
        }
    }
    if let Some(Command::FaultPeer {
        mode,
        streamer,
        max_segment_bytes,
        state_file,
    }) = args.command.as_ref()
    {
        return fault_peer::serve(
            *mode,
            streamer.clone(),
            *max_segment_bytes,
            state_file.clone(),
        )
        .await;
    }
    if let Some(Command::FaultTicket { json, state_file }) = args.command.as_ref() {
        if !*json {
            anyhow::bail!("fault-ticket requires --json");
        }
        println!("{}", fault_peer::read_state_json(state_file)?);
        return Ok(());
    }
    if let Some(Command::Serve {
        firehose: _,
        streamer: _,
        alpn,
        max_segment_bytes,
        max_reconnects,
        bind_all,
    }) = args.command
    {
        if alpn != "/iroh/streamplace/1" {
            anyhow::bail!("refusing unexpected ALPN");
        }
        let config = jelcz_streamplace_iroh_bridge::BridgeConfig {
            max_segment_bytes,
            reconnect_attempt_limit: max_reconnects,
            evidence_path,
            ..Default::default()
        };
        config.validate()?;
        let capability_token = std::env::var("JELCZ_STREAMPLACE_IROH_BRIDGE_TOKEN")
            .map_err(|_| anyhow::anyhow!("JELCZ_STREAMPLACE_IROH_BRIDGE_TOKEN is required"))?;
        let listen = if bind_all {
            SocketAddr::new(std::net::Ipv4Addr::UNSPECIFIED.into(), args.listen.port())
        } else {
            args.listen
        };
        return match args.unix {
            Some(path) => ipc::serve_unix(&path, config, capability_token).await,
            None => ipc::serve_tcp(listen, config, capability_token, bind_all).await,
        };
    }
    let capability_token = std::env::var("JELCZ_STREAMPLACE_IROH_BRIDGE_TOKEN")
        .map_err(|_| anyhow::anyhow!("JELCZ_STREAMPLACE_IROH_BRIDGE_TOKEN is required"))?;
    match args.unix {
        Some(path) => {
            ipc::serve_unix(
                &path,
                jelcz_streamplace_iroh_bridge::BridgeConfig {
                    evidence_path,
                    ..Default::default()
                },
                capability_token,
            )
            .await
        }
        None => {
            ipc::serve_tcp(
                args.listen,
                jelcz_streamplace_iroh_bridge::BridgeConfig {
                    evidence_path,
                    ..Default::default()
                },
                capability_token,
                false,
            )
            .await
        }
    }
}
