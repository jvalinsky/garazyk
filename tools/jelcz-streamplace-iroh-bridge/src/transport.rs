// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

//! Pin-specific Streamplace wire adapter.
//!
//! This reproduces only the three documented irpc messages from the pinned
//! Streamplace source. It intentionally does not import upstream code: the
//! upstream crate is staticlib/cdylib-only and its generic handler drops the
//! authenticated connection identity. The `ProtocolHandler` below captures
//! `Connection::remote_node_id()` and enforces it at the receive sink.

use std::{collections::HashMap, io, str::FromStr, sync::Arc};

use bytes::Bytes;
use iroh::{
    Endpoint, NodeAddr, NodeId,
    endpoint::Connection,
    protocol::{AcceptError, ProtocolHandler, Router},
};
use iroh_base::ticket::NodeTicket;
use irpc::{
    WithChannels, channel::oneshot, rpc::RemoteService, rpc_requests, util::AsyncReadVarintExt,
};
use irpc_iroh::IrohRemoteConnection;
use serde::{Deserialize, Serialize};
use tokio::sync::{Mutex, OwnedSemaphorePermit, Semaphore, mpsc};

use crate::bridge::{
    BridgeConfig, BridgeError, Candidate, DialConsent, Health, STREAMPLACE_ALPN,
    SubscriptionRequest, UPSTREAM_REVISION, validate_streamer_did,
};
use crate::evidence::EvidenceStore;

/// Postcard enum/key/NodeId/channel framing allowance beyond segment bytes.
/// Streamer DIDs are independently bounded to 2 KiB.
const MAX_WIRE_OVERHEAD_BYTES: usize = 4 * 1024;

pub(crate) mod wire {
    use super::*;

    #[derive(Debug, Serialize, Deserialize)]
    pub struct Subscribe {
        pub key: String,
        pub remote_id: NodeId,
    }

    #[derive(Debug, Serialize, Deserialize)]
    pub struct Unsubscribe {
        pub key: String,
        pub remote_id: NodeId,
    }

    #[derive(Clone, Debug, Serialize, Deserialize)]
    pub struct RecvSegment {
        pub from: NodeId,
        pub key: String,
        pub data: Bytes,
    }

    #[rpc_requests(message = Message)]
    #[derive(Debug, Serialize, Deserialize)]
    pub enum Protocol {
        #[rpc(tx = oneshot::Sender<()>)]
        Subscribe(Subscribe),
        #[rpc(tx = oneshot::Sender<()>)]
        Unsubscribe(Unsubscribe),
        #[rpc(tx = oneshot::Sender<()>)]
        RecvSegment(RecvSegment),
    }
}

#[derive(Debug)]
struct Subscription {
    streamer: String,
    peer_addr: NodeAddr,
    candidates: mpsc::Sender<Candidate>,
    evidence_session_id: String,
}

#[derive(Debug)]
struct Core {
    config: BridgeConfig,
    next_id: u64,
    subscriptions: HashMap<u64, Subscription>,
    evidence: EvidenceStore,
}

impl Core {
    fn deliver(
        &self,
        authenticated_peer: NodeId,
        segment: wire::RecvSegment,
    ) -> Result<(), BridgeError> {
        let subscription_for_peer = self
            .subscriptions
            .values()
            .find(|subscription| subscription.peer_addr.node_id == authenticated_peer);
        if segment.from != authenticated_peer {
            self.record_rejection(subscription_for_peer, "peer_identity_mismatch")?;
            return Err(BridgeError::PeerIdentityMismatch);
        }
        if segment.data.is_empty() || segment.data.len() > self.config.max_segment_bytes {
            self.record_rejection(subscription_for_peer, "segment_size_rejected")?;
            return Err(BridgeError::SegmentTooLarge);
        }
        let subscription = match self.subscriptions.values().find(|subscription| {
            subscription.streamer == segment.key
                && subscription.peer_addr.node_id == authenticated_peer
        }) {
            Some(subscription) => subscription,
            None => {
                if let Some(subscription) = subscription_for_peer {
                    self.evidence
                        .record_rejection(&subscription.evidence_session_id, "wrong_streamer")?;
                }
                return Err(BridgeError::UnknownSubscription);
            }
        };
        let segment_bytes = segment.data.len();
        let segment_from_node_id = segment.from.to_string();
        let segment_content_sha256 = EvidenceStore::content_sha256(&segment.data);
        if subscription
            .candidates
            .try_send(Candidate {
                streamer_did: segment.key,
                source_node_id: authenticated_peer.to_string(),
                muxl_bytes: segment.data.to_vec(),
            })
            .is_err()
        {
            self.evidence
                .record_rejection(&subscription.evidence_session_id, "candidate_queue_full")?;
            return Err(BridgeError::CandidateQueueFull);
        }
        self.evidence.record_segment(
            &subscription.evidence_session_id,
            authenticated_peer.to_string(),
            segment_bytes,
            segment_from_node_id,
            segment_content_sha256,
        )?;
        Ok(())
    }

