// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

//! Private, lab-only peer for executable Track B rejection evidence.
//!
//! This peer speaks the same pinned postcard/irpc wire as the bridge. It is
//! never part of the production receive path and exposes no host port.

use std::{
    ffi::CString,
    fs::File,
    io::{self, Read, Write},
    os::{fd::FromRawFd, unix::ffi::OsStrExt},
    path::{Path, PathBuf},
};

use bytes::Bytes;
use clap::ValueEnum;
use iroh::{
    Endpoint, NodeAddr,
    endpoint::Connection,
    protocol::{AcceptError, ProtocolHandler, Router},
};
use iroh_base::{SecretKey, ticket::NodeTicket};
use irpc::WithChannels;
use irpc_iroh::IrohRemoteConnection;
use serde::{Deserialize, Serialize};

use crate::{
    bridge::STREAMPLACE_ALPN,
    transport::{read_bounded_request, wire},
};

const FAULT_ALPN: &str = "/iroh/streamplace/fault/1";
const MAX_CONTROL_WIRE_BYTES: usize = 8 * 1024;
const MAX_STATE_BYTES: usize = 8 * 1024;

#[derive(Clone, Copy, Debug, Deserialize, Serialize, ValueEnum)]
#[serde(rename_all = "kebab-case")]
pub enum FaultMode {
    WrongStreamer,
    WrongAlpn,
    WrongFrom,
    CorruptMuxl,
    OversizeSegment,
    DropSubscribe,
}

impl FaultMode {
    fn label(self) -> &'static str {
        match self {
            Self::WrongStreamer => "wrong-streamer",
            Self::WrongAlpn => "wrong-alpn",
            Self::WrongFrom => "wrong-from",
            Self::CorruptMuxl => "corrupt-muxl",
            Self::OversizeSegment => "oversize-segment",
            Self::DropSubscribe => "drop-subscribe",
        }
    }

    fn alpn(self) -> &'static str {
        match self {
            Self::WrongAlpn => FAULT_ALPN,
            _ => STREAMPLACE_ALPN,
        }
    }
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct FaultPeerState {
    contract_version: String,
    mode: String,
    node_id: String,
    iroh_ticket: String,
    advertised_alpn: String,
    configured_segment_limit: usize,
}

#[derive(Clone, Debug)]
struct FaultProtocol {
    endpoint: Endpoint,
    mode: FaultMode,
    expected_streamer: String,
    max_segment_bytes: usize,
}

impl FaultProtocol {
    async fn handle_subscribe(
        &self,
        authenticated_bridge: iroh::NodeId,
        message: WithChannels<wire::Subscribe, wire::Protocol>,
    ) -> Result<(), AcceptError> {
        if message.inner.remote_id != authenticated_bridge
            || message.inner.key != self.expected_streamer
        {
            return Err(AcceptError::from_err(io::Error::new(
                io::ErrorKind::PermissionDenied,
                "fault peer received an unbound subscription",
            )));
        }
        if matches!(self.mode, FaultMode::DropSubscribe) {
            return Err(AcceptError::from_err(io::Error::new(
                io::ErrorKind::ConnectionAborted,
                "fault peer dropped Subscribe before acknowledgement",
            )));
        }
        message.tx.send(()).await.map_err(AcceptError::from_err)?;

        let from = if matches!(self.mode, FaultMode::WrongFrom) {
            SecretKey::from_bytes(&[0x5a; 32]).public()
        } else {
            self.endpoint.node_id()
        };
        let key = if matches!(self.mode, FaultMode::WrongStreamer) {
            "did:plc:track-b-wrong-streamer".to_owned()
        } else {
            self.expected_streamer.clone()
        };
        let data = match self.mode {
            FaultMode::OversizeSegment => {
                Bytes::from(vec![0xa5; self.max_segment_bytes.saturating_add(1)])
            }
            FaultMode::WrongStreamer | FaultMode::WrongFrom => Bytes::from_static(b"fault"),
            FaultMode::CorruptMuxl => Bytes::from_static(b"not-a-muxl-segment"),
            FaultMode::WrongAlpn | FaultMode::DropSubscribe => return Ok(()),
        };
        // Streamplace pushes over a peer-initiated connection back to the
        // subscriber. The accepted Subscribe connection has already taught
        // this endpoint the authenticated bridge's live route.
        let client = irpc::Client::<wire::Protocol>::boxed(IrohRemoteConnection::new(
            self.endpoint.clone(),
            NodeAddr::new(authenticated_bridge),
            STREAMPLACE_ALPN.as_bytes().to_vec(),
        ));
        // Rejection is the intended outcome for every mode except corrupt
        // MUXL, which the transport accepts and Jelcz independently rejects.
        let _ = client.rpc(wire::RecvSegment { from, key, data }).await;
        Ok(())
    }
}

