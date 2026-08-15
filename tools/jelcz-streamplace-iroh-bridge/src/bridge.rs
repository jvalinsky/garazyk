// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

use std::{path::PathBuf, time::Duration};

use serde::Serialize;
use thiserror::Error;

/// Streamplace's fixed, versioned live-segment ALPN.
pub const STREAMPLACE_ALPN: &str = "/iroh/streamplace/1";
pub const UPSTREAM_REVISION: &str = "5ba597dbedda8f2fdb84b815ee633301212f5f51";
pub const MAX_NODE_TICKET_BYTES: usize = 2_048;

/// Bounds applied before caller-controlled data can reach the network or queue.
#[derive(Clone, Debug)]
pub struct BridgeConfig {
    pub max_segment_bytes: usize,
    pub max_queue_segments: usize,
    pub max_subscriptions: usize,
    pub dial_timeout: Duration,
    pub subscription_timeout: Duration,
    pub reconnect_initial_backoff: Duration,
    pub reconnect_max_backoff: Duration,
    pub reconnect_attempt_limit: u8,
    pub attestation_window: Duration,
    pub max_inbound_connections: usize,
    pub evidence_path: PathBuf,
}

impl Default for BridgeConfig {
    fn default() -> Self {
        Self {
            max_segment_bytes: 8 * 1024 * 1024,
            max_queue_segments: 32,
            max_subscriptions: 64,
            dial_timeout: Duration::from_secs(10),
            subscription_timeout: Duration::from_secs(10),
            reconnect_initial_backoff: Duration::from_millis(500),
            reconnect_max_backoff: Duration::from_secs(30),
            reconnect_attempt_limit: 5,
            attestation_window: Duration::from_secs(30),
            max_inbound_connections: 16,
            evidence_path: PathBuf::from("/tmp/jelcz-streamplace-iroh-bridge-evidence.json"),
        }
    }
}

impl BridgeConfig {
    pub fn validate(&self) -> Result<(), BridgeError> {
        if self.max_segment_bytes == 0 || self.max_segment_bytes > 64 * 1024 * 1024 {
            return Err(BridgeError::InvalidLimit("max_segment_bytes"));
        }
        if self.max_queue_segments == 0 || self.max_queue_segments > 1_024 {
            return Err(BridgeError::InvalidLimit("max_queue_segments"));
        }
        if self.max_subscriptions == 0 || self.max_subscriptions > 256 {
            return Err(BridgeError::InvalidLimit("max_subscriptions"));
        }
        if self.max_inbound_connections == 0 || self.max_inbound_connections > 128 {
            return Err(BridgeError::InvalidLimit("max_inbound_connections"));
        }
        if self.dial_timeout.is_zero()
            || self.subscription_timeout.is_zero()
            || self.reconnect_initial_backoff.is_zero()
            || self.reconnect_max_backoff < self.reconnect_initial_backoff
            || self.reconnect_attempt_limit == 0
            || self.attestation_window.is_zero()
            || self.attestation_window > Duration::from_secs(120)
        {
            return Err(BridgeError::InvalidDeadlineOrBackoff);
        }
        Ok(())
    }
}

/// Caller-provided authority to dial exactly the NodeTicket peer.
#[derive(Clone, Debug)]
pub struct DialConsent {
    pub expected_node_id: String,
    pub authorized: bool,
}

/// Parsed request for the only live subscription operation.
#[derive(Clone, Debug)]
pub struct SubscriptionRequest {
    pub streamer_did: String,
    pub node_ticket: String,
    pub dial_consent: DialConsent,
}

/// A MUXL candidate that a future authenticated transport may deliver locally.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Candidate {
    pub streamer_did: String,
    pub source_node_id: String,
    pub muxl_bytes: Vec<u8>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Health {
    pub status: &'static str,
    pub receive_only: bool,
    pub alpn: &'static str,
    pub upstream_revision: &'static str,
    pub authenticated_peer_identity: &'static str,
    pub subscriptions: usize,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum BridgeError {
    #[error("invalid bridge limit: {0}")]
    InvalidLimit(&'static str),
    #[error("invalid deadline or reconnect backoff")]
    InvalidDeadlineOrBackoff,
    #[error("streamer DID is invalid")]
    InvalidStreamerDid,
    #[error("NodeTicket exceeds {MAX_NODE_TICKET_BYTES} bytes")]
    TicketTooLarge,
    #[error("malformed NodeTicket")]
    MalformedTicket,
    #[error("dial consent was not granted")]
    ConsentDenied,
    #[error("local IPC capability is missing or invalid")]
    UnauthorizedIpc,
    #[error("dial consent does not bind to the NodeTicket identity")]
    ConsentIdentityMismatch,
    #[error("subscription limit reached")]
    SubscriptionLimit,
    #[error("subscription does not exist")]
    UnknownSubscription,
    #[error("segment exceeds configured maximum")]
    SegmentTooLarge,
    #[error("segment source is not the authenticated subscription peer")]
    PeerIdentityMismatch,
    #[error("segment was sent for a different streamer DID")]
    StreamerMismatch,
    #[error("candidate queue is full")]
    CandidateQueueFull,
    #[error("live iroh transport is unavailable")]
    TransportUnavailable,
    #[error("subscription request exceeded its deadline")]
    SubscriptionDeadlineExceeded,
    #[error("bridge evidence file must be an existing directory beneath /tmp")]
    InvalidEvidencePath,
    #[error("bridge evidence could not be persisted")]
    EvidencePersistence,
    #[error("bridge evidence is unavailable or malformed")]
    EvidenceUnavailable,
    #[error("Jelcz attestation does not bind to a received bridge session")]
    EvidenceAttestationMismatch,
}

pub(crate) fn validate_streamer_did(value: &str) -> Result<(), BridgeError> {
    if value.len() > 2_048 || !value.is_ascii() {
        return Err(BridgeError::InvalidStreamerDid);
    }
    let Some((method, identifier)) = value
        .strip_prefix("did:")
        .and_then(|rest| rest.split_once(':'))
    else {
        return Err(BridgeError::InvalidStreamerDid);
    };
    if method.is_empty()
        || identifier.is_empty()
        || !method
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit())
        || identifier
            .bytes()
            .any(|byte| byte.is_ascii_whitespace() || byte.is_ascii_control())
    {
        return Err(BridgeError::InvalidStreamerDid);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invalid_limits_are_rejected() {
        let config = BridgeConfig {
            max_segment_bytes: 0,
            ..BridgeConfig::default()
        };
        assert_eq!(
            config.validate().unwrap_err(),
            BridgeError::InvalidLimit("max_segment_bytes")
        );
    }

    #[test]
    fn streamer_did_validation_is_bounded() {
        assert!(validate_streamer_did("did:plc:alice").is_ok());
        assert_eq!(
            validate_streamer_did("not-a-did").unwrap_err(),
            BridgeError::InvalidStreamerDid
        );
    }
}