    fn record_rejection(
        &self,
        subscription: Option<&Subscription>,
        code: &'static str,
    ) -> Result<(), BridgeError> {
        if let Some(subscription) = subscription {
            self.evidence
                .record_rejection(&subscription.evidence_session_id, code)?;
        }
        Ok(())
    }
}

/// Custom receiver which retains the router for the process lifetime.
pub struct ReceiveBridge {
    endpoint: Endpoint,
    _router: Router,
    core: Arc<Mutex<Core>>,
}

impl ReceiveBridge {
    pub async fn new(config: BridgeConfig) -> Result<Self, BridgeError> {
        config.validate()?;
        let max_inbound_connections = config.max_inbound_connections;
        let max_wire_bytes = config
            .max_segment_bytes
            .saturating_add(MAX_WIRE_OVERHEAD_BYTES);
        let inbound_read_timeout = config.subscription_timeout;
        let core = Arc::new(Mutex::new(Core {
            evidence: EvidenceStore::start(config.evidence_path.clone())?,
            config,
            next_id: 1,
            subscriptions: HashMap::new(),
        }));
        let endpoint = Endpoint::builder()
            .bind()
            .await
            .map_err(|_| BridgeError::TransportUnavailable)?;
        let router = Router::builder(endpoint.clone())
            .accept(
                STREAMPLACE_ALPN.as_bytes(),
                SecureProtocol {
                    core: core.clone(),
                    inbound_connections: Arc::new(Semaphore::new(max_inbound_connections)),
                    max_wire_bytes,
                    read_timeout: inbound_read_timeout,
                },
            )
            .spawn();
        Ok(Self {
            endpoint,
            _router: router,
            core,
        })
    }

    pub async fn health(&self) -> Health {
        let core = self.core.lock().await;
        Health {
            status: "ready",
            receive_only: true,
            alpn: STREAMPLACE_ALPN,
            upstream_revision: UPSTREAM_REVISION,
            authenticated_peer_identity: "connection.remote_node_id",
            subscriptions: core.subscriptions.len(),
        }
    }

    /// Record Jelcz's structural MUXL validation for a returned bridge session.
    /// The capability boundary is enforced by the IPC route; this method still
    /// enforces the session, fingerprint, and exact received byte count.
    pub async fn attest_muxl(
        &self,
        session_id: &str,
        ticket_fingerprint: &str,
        content_bytes: usize,
        content_sha256: &str,
    ) -> Result<(), BridgeError> {
        self.core.lock().await.evidence.attest_muxl(
            session_id,
            ticket_fingerprint,
            content_bytes,
            content_sha256,
        )
    }

    pub async fn open_attestation_window(&self, session_id: &str) -> Result<(), BridgeError> {
        let core = self.core.lock().await;
        core.evidence
            .open_attestation_window(session_id, core.config.attestation_window)
    }

