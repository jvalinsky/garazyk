// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

//! Fail-closed receive-only boundary for Streamplace's live iroh protocol.
//!
//! The pin-specific transport sends the narrow Subscribe/Unsubscribe RPCs and
//! accepts pushed segments only through a custom protocol handler. The handler
//! binds payload `from` to the authenticated iroh connection peer; upstream's
//! generic handler does not provide that invariant at the selected revision.

pub mod bridge;
pub mod evidence;
pub mod fault_peer;
pub mod ipc;
pub mod transport;

pub use bridge::{BridgeConfig, BridgeError, Candidate, Health, SubscriptionRequest};
