// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

//! Two-process-style integration: separate provider and requester endpoints.

use std::path::Path;

use jelcz_iroh_blobs_sidecar::{link_peers, BlobNode};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct FixtureFile {
    fixtures: Vec<Fixture>,
}

#[derive(Debug, Deserialize)]
struct Fixture {
    label: String,
    payload_utf8: String,
}

fn load_fixtures() -> FixtureFile {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/hash_mapping.json");
    let text = std::fs::read_to_string(path).expect("read hash_mapping.json");
    serde_json::from_str(&text).expect("parse hash_mapping.json")
}

#[tokio::test]
async fn two_endpoints_offer_then_fetch() -> anyhow::Result<()> {
    let provider = BlobNode::new().await?;
    let requester = BlobNode::new().await?;
    link_peers(&provider, &requester);

    let payload = b"phase-35-s3-local-transfer";
    let hash = provider.offer_slice(payload).await?;
    let provider_id = provider.endpoint_id();

    let fetched = requester.fetch_from(hash, provider_id).await?;
    assert_eq!(&fetched[..], payload);

    provider.shutdown().await?;
    requester.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn fixture_payloads_roundtrip() -> anyhow::Result<()> {
    let fixtures = load_fixtures();
    for fixture in fixtures.fixtures {
        let provider = BlobNode::new().await?;
        let requester = BlobNode::new().await?;
        link_peers(&provider, &requester);

        let payload = fixture.payload_utf8.into_bytes();
        let hash = provider.offer_slice(&payload).await?;
        let fetched = requester.fetch_from(hash, provider.endpoint_id()).await?;
        assert_eq!(
            fetched.as_ref(),
            payload.as_slice(),
            "fixture {}",
            fixture.label
        );

        provider.shutdown().await?;
        requester.shutdown().await?;
    }
    Ok(())
}