impl ProtocolHandler for FaultProtocol {
    fn accept(
        &self,
        connection: Connection,
    ) -> impl std::future::Future<Output = Result<(), AcceptError>> + Send {
        let protocol = self.clone();
        async move {
            let authenticated_bridge = connection
                .remote_node_id()
                .map_err(|error| AcceptError::from_err(io::Error::other(error)))?;
            loop {
                let Some(message) = read_bounded_request(&connection, MAX_CONTROL_WIRE_BYTES)
                    .await
                    .map_err(AcceptError::from_err)?
                else {
                    return Ok(());
                };
                match message {
                    wire::Message::Subscribe(message) => {
                        protocol
                            .handle_subscribe(authenticated_bridge, message)
                            .await?;
                    }
                    wire::Message::Unsubscribe(WithChannels { tx, inner, .. }) => {
                        if inner.remote_id != authenticated_bridge {
                            return Err(AcceptError::from_err(io::Error::new(
                                io::ErrorKind::PermissionDenied,
                                "fault peer received an unbound unsubscribe",
                            )));
                        }
                        tx.send(()).await.map_err(AcceptError::from_err)?;
                    }
                    wire::Message::RecvSegment(_) => {
                        return Err(AcceptError::from_err(io::Error::new(
                            io::ErrorKind::PermissionDenied,
                            "fault peer does not accept pushed segments",
                        )));
                    }
                }
            }
        }
    }
}

/// Run a private fault peer and persist its public NodeTicket for `docker exec`.
pub async fn serve(
    mode: FaultMode,
    streamer: String,
    max_segment_bytes: usize,
    state_file: PathBuf,
) -> anyhow::Result<()> {
    if !streamer.starts_with("did:") || streamer.len() > 2_048 {
        anyhow::bail!("fault peer requires a bounded streamer DID");
    }
    if max_segment_bytes == 0 || max_segment_bytes > 64 * 1024 * 1024 {
        anyhow::bail!("fault peer segment limit is invalid");
    }
    let endpoint = Endpoint::builder().bind().await?;
    let router = Router::builder(endpoint.clone())
        .accept(
            mode.alpn().as_bytes(),
            FaultProtocol {
                endpoint: endpoint.clone(),
                mode,
                expected_streamer: streamer,
                max_segment_bytes,
            },
        )
        .spawn();
    let mut node_addr = endpoint.node_addr();
    for _ in 0..40 {
        if !node_addr.direct_addresses.is_empty() || node_addr.relay_url.is_some() {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
        node_addr = endpoint.node_addr();
    }
    if node_addr.direct_addresses.is_empty() && node_addr.relay_url.is_none() {
        anyhow::bail!("fault peer has no advertised route");
    }
    let state = FaultPeerState {
        contract_version: "jelcz-streamplace-track-b-fault-peer/v1".into(),
        mode: mode.label().into(),
        node_id: endpoint.node_id().to_string(),
        iroh_ticket: NodeTicket::new(node_addr).to_string(),
        advertised_alpn: mode.alpn().into(),
        configured_segment_limit: max_segment_bytes,
    };
    write_state(&state_file, &serde_json::to_vec(&state)?)?;
    tracing::info!(mode = mode.label(), "Track B private fault peer ready");
    let _router = router;
    std::future::pending::<()>().await;
    Ok(())
}

/// Read the private state file. Callers must redact `irohTicket` from artifacts.
pub fn read_state_json(path: &Path) -> anyhow::Result<String> {
    validate_state_path(path)?;
    let c_path = CString::new(path.as_os_str().as_bytes())?;
    let fd = unsafe { libc::open(c_path.as_ptr(), libc::O_RDONLY | libc::O_NOFOLLOW) };
    if fd < 0 {
        return Err(io::Error::last_os_error().into());
    }
    let mut file = unsafe { File::from_raw_fd(fd) };
    let mut bytes = Vec::new();
    Read::by_ref(&mut file)
        .take((MAX_STATE_BYTES + 1) as u64)
        .read_to_end(&mut bytes)?;
    if bytes.len() > MAX_STATE_BYTES {
        anyhow::bail!("fault peer state exceeds limit");
    }
    let state: FaultPeerState = serde_json::from_slice(&bytes)?;
    Ok(serde_json::to_string(&state)?)
}

fn write_state(path: &Path, bytes: &[u8]) -> anyhow::Result<()> {
    validate_state_path(path)?;
    if bytes.len() > MAX_STATE_BYTES {
        anyhow::bail!("fault peer state exceeds limit");
    }
    let c_path = CString::new(path.as_os_str().as_bytes())?;
    let fd = unsafe {
        libc::open(
            c_path.as_ptr(),
            libc::O_WRONLY | libc::O_CREAT | libc::O_TRUNC | libc::O_NOFOLLOW | libc::O_CLOEXEC,
            0o600,
        )
    };
    if fd < 0 {
        return Err(io::Error::last_os_error().into());
    }
    let mut file = unsafe { File::from_raw_fd(fd) };
    file.write_all(bytes)?;
    file.sync_all()?;
    Ok(())
}

fn validate_state_path(path: &Path) -> anyhow::Result<()> {
    if !path.is_absolute() || path.parent() != Some(Path::new("/tmp")) {
        anyhow::bail!("fault peer state file must be a direct child of /tmp");
    }
    if path.file_name().is_none() {
        anyhow::bail!("fault peer state file needs a file name");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fault_modes_are_explicit_about_alpn() {
        assert_eq!(FaultMode::WrongAlpn.alpn(), FAULT_ALPN);
        assert_eq!(FaultMode::CorruptMuxl.alpn(), STREAMPLACE_ALPN);
    }

    #[test]
    fn state_path_is_narrowly_scoped() {
        assert!(validate_state_path(Path::new("/tmp/fault-peer.json")).is_ok());
        assert!(validate_state_path(Path::new("/var/tmp/fault-peer.json")).is_err());
        assert!(validate_state_path(Path::new("/tmp/nested/fault-peer.json")).is_err());
    }
}