    /// Dial the consent-bound ticket and subscribe by the exact streamer DID.
    pub async fn subscribe(
        &self,
        request: SubscriptionRequest,
    ) -> Result<(u64, mpsc::Receiver<Candidate>, String), BridgeError> {
        validate_streamer_did(&request.streamer_did)?;
        if request.node_ticket.len() > crate::bridge::MAX_NODE_TICKET_BYTES {
            return Err(BridgeError::TicketTooLarge);
        }
        let ticket =
            NodeTicket::from_str(&request.node_ticket).map_err(|_| BridgeError::MalformedTicket)?;
        let peer_addr: NodeAddr = ticket.into();
        if !request.dial_consent.authorized {
            return Err(BridgeError::ConsentDenied);
        }
        if request.dial_consent.expected_node_id != peer_addr.node_id.to_string() {
            return Err(BridgeError::ConsentIdentityMismatch);
        }
        let (
            timeout,
            max_subscriptions,
            queue,
            reconnect_attempt_limit,
            reconnect_initial_backoff,
            reconnect_max_backoff,
        ) = {
            let core = self.core.lock().await;
            (
                core.config.subscription_timeout,
                core.config.max_subscriptions,
                core.config.max_queue_segments,
                core.config.reconnect_attempt_limit,
                core.config.reconnect_initial_backoff,
                core.config.reconnect_max_backoff,
            )
        };
        // Reserve before sending Subscribe: a compliant peer can push a MUXL
        // candidate as soon as it acknowledges the call.
        let (id, receiver, evidence_session_id, ticket_fingerprint) = {
            let mut core = self.core.lock().await;
            if core.subscriptions.len() >= max_subscriptions {
                return Err(BridgeError::SubscriptionLimit);
            }
            let (sender, receiver) = mpsc::channel(queue);
            let id = core.next_id;
            core.next_id += 1;
            let evidence_session_id = format!("{}-{id}", self.endpoint.node_id());
            let ticket_fingerprint = EvidenceStore::ticket_fingerprint(&request.node_ticket);
            core.subscriptions.insert(
                id,
                Subscription {
                    streamer: request.streamer_did.clone(),
                    peer_addr: peer_addr.clone(),
                    candidates: sender,
                    evidence_session_id: evidence_session_id.clone(),
                },
            );
            (id, receiver, evidence_session_id, ticket_fingerprint)
        };
        let mut reconnects = 0_u8;
        let mut backoff = reconnect_initial_backoff;
        loop {
            {
                let core = self.core.lock().await;
                core.evidence.begin_dial(
                    evidence_session_id.clone(),
                    request.streamer_did.clone(),
                    ticket_fingerprint.clone(),
                    peer_addr.node_id.to_string(),
                    reconnect_attempt_limit,
                )?;
            }
            let client = irpc::Client::<wire::Protocol>::boxed(IrohRemoteConnection::new(
                self.endpoint.clone(),
                peer_addr.clone(),
                STREAMPLACE_ALPN.as_bytes().to_vec(),
            ));
            let rpc_result = tokio::time::timeout(
                timeout,
                client.rpc(wire::Subscribe {
                    key: request.streamer_did.clone(),
                    remote_id: self.endpoint.node_id(),
                }),
            )
            .await
            .map_err(|_| BridgeError::SubscriptionDeadlineExceeded)
            .and_then(|result| result.map_err(|_| BridgeError::TransportUnavailable));
            match rpc_result {
                Ok(()) => break,
                Err(_error) if reconnects < reconnect_attempt_limit => {
                    reconnects = reconnects.saturating_add(1);
                    {
                        let core = self.core.lock().await;
                        core.evidence
                            .record_reconnect_attempt(&evidence_session_id)?;
                    }
                    tokio::time::sleep(backoff).await;
                    backoff = backoff.saturating_mul(2).min(reconnect_max_backoff);
                }
                Err(error) => {
                    let core = self.core.lock().await;
                    let _ = core
                        .evidence
                        .record_rejection(&evidence_session_id, "subscribe_failed");
                    drop(core);
                    self.core.lock().await.subscriptions.remove(&id);
                    return Err(error);
                }
            }
        }
        {
            let core = self.core.lock().await;
            core.evidence.acknowledge_subscribe(&evidence_session_id)?;
        }
        Ok((id, receiver, evidence_session_id))
    }

    pub async fn unsubscribe(&self, id: u64) {
        let subscription = {
            let mut core = self.core.lock().await;
            let timeout = core.config.subscription_timeout;
            core.subscriptions
                .remove(&id)
                .map(|subscription| (subscription.streamer, subscription.peer_addr, timeout))
        };
        let Some((streamer, peer_addr, timeout)) = subscription else {
            return;
        };
        // Best effort only: remove local state even if the remote has already
        // gone away. This limits further candidate acceptance immediately.
        let client = irpc::Client::<wire::Protocol>::boxed(IrohRemoteConnection::new(
            self.endpoint.clone(),
            peer_addr,
            STREAMPLACE_ALPN.as_bytes().to_vec(),
        ));
        let _ = tokio::time::timeout(
            timeout,
            client.rpc(wire::Unsubscribe {
                key: streamer,
                remote_id: self.endpoint.node_id(),
            }),
        )
        .await;
    }
}

#[derive(Clone, Debug)]
struct SecureProtocol {
    core: Arc<Mutex<Core>>,
    inbound_connections: Arc<Semaphore>,
    max_wire_bytes: usize,
    read_timeout: std::time::Duration,
}

