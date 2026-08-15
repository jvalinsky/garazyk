// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

//! Versioned local-only HTTP IPC for the receive-only bridge.

use std::{net::SocketAddr, path::Path, str::FromStr, sync::Arc};

use axum::{
    Json, Router,
    extract::State,
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use iroh_base::ticket::NodeTicket;
use serde::{Deserialize, Serialize};

use crate::{
    bridge::{BridgeConfig, BridgeError},
    transport::{ReceiveBridge, subscription_request},
};

#[derive(Clone)]
pub struct IpcState {
    bridge: Arc<ReceiveBridge>,
    capability_token: Arc<str>,
}

impl IpcState {
    pub async fn new(config: BridgeConfig, capability_token: String) -> Result<Self, BridgeError> {
        if capability_token.is_empty() {
            return Err(BridgeError::UnauthorizedIpc);
        }
        Ok(Self {
            bridge: Arc::new(ReceiveBridge::new(config).await?),
            capability_token: capability_token.into(),
        })
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SubscribeBody {
    #[serde(rename = "streamer", alias = "streamerDid")]
    streamer_did: String,
    #[serde(rename = "irohTicket", alias = "nodeTicket")]
    node_ticket: String,
    #[serde(rename = "consentAuthorized")]
    consent_authorized: bool,
}

#[derive(Serialize)]
struct ErrorBody {
    error: &'static str,
}

async fn health(State(state): State<IpcState>) -> Json<crate::bridge::Health> {
    Json(state.bridge.health().await)
}

async fn subscribe(
    State(state): State<IpcState>,
    headers: HeaderMap,
    Json(body): Json<SubscribeBody>,
) -> Result<Response, Response> {
    if !has_capability(&headers, &state.capability_token) {
        return Err(ipc_error(BridgeError::UnauthorizedIpc));
    }
    let request = subscription_from_body(body).map_err(ipc_error)?;
    match state.bridge.subscribe(request).await {
        Ok((subscription_id, mut candidates, evidence_session_id)) => {
            let mut lease = SubscriptionLease::new(state.bridge.clone(), subscription_id);
            let received =
                tokio::time::timeout(std::time::Duration::from_secs(10), candidates.recv()).await;
            lease.close().await;
            let candidate = received
                .map_err(|_| ipc_error(BridgeError::SubscriptionDeadlineExceeded))?
                .ok_or_else(|| ipc_error(BridgeError::TransportUnavailable))?;
            state
                .bridge
                .open_attestation_window(&evidence_session_id)
                .await
                .map_err(ipc_error)?;
            Ok((
                StatusCode::OK,
                [
                    (
                        axum::http::header::CONTENT_TYPE.as_str(),
                        "application/octet-stream",
                    ),
                    ("x-jelcz-bridge-session", evidence_session_id.as_str()),
                ],
                candidate.muxl_bytes,
            )
                .into_response())
        }
        Err(error) => Err(ipc_error(error)),
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct MuxlAttestationBody {
    session_id: String,
    ticket_fingerprint: String,
    content_bytes: usize,
    content_sha256: String,
    muxl_structural_validation: bool,
}

/// Trusted Jelcz attests only that it structurally validated the exact bytes
/// just received from this bridge.  Origin, firehose, and consent claims are
/// deliberately not accepted on this route because they are not bridge facts.
async fn attest_muxl(
    State(state): State<IpcState>,
    headers: HeaderMap,
    Json(body): Json<MuxlAttestationBody>,
) -> Result<Response, Response> {
    if !has_capability(&headers, &state.capability_token) {
        return Err(ipc_error(BridgeError::UnauthorizedIpc));
    }
    if !body.muxl_structural_validation
        || !valid_fingerprint(&body.ticket_fingerprint)
        || !valid_fingerprint(&body.content_sha256)
    {
        return Err(ipc_error(BridgeError::EvidenceAttestationMismatch));
    }
    state
        .bridge
        .attest_muxl(
            &body.session_id,
            &body.ticket_fingerprint,
            body.content_bytes,
            &body.content_sha256,
        )
        .await
        .map_err(ipc_error)?;
    Ok(StatusCode::NO_CONTENT.into_response())
}

struct SubscriptionLease {
    bridge: Arc<ReceiveBridge>,
    id: Option<u64>,
}

impl SubscriptionLease {
    fn new(bridge: Arc<ReceiveBridge>, id: u64) -> Self {
        Self {
            bridge,
            id: Some(id),
        }
    }

    async fn close(&mut self) {
        if let Some(id) = self.id.take() {
            self.bridge.unsubscribe(id).await;
        }
    }
}

impl Drop for SubscriptionLease {
    fn drop(&mut self) {
        let Some(id) = self.id.take() else {
            return;
        };
        let bridge = self.bridge.clone();
        tokio::spawn(async move {
            bridge.unsubscribe(id).await;
        });
    }
}

fn has_capability(headers: &HeaderMap, expected: &str) -> bool {
    let Some(value) = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
    else {
        return false;
    };
    let actual = value.as_bytes();
    let expected = expected.as_bytes();
    if actual.len() != expected.len() {
        return false;
    }
    actual
        .iter()
        .zip(expected)
        .fold(0_u8, |difference, (left, right)| {
            difference | (left ^ right)
        })
        == 0
}

fn subscription_from_body(body: SubscribeBody) -> Result<crate::SubscriptionRequest, BridgeError> {
    if body.node_ticket.len() > crate::bridge::MAX_NODE_TICKET_BYTES {
        return Err(BridgeError::TicketTooLarge);
    }
    let expected_node_id = NodeTicket::from_str(&body.node_ticket)
        .map_err(|_| BridgeError::MalformedTicket)?
        .node_addr()
        .node_id
        .to_string();
    Ok(subscription_request(
        body.streamer_did,
        body.node_ticket,
        expected_node_id,
        body.consent_authorized,
    ))
}

fn ipc_error(error: BridgeError) -> Response {
    let status = match error {
        BridgeError::TransportUnavailable | BridgeError::SubscriptionDeadlineExceeded => {
            StatusCode::BAD_GATEWAY
        }
        BridgeError::TicketTooLarge | BridgeError::SegmentTooLarge => StatusCode::PAYLOAD_TOO_LARGE,
        BridgeError::SubscriptionLimit | BridgeError::CandidateQueueFull => {
            StatusCode::TOO_MANY_REQUESTS
        }
        BridgeError::InvalidStreamerDid
        | BridgeError::MalformedTicket
        | BridgeError::ConsentDenied
        | BridgeError::ConsentIdentityMismatch => StatusCode::BAD_REQUEST,
        BridgeError::UnauthorizedIpc => StatusCode::UNAUTHORIZED,
        _ => StatusCode::CONFLICT,
    };
    // No ticket, peer ID, or arbitrary parser text is reflected into logs or IPC.
    (
        status,
        Json(ErrorBody {
            error: error_code(&error),
        }),
    )
        .into_response()
}

fn error_code(error: &BridgeError) -> &'static str {
    match error {
        BridgeError::InvalidLimit(_) => "invalid_limit",
        BridgeError::InvalidDeadlineOrBackoff => "invalid_deadline_or_backoff",
        BridgeError::InvalidStreamerDid => "invalid_streamer_did",
        BridgeError::TicketTooLarge => "ticket_too_large",
        BridgeError::MalformedTicket => "malformed_ticket",
        BridgeError::ConsentDenied => "consent_denied",
        BridgeError::UnauthorizedIpc => "unauthorized_ipc",
        BridgeError::ConsentIdentityMismatch => "consent_identity_mismatch",
        BridgeError::SubscriptionLimit => "subscription_limit",
        BridgeError::UnknownSubscription => "unknown_subscription",
        BridgeError::SegmentTooLarge => "segment_too_large",
        BridgeError::PeerIdentityMismatch => "peer_identity_mismatch",
        BridgeError::StreamerMismatch => "streamer_mismatch",
        BridgeError::CandidateQueueFull => "candidate_queue_full",
        BridgeError::TransportUnavailable => "transport_unavailable",
        BridgeError::SubscriptionDeadlineExceeded => "subscription_deadline_exceeded",
        BridgeError::InvalidEvidencePath => "invalid_evidence_path",
        BridgeError::EvidencePersistence => "evidence_persistence_failed",
        BridgeError::EvidenceUnavailable => "evidence_unavailable",
        BridgeError::EvidenceAttestationMismatch => "evidence_attestation_mismatch",
    }
}

fn valid_fingerprint(value: &str) -> bool {
    value.len() == "sha256:".len() + 64
        && value.starts_with("sha256:")
        && value["sha256:".len()..]
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

pub fn router(state: IpcState) -> Router {
    Router::new()
        .route("/v1/health", get(health))
        .route("/v1/subscriptions", post(subscribe))
        .route("/v1/subscribe", post(subscribe))
        .route("/v1/evidence/muxl-attestations", post(attest_muxl))
        .with_state(state)
}

pub async fn serve_tcp(
    addr: SocketAddr,
    config: BridgeConfig,
    capability_token: String,
    allow_private_network: bool,
) -> anyhow::Result<()> {
    if !addr.ip().is_loopback() && !allow_private_network {
        anyhow::bail!("refusing non-loopback IPC address {addr}");
    }
    let app = router(IpcState::new(config, capability_token).await?);
    let listener = tokio::net::TcpListener::bind(addr).await?;
    tracing::info!(%addr, "Streamplace bridge listening on loopback IPC");
    axum::serve(listener, app).await?;
    Ok(())
}

pub async fn serve_unix(
    path: &Path,
    config: BridgeConfig,
    capability_token: String,
) -> anyhow::Result<()> {
    if path.exists() {
        anyhow::bail!("refusing to replace existing IPC socket {}", path.display());
    }
    let parent = path
        .parent()
        .ok_or_else(|| anyhow::anyhow!("IPC socket needs a parent directory"))?;
    if !parent.exists() {
        anyhow::bail!("IPC socket parent does not exist: {}", parent.display());
    }
    let app = router(IpcState::new(config, capability_token).await?);
    let listener = tokio::net::UnixListener::bind(path)?;
    tracing::info!(path = %path.display(), "Streamplace bridge listening on UDS IPC");
    axum::serve(listener, app).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn malformed_ticket_is_rejected_without_reflection() {
        let body: SubscribeBody = serde_json::from_str(
            r#"{"streamer":"did:plc:alice","irohTicket":"secret-not-a-ticket","consentAuthorized":true}"#,
        )
        .unwrap();
        let error = subscription_from_body(body).unwrap_err();
        assert_eq!(error, BridgeError::MalformedTicket);
        assert_eq!(error_code(&error), "malformed_ticket");
        assert!(!error_code(&error).contains("secret"));
    }

    #[test]
    fn capability_is_required_and_compared_exactly() {
        let mut headers = HeaderMap::new();
        assert!(!has_capability(&headers, "expected"));
        headers.insert(
            axum::http::header::AUTHORIZATION,
            "Bearer expected".parse().unwrap(),
        );
        assert!(has_capability(&headers, "expected"));
        assert!(!has_capability(&headers, "different"));
    }
}
