// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

//! Minimal iroh-blobs node helpers for Garazyk Track A (CA/VOD) lab work.
//!
//! Phase-35 S3: local offer/fetch. S4: versioned loopback/UDS HTTP IPC.

pub mod cid;
pub mod ipc;

use anyhow::Context;
use bytes::Bytes;
use iroh::{
    address_lookup::MemoryLookup, endpoint::presets, protocol::Router, Endpoint, EndpointAddr,
    EndpointId, RelayMode,
};
use iroh_blobs::{store::mem::MemStore, BlobsProtocol, Hash};

/// In-memory iroh-blobs provider/requester pair member.
pub struct BlobNode {
    router: Router,
    store: MemStore,
    lookup: MemoryLookup,
}

impl BlobNode {
    /// Bind a local endpoint, attach an in-memory blob store, and serve blobs.
    pub async fn new() -> anyhow::Result<Self> {
        let store = MemStore::new();
        let lookup = MemoryLookup::new();
        let endpoint = Endpoint::builder(presets::Minimal)
            .relay_mode(RelayMode::Disabled)
            .address_lookup(lookup.clone())
            .bind()
            .await
            .context("bind iroh endpoint")?;
        let blobs = BlobsProtocol::new(&store, None);
        let router = Router::builder(endpoint)
            .accept(iroh_blobs::ALPN, blobs)
            .spawn();
        Ok(Self {
            router,
            store,
            lookup,
        })
    }

    pub fn endpoint_id(&self) -> EndpointId {
        self.router.endpoint().id()
    }

    pub fn endpoint_addr(&self) -> EndpointAddr {
        self.router.endpoint().addr()
    }

    /// Register a peer so fetches can resolve `EndpointId` → dial info.
    pub fn register_peer(&self, addr: EndpointAddr) {
        self.lookup.add_endpoint_info(addr);
    }

    /// Store bytes and return the iroh-blobs content hash (Bao root).
    pub async fn offer_slice(&self, data: &[u8]) -> anyhow::Result<Hash> {
        let tag = self
            .store
            .add_slice(data)
            .await
            .context("store offered slice")?;
        Ok(tag.hash)
    }

    /// Download a blob from `provider` and return the full payload.
    pub async fn fetch_from(&self, hash: Hash, provider: EndpointId) -> anyhow::Result<Bytes> {
        if let Ok(bytes) = self.store.get_bytes(hash).await {
            return Ok(bytes);
        }
        let downloader = self.store.downloader(self.router.endpoint());
        downloader
            .download(hash, Some(provider))
            .await
            .context("download blob from provider")?;
        self.store
            .get_bytes(hash)
            .await
            .map_err(|e| anyhow::anyhow!("read fetched blob: {e}"))
    }

    pub async fn shutdown(self) -> anyhow::Result<()> {
        self.router.shutdown().await.context("shutdown router")
    }
}

/// Pair two nodes for localhost lab tests (shared address lookup).
pub fn link_peers(a: &BlobNode, b: &BlobNode) {
    a.register_peer(b.endpoint_addr());
    b.register_peer(a.endpoint_addr());
}

/// Convenience: provider offers bytes; requester fetches by hash + endpoint id.
pub async fn offer_and_fetch(payload: &[u8]) -> anyhow::Result<(Hash, EndpointId, Bytes)> {
    let provider = BlobNode::new().await?;
    let requester = BlobNode::new().await?;
    link_peers(&provider, &requester);

    let hash = provider.offer_slice(payload).await?;
    let provider_id = provider.endpoint_id();
    let fetched = requester.fetch_from(hash, provider_id).await?;

    provider.shutdown().await?;
    requester.shutdown().await?;
    Ok((hash, provider_id, fetched))
}

/// Re-export for tests and future IPC layers.
pub use iroh_blobs::Hash as BlobHash;

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn empty_offer_fetch_roundtrip() -> anyhow::Result<()> {
        let (_hash, _provider, fetched) = offer_and_fetch(b"").await?;
        assert!(fetched.is_empty());
        Ok(())
    }

    #[tokio::test]
    async fn small_offer_fetch_roundtrip() -> anyhow::Result<()> {
        let payload = b"hello-ca-store";
        let (_hash, _provider, fetched) = offer_and_fetch(payload).await?;
        assert_eq!(&fetched[..], payload);
        Ok(())
    }
}