impl SecureProtocol {
    fn acquire_connection(&self) -> Result<OwnedSemaphorePermit, AcceptError> {
        self.inbound_connections
            .clone()
            .try_acquire_owned()
            .map_err(|_| {
                AcceptError::from_err(io::Error::new(
                    io::ErrorKind::ConnectionRefused,
                    "inbound Streamplace connection limit reached",
                ))
            })
    }
}

impl ProtocolHandler for SecureProtocol {
    fn accept(
        &self,
        connection: Connection,
    ) -> impl std::future::Future<Output = Result<(), AcceptError>> + Send {
        let core = self.core.clone();
        let connection_permit = self.acquire_connection();
        let max_wire_bytes = self.max_wire_bytes;
        let read_timeout = self.read_timeout;
        async move {
            let _connection_permit = connection_permit?;
            let authenticated_peer = connection
                .remote_node_id()
                .map_err(|error| AcceptError::from_err(io::Error::other(error)))?;
            loop {
                let Some(message) = tokio::time::timeout(
                    read_timeout,
                    read_bounded_request(&connection, max_wire_bytes),
                )
                .await
                .map_err(|_| {
                    AcceptError::from_err(io::Error::new(
                        io::ErrorKind::TimedOut,
                        "inbound Streamplace request timed out",
                    ))
                })?
                .map_err(AcceptError::from_err)?
                else {
                    return Ok(());
                };
                match message {
                    wire::Message::RecvSegment(WithChannels { tx, inner, .. }) => {
                        let result = core.lock().await.deliver(authenticated_peer, inner);
                        // Do not acknowledge unauthorized or oversized bytes.
                        if let Err(error) = result {
                            return Err(AcceptError::from_err(io::Error::new(
                                io::ErrorKind::PermissionDenied,
                                error.to_string(),
                            )));
                        }
                        tx.send(()).await.map_err(AcceptError::from_err)?;
                    }
                    wire::Message::Subscribe(_) | wire::Message::Unsubscribe(_) => {
                        return Err(AcceptError::from_err(io::Error::new(
                            io::ErrorKind::PermissionDenied,
                            "receive-only bridge rejects inbound subscription control",
                        )));
                    }
                }
            }
        }
    }
}

/// Read Streamplace's length-prefixed postcard request with the configured
/// segment ceiling enforced before allocating the frame buffer. Pinned
/// `irpc_iroh::read_request` hard-codes 16 MiB and offers no limit parameter.
pub(crate) async fn read_bounded_request(
    connection: &Connection,
    max_wire_bytes: usize,
) -> io::Result<Option<wire::Message>> {
    let (send, mut recv) = connection.accept_bi().await.map_err(io::Error::other)?;
    let size = recv
        .read_varint_u64()
        .await?
        .ok_or_else(|| io::Error::new(io::ErrorKind::UnexpectedEof, "missing request size"))?;
    validate_wire_size(size, max_wire_bytes)?;
    let mut bytes = vec![0; size as usize];
    recv.read_exact(&mut bytes)
        .await
        .map_err(|error| io::Error::new(io::ErrorKind::UnexpectedEof, error))?;
    let request: wire::Protocol = postcard::from_bytes(&bytes)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
    Ok(Some(
        <wire::Protocol as RemoteService>::with_remote_channels(request, recv, send),
    ))
}

fn validate_wire_size(size: u64, max_wire_bytes: usize) -> io::Result<()> {
    if size > max_wire_bytes as u64 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "Streamplace request exceeded configured predecode limit",
        ));
    }
    Ok(())
}

