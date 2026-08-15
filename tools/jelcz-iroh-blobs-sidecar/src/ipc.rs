// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

//! Versioned loopback/UDS HTTP IPC for the Track A lab sidecar (phase-35 S4).

use std::net::SocketAddr;
use std::path::Path;
use std::str::FromStr;
use std::sync::Arc;
use std::time::Duration;

use anyhow::Context;
use axum::{
    extract::{DefaultBodyLimit, State},
    http::{header, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use iroh::{EndpointAddr, EndpointId};
use iroh_blobs::Hash;
use iroh_tickets::endpoint::EndpointTicket;
use serde::{Deserialize, Serialize};
use tokio::sync::Semaphore;

use crate::cid::{self, CidMappingError};
use crate::BlobNode;

const DEFAULT_MAX_FETCH_BYTES: usize = 64 * 1024 * 1024;
const DEFAULT_FETCH_TIMEOUT: Duration = Duration::from_secs(60);
const DEFAULT_MAX_CONCURRENT_FETCHES: usize = 2;
const CAPABILITY_ENV: &str = "JELCZ_IROH_SIDECAR_CAPABILITY";

#[derive(Clone)]
pub struct SidecarState {
    node: Arc<BlobNode>,
    max_fetch_bytes: usize,
    fetch_timeout: Duration,
    fetch_admission: Arc<Semaphore>,
    capability: Arc<str>,
}

impl SidecarState {
    pub async fn new() -> anyhow::Result<Self> {
        let capability = std::env::var(CAPABILITY_ENV)
            .context("JELCZ_IROH_SIDECAR_CAPABILITY is required for /v1 IPC")?;
        if capability.is_empty() {
            anyhow::bail!("JELCZ_IROH_SIDECAR_CAPABILITY must not be empty");
        }
        Self::with_limits(
            capability,
            DEFAULT_MAX_FETCH_BYTES,
            DEFAULT_FETCH_TIMEOUT,
            DEFAULT_MAX_CONCURRENT_FETCHES,
        )
        .await
    }

    async fn with_limits(
        capability: String,
        max_fetch_bytes: usize,
        fetch_timeout: Duration,
        max_concurrent_fetches: usize,
    ) -> anyhow::Result<Self> {
        if capability.is_empty() || max_fetch_bytes == 0 || max_concurrent_fetches == 0 {
            anyhow::bail!("invalid sidecar safety limits");
        }
        Ok(Self {
            node: Arc::new(BlobNode::new().await?),
            max_fetch_bytes,
            fetch_timeout,
            fetch_admission: Arc::new(Semaphore::new(max_concurrent_fetches)),
            capability: Arc::from(capability),
        })
    }
}

#[derive(Serialize)]
struct HealthResponse {
    status: &'static str,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct IdentityResponse {
    endpoint_id: String,
    endpoint_ticket: String,
}

#[derive(Deserialize)]
struct OfferRequest {
    #[serde(default)]
    payload_utf8: Option<String>,
    #[serde(default)]
    payload_base64: Option<String>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct OfferResponse {
    hash: String,
    endpoint_id: String,
    endpoint_ticket: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct FetchProvider {
    endpoint_id: String,
    #[serde(default)]
    endpoint_ticket: Option<String>,
}

#[derive(Deserialize)]
struct FetchRequest {
    cid: String,
    provider: FetchProvider,
}

#[derive(Serialize)]
struct ErrorResponse {
    error: String,
}

fn api_error(status: StatusCode, message: impl Into<String>) -> Response {
    (
        status,
        Json(ErrorResponse {
            error: message.into(),
        }),
    )
        .into_response()
}

fn constant_time_equal(expected: &[u8], supplied: &[u8]) -> bool {
    // The generated Compose capability is fixed-width hex.  Keep all content
    // comparisons over that width even when a hostile client sends a shorter
    // or longer value; only the final branch observes the mismatch.
    let mut difference = expected.len() ^ supplied.len();
    for (index, expected_byte) in expected.iter().enumerate() {
        difference |= usize::from(*expected_byte ^ supplied.get(index).copied().unwrap_or(0));
    }
    difference == 0
}

fn require_capability(state: &SidecarState, headers: &HeaderMap) -> Result<(), Response> {
    let Some(authorization) = headers.get(header::AUTHORIZATION) else {
        return Err((
            StatusCode::UNAUTHORIZED,
            [(
                header::WWW_AUTHENTICATE,
                "Bearer realm=\"jelcz-iroh-sidecar\"",
            )],
            Json(ErrorResponse {
                error: "sidecar capability required".to_owned(),
            }),
        )
            .into_response());
    };
    let Ok(authorization) = authorization.to_str() else {
        return Err(api_error(
            StatusCode::FORBIDDEN,
            "invalid sidecar capability",
        ));
    };
    let Some(supplied) = authorization.strip_prefix("Bearer ") else {
        return Err(api_error(
            StatusCode::FORBIDDEN,
            "invalid sidecar capability",
        ));
    };
    if !constant_time_equal(state.capability.as_bytes(), supplied.as_bytes()) {
        return Err(api_error(
            StatusCode::FORBIDDEN,
            "invalid sidecar capability",
        ));
    }
    Ok(())
}

async fn health() -> Json<HealthResponse> {
    Json(HealthResponse { status: "ok" })
}

async fn identity(
    State(state): State<SidecarState>,
    headers: HeaderMap,
) -> Result<Json<IdentityResponse>, Response> {
    require_capability(&state, &headers)?;
    let ticket = EndpointTicket::from(state.node.endpoint_addr());
    Ok(Json(IdentityResponse {
        endpoint_id: state.node.endpoint_id().to_string(),
        endpoint_ticket: ticket.to_string(),
    }))
}

async fn offer(
    State(state): State<SidecarState>,
    headers: HeaderMap,
    Json(body): Json<OfferRequest>,
) -> Result<Json<OfferResponse>, Response> {
    require_capability(&state, &headers)?;
    let payload = if let Some(text) = body.payload_utf8 {
        text.into_bytes()
    } else if let Some(b64) = body.payload_base64 {
        base64::Engine::decode(&base64::engine::general_purpose::STANDARD, b64)
            .map_err(|e| api_error(StatusCode::BAD_REQUEST, format!("payload_base64: {e}")))?
    } else {
        return Err(api_error(
            StatusCode::BAD_REQUEST,
            "payload_utf8 or payload_base64 required",
        ));
    };

    let hash = state
        .node
        .offer_slice(&payload)
        .await
        .map_err(|e| api_error(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    let ticket = EndpointTicket::from(state.node.endpoint_addr());
    Ok(Json(OfferResponse {
        hash: hash.to_string(),
        endpoint_id: state.node.endpoint_id().to_string(),
        endpoint_ticket: ticket.to_string(),
    }))
}

async fn fetch(
    State(state): State<SidecarState>,
    headers: HeaderMap,
    Json(body): Json<FetchRequest>,
) -> Result<Response, Response> {
    require_capability(&state, &headers)?;
    let _permit = state
        .fetch_admission
        .clone()
        .try_acquire_owned()
        .map_err(|_| api_error(StatusCode::TOO_MANY_REQUESTS, "fetch capacity exhausted"))?;
    let hash = garazyk_ca_vod_cid_to_hash(&body.cid)
        .map_err(|e| api_error(StatusCode::BAD_REQUEST, e.to_string()))?;
    let provider = EndpointId::from_str(&body.provider.endpoint_id).map_err(|e| {
        api_error(
            StatusCode::BAD_REQUEST,
            format!("invalid provider.endpointId: {e}"),
        )
    })?;

    if let Some(ticket) = body.provider.endpoint_ticket.as_deref() {
        let ticket = EndpointTicket::from_str(ticket).map_err(|e| {
            api_error(
                StatusCode::BAD_REQUEST,
                format!("invalid provider.endpointTicket: {e}"),
            )
        })?;
        let addr: EndpointAddr = ticket.into();
        state.node.register_peer(addr);
    }

    let bytes = fetch_with_timeout(
        state.fetch_timeout,
        state
            .node
            .fetch_from_bounded(hash, provider, state.max_fetch_bytes as u64),
    )
    .await
    .map_err(|_| api_error(StatusCode::GATEWAY_TIMEOUT, "fetch timed out"))?
    .map_err(|e| {
        let msg = e.to_string();
        if msg.contains("exceeds limit") {
            api_error(StatusCode::PAYLOAD_TOO_LARGE, msg)
        } else {
            api_error(StatusCode::BAD_GATEWAY, msg)
        }
    })?;

    Ok((
        StatusCode::OK,
        [(header::CONTENT_TYPE, "application/octet-stream")],
        bytes,
    )
        .into_response())
}

async fn fetch_with_timeout<T>(
    timeout: Duration,
    operation: impl std::future::Future<Output = anyhow::Result<T>>,
) -> Result<anyhow::Result<T>, tokio::time::error::Elapsed> {
    tokio::time::timeout(timeout, operation).await
}

fn garazyk_ca_vod_cid_to_hash(cid: &str) -> Result<Hash, CidMappingError> {
    cid::garazyk_ca_vod_cid_to_hash(cid)
}

pub fn router(state: SidecarState) -> Router {
    // Lab offers currently JSON-base64 the payload; a 32 MiB blob becomes ~43 MiB.
    // Keep headroom under max_fetch_bytes for fetch responses.
    const MAX_OFFER_BODY: usize = 96 * 1024 * 1024;
    Router::new()
        .route("/v1/health", get(health))
        .route("/v1/identity", get(identity))
        .route("/v1/offer", post(offer))
        .route("/v1/fetch", post(fetch))
        .layer(DefaultBodyLimit::max(MAX_OFFER_BODY))
        .with_state(state)
}

pub async fn serve_tcp(addr: SocketAddr) -> anyhow::Result<()> {
    let state = SidecarState::new().await?;
    let app = router(state);
    let listener = tokio::net::TcpListener::bind(addr).await?;
    tracing::info!("jelcz-iroh-blobs-sidecar listening on http://{addr}");
    axum::serve(listener, app).await?;
    Ok(())
}

pub async fn serve_unix(path: &Path) -> anyhow::Result<()> {
    if path.exists() {
        std::fs::remove_file(path)?;
    }
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)?;
        }
    }
    let state = SidecarState::new().await?;
    let app = router(state);
    let listener = tokio::net::UnixListener::bind(path)?;
    tracing::info!(
        "jelcz-iroh-blobs-sidecar listening on unix://{}",
        path.display()
    );
    axum::serve(listener, app).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::{to_bytes, Body};
    use axum::http::Request;
    use std::future;
    use tower::ServiceExt;

    const TEST_CAPABILITY: &str =
        "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    async fn test_state(
        max_fetch_bytes: usize,
        max_concurrent_fetches: usize,
    ) -> anyhow::Result<SidecarState> {
        SidecarState::with_limits(
            TEST_CAPABILITY.to_owned(),
            max_fetch_bytes,
            Duration::from_millis(20),
            max_concurrent_fetches,
        )
        .await
    }

    fn request(
        method: &str,
        uri: &str,
        body: Body,
        capability: Option<&str>,
    ) -> anyhow::Result<Request<Body>> {
        let mut builder = Request::builder().method(method).uri(uri);
        if let Some(capability) = capability {
            builder = builder.header(header::AUTHORIZATION, format!("Bearer {capability}"));
        }
        Ok(builder
            .header(header::CONTENT_TYPE, "application/json")
            .body(body)?)
    }

    #[tokio::test]
    async fn ipc_offer_and_fetch_roundtrip() -> anyhow::Result<()> {
        let state = test_state(DEFAULT_MAX_FETCH_BYTES, DEFAULT_MAX_CONCURRENT_FETCHES).await?;
        let app = router(state);

        let offer_resp = app
            .clone()
            .oneshot(request(
                "POST",
                "/v1/offer",
                Body::from(r#"{"payload_utf8":"hello-ca-store"}"#),
                Some(TEST_CAPABILITY),
            )?)
            .await?;
        assert_eq!(offer_resp.status(), StatusCode::OK);
        let offer_bytes = to_bytes(offer_resp.into_body(), usize::MAX).await?;
        let offer: OfferResponse = serde_json::from_slice(&offer_bytes)?;

        let fetch_body = serde_json::json!({
            "cid": "bafkr4iadewxtddpf7wzglzmsoxbm4gqkmq6n3hieephctfxj5ht2n4b43e",
            "provider": {
                "endpointId": offer.endpoint_id,
                "endpointTicket": offer.endpoint_ticket,
            }
        });
        let fetch_resp = app
            .oneshot(request(
                "POST",
                "/v1/fetch",
                Body::from(fetch_body.to_string()),
                Some(TEST_CAPABILITY),
            )?)
            .await?;
        assert_eq!(fetch_resp.status(), StatusCode::OK);
        let fetched = to_bytes(fetch_resp.into_body(), usize::MAX).await?;
        assert_eq!(&fetched[..], b"hello-ca-store");
        Ok(())
    }

    #[tokio::test]
    async fn health_is_public_but_identity_requires_capability() -> anyhow::Result<()> {
        let app = router(test_state(1024, 1).await?);
        let health = app
            .clone()
            .oneshot(request("GET", "/v1/health", Body::empty(), None)?)
            .await?;
        assert_eq!(health.status(), StatusCode::OK);

        let missing = app
            .clone()
            .oneshot(request("GET", "/v1/identity", Body::empty(), None)?)
            .await?;
        assert_eq!(missing.status(), StatusCode::UNAUTHORIZED);
        assert!(missing.headers().contains_key(header::WWW_AUTHENTICATE));

        let wrong = app
            .clone()
            .oneshot(request(
                "GET",
                "/v1/identity",
                Body::empty(),
                Some("wrong"),
            )?)
            .await?;
        assert_eq!(wrong.status(), StatusCode::FORBIDDEN);

        let authorized = app
            .oneshot(request(
                "GET",
                "/v1/identity",
                Body::empty(),
                Some(TEST_CAPABILITY),
            )?)
            .await?;
        assert_eq!(authorized.status(), StatusCode::OK);
        Ok(())
    }

    #[tokio::test]
    async fn rejected_offer_has_no_storage_side_effect() -> anyhow::Result<()> {
        let app = router(test_state(1024, 1).await?);
        let rejected = app
            .clone()
            .oneshot(request(
                "POST",
                "/v1/offer",
                Body::from(r#"{"payload_utf8":"hello-ca-store"}"#),
                Some("wrong"),
            )?)
            .await?;
        assert_eq!(rejected.status(), StatusCode::FORBIDDEN);

        let identity = app
            .clone()
            .oneshot(request(
                "GET",
                "/v1/identity",
                Body::empty(),
                Some(TEST_CAPABILITY),
            )?)
            .await?;
        let identity: IdentityResponse =
            serde_json::from_slice(&to_bytes(identity.into_body(), usize::MAX).await?)?;
        let fetch = serde_json::json!({
            "cid": "bafkr4iadewxtddpf7wzglzmsoxbm4gqkmq6n3hieephctfxj5ht2n4b43e",
            "provider": {
                "endpointId": identity.endpoint_id,
                "endpointTicket": identity.endpoint_ticket,
            }
        });
        let response = app
            .oneshot(request(
                "POST",
                "/v1/fetch",
                Body::from(fetch.to_string()),
                Some(TEST_CAPABILITY),
            )?)
            .await?;
        assert_ne!(response.status(), StatusCode::OK);
        Ok(())
    }

    #[tokio::test]
    async fn fetch_rejects_oversized_completed_blob() -> anyhow::Result<()> {
        let app = router(test_state(4, 1).await?);
        let offer = app
            .clone()
            .oneshot(request(
                "POST",
                "/v1/offer",
                Body::from(r#"{"payload_utf8":"hello-ca-store"}"#),
                Some(TEST_CAPABILITY),
            )?)
            .await?;
        let offer: OfferResponse =
            serde_json::from_slice(&to_bytes(offer.into_body(), usize::MAX).await?)?;
        let fetch = serde_json::json!({
            "cid": "bafkr4iadewxtddpf7wzglzmsoxbm4gqkmq6n3hieephctfxj5ht2n4b43e",
            "provider": {
                "endpointId": offer.endpoint_id,
                "endpointTicket": offer.endpoint_ticket,
            }
        });
        let response = app
            .oneshot(request(
                "POST",
                "/v1/fetch",
                Body::from(fetch.to_string()),
                Some(TEST_CAPABILITY),
            )?)
            .await?;
        assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);
        Ok(())
    }

    #[tokio::test]
    async fn stalled_fetch_times_out_and_admission_recovers_after_n_plus_one() -> anyhow::Result<()>
    {
        assert!(fetch_with_timeout(
            Duration::from_millis(1),
            future::pending::<anyhow::Result<()>>()
        )
        .await
        .is_err());

        let state = test_state(1024, 2).await?;
        let first = state.fetch_admission.clone().try_acquire_owned()?;
        let second = state.fetch_admission.clone().try_acquire_owned()?;
        assert!(state.fetch_admission.clone().try_acquire_owned().is_err());
        drop(first);
        let recovered = state.fetch_admission.clone().try_acquire_owned()?;
        drop(recovered);
        drop(second);
        Ok(())
    }
}