/// Shared request decoding used by local IPC; tickets remain out of error text.
pub fn subscription_request(
    streamer: String,
    iroh_ticket: String,
    expected_node_id: String,
    authorized: bool,
) -> SubscriptionRequest {
    SubscriptionRequest {
        streamer_did: streamer,
        node_ticket: iroh_ticket,
        dial_consent: DialConsent {
            expected_node_id,
            authorized,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn core_with_subscription(
        peer: NodeId,
        max_segment_bytes: usize,
        queue: usize,
    ) -> (Core, mpsc::Receiver<Candidate>) {
        let (sender, receiver) = mpsc::channel(queue);
        let mut subscriptions = HashMap::new();
        subscriptions.insert(
            1,
            Subscription {
                streamer: "did:plc:alice".into(),
                peer_addr: NodeAddr::new(peer),
                candidates: sender,
                evidence_session_id: "test-session".into(),
            },
        );
        let evidence = EvidenceStore::start(std::path::PathBuf::from("/tmp").join(format!(
            "jelcz-bridge-transport-test-{}-{}.json",
            std::process::id(),
            peer
        )))
        .unwrap();
        evidence
            .begin_dial(
                "test-session".into(),
                "did:plc:alice".into(),
                "sha256:test-ticket".into(),
                peer.to_string(),
                3,
            )
            .unwrap();
        evidence.acknowledge_subscribe("test-session").unwrap();
        (
            Core {
                config: BridgeConfig {
                    max_segment_bytes,
                    max_queue_segments: queue,
                    ..BridgeConfig::default()
                },
                next_id: 2,
                subscriptions,
                evidence,
            },
            receiver,
        )
    }

    #[test]
    fn wire_messages_have_a_pinned_postcard_round_trip() {
        let key = iroh_base::SecretKey::from_bytes(&[11; 32]).public();
        let message = wire::Protocol::RecvSegment(wire::RecvSegment {
            from: key,
            key: "did:plc:alice".into(),
            data: Bytes::from_static(b"muxl"),
        });
        let encoded = postcard::to_stdvec(&message).unwrap();
        let decoded: wire::Protocol = postcard::from_bytes(&encoded).unwrap();
        assert!(matches!(decoded, wire::Protocol::RecvSegment(_)));
    }

    #[tokio::test]
    async fn authenticated_peer_binding_is_enforced_by_the_live_sink() {
        let peer = iroh_base::SecretKey::from_bytes(&[7; 32]).public();
        let impostor = iroh_base::SecretKey::from_bytes(&[8; 32]).public();
        let (core, mut candidates) = core_with_subscription(peer, 8, 1);
        let segment = wire::RecvSegment {
            from: impostor,
            key: "did:plc:alice".into(),
            data: Bytes::from_static(b"muxl"),
        };
        assert_eq!(
            core.deliver(impostor, segment).unwrap_err(),
            BridgeError::UnknownSubscription
        );
        let spoofed_payload = wire::RecvSegment {
            from: impostor,
            key: "did:plc:alice".into(),
            data: Bytes::from_static(b"muxl"),
        };
        assert_eq!(
            core.deliver(peer, spoofed_payload).unwrap_err(),
            BridgeError::PeerIdentityMismatch
        );
        core.deliver(
            peer,
            wire::RecvSegment {
                from: peer,
                key: "did:plc:alice".into(),
                data: Bytes::from_static(b"muxl"),
            },
        )
        .unwrap();
        assert_eq!(
            candidates.recv().await.unwrap().source_node_id,
            peer.to_string()
        );
    }

    #[test]
    fn live_sink_enforces_segment_and_queue_bounds() {
        let peer = iroh_base::SecretKey::from_bytes(&[9; 32]).public();
        let (core, _candidates) = core_with_subscription(peer, 2, 1);
        let segment = |data: &'static [u8]| wire::RecvSegment {
            from: peer,
            key: "did:plc:alice".into(),
            data: Bytes::from_static(data),
        };
        assert_eq!(
            core.deliver(peer, segment(b"big")).unwrap_err(),
            BridgeError::SegmentTooLarge
        );
        core.deliver(peer, segment(b"1")).unwrap();
        assert_eq!(
            core.deliver(peer, segment(b"2")).unwrap_err(),
            BridgeError::CandidateQueueFull
        );
    }

    #[test]
    fn inbound_connection_permits_are_bounded() {
        let peer = iroh_base::SecretKey::from_bytes(&[10; 32]).public();
        let (core, _candidates) = core_with_subscription(peer, 8, 1);
        let protocol = SecureProtocol {
            core: Arc::new(Mutex::new(core)),
            inbound_connections: Arc::new(Semaphore::new(1)),
            max_wire_bytes: 8 + MAX_WIRE_OVERHEAD_BYTES,
            read_timeout: std::time::Duration::from_secs(1),
        };
        let permit = protocol.acquire_connection().unwrap();
        assert!(protocol.acquire_connection().is_err());
        drop(permit);
        assert!(protocol.acquire_connection().is_ok());
    }

    #[test]
    fn predecode_wire_bound_tracks_configured_segment_limit() {
        let config = BridgeConfig {
            max_segment_bytes: 1_024,
            ..BridgeConfig::default()
        };
        assert_eq!(
            config.max_segment_bytes + MAX_WIRE_OVERHEAD_BYTES,
            5 * 1_024
        );
        assert!(validate_wire_size(5 * 1_024, 5 * 1_024).is_ok());
        assert!(validate_wire_size(5 * 1_024 + 1, 5 * 1_024).is_err());
    }
}
