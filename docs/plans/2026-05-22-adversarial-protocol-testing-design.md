# Adversarial Protocol Abuse Testing Design

**Date:** 2026-05-22
**Topic:** Live Network E2E Test Gaps (ATProto)

## Overview
A deep code review of the current 63 e2e scenarios revealed that while application-level edge cases (rate limiting, noisy neighbors, reconnects) are well-covered, we lack coverage for **Adversarial Protocol Abuse**—specifically, attacks targeting the ATProto federation and synchronization layers.

This design outlines three new scenarios to test the robustness of our Relay, AppView, and PDS implementations against malicious network payloads.

---

## 1. MST Exploitation (Merkle Search Tree Poisoning)
**Scenario File:** `64_mst_poisoning.ts`

**Context & Threat:** 
ATProto relies on Merkle Search Trees (MST) for efficient repository synchronization. An adversarial PDS could craft a pathological MST to degrade AppView/Relay ingestion by generating record keys (`rkey`) that share long common prefixes in base32 sorting. This forces the MST to become extremely unbalanced (deep) or excessively wide at specific nodes.

**Architecture & Flow:**
1. **Setup:** A bad-actor character (`troll.test`) connects to the network.
2. **Payload Generation:** The scenario bypasses standard `TID` generators and creates a payload of 500+ records where the first 10 characters of every `rkey` are identical. This forces deep splits in the MST.
3. **Execution:** The bad actor commits these records via `com.atproto.repo.applyWrites`.
4. **Validation:**
   - The test monitors local PDS performance and observes the Relay and AppView during `subscribeRepos`.
   - The system must handle the load gracefully (bounded processing time) or reject the commit if it exceeds a maximum tree depth threshold.
   - The test asserts that the time to sync the repo scales linearly, without unbounded memory consumption or crashes.

---

## 2. Firehose Sequencer Attacks
**Scenario File:** `65_firehose_fuzzing.ts`

**Context & Threat:** 
The ATProto Firehose (`com.atproto.sync.subscribeRepos`) relies on sequence numbers (`seq`) and timestamps (`time`) for cursor tracking. A malicious PDS could emit events with massive sequencer gaps, regressive sequence numbers, or impossible timestamps, aiming to corrupt consumer state or cause OOMs.

**Architecture & Flow:**
1. **Setup:** A second PDS (`PDS 2` in the local network) is configured as the adversarial node.
2. **Payload Generation:** We mock or intercept the firehose emitter on PDS 2 to emit anomalous events:
   - *Gaps:* `seq=100`, followed immediately by `seq=1000000000000`.
   - *Regressions:* `seq=105`, followed by `seq=102`.
   - *Time-Travel:* Events with `time` set 50 years in the future.
3. **Validation:**
   - *Gaps:* The Relay/AppView must handle the gap without attempting to allocate memory for skipped numbers.
   - *Regressions:* Consumers must reject or drop regressive sequences, maintaining their high-water mark without crashing.
   - *Time-Travel:* The system must reject impossible timestamps to prevent content from becoming permanently "sticky" in chronologically sorted feeds.

---

## 3. DAG-CBOR Zip Bombs & Payload Bloat
**Scenario File:** `66_cbor_bombs.ts`

**Context & Threat:** 
A malicious PDS could construct a "Zip Bomb" (a dense CBOR structure that expands into gigabytes in memory) or a deeply nested structure that bypasses lexicon depth checks, targeting the CBOR decoder directly to trigger OOMs or infinite loops.

**Architecture & Flow:**
1. **Setup:** The bad-actor character (`troll.test`) connects to the network.
2. **Payload Generation:** We construct raw CBOR blocks bypassing the standard XRPC client:
   - *Memory Bomb:* A CBOR array with a massive length header but containing only millions of `null` values.
   - *Reference Loops:* Circular IPLD references designed to trap the parser in an infinite loop.
3. **Execution:** The payload is pushed to the PDS via `com.atproto.repo.applyWrites` or `com.atproto.sync.notifyOfUpdate`.
4. **Validation:**
   - The PDS CBOR parser must enforce strict memory limits, array length limits, and cyclomatic checks *before* full decoding.
   - The PDS should return a `400 Bad Request` or safely drop the connection.
   - Concurrent health checks from another client will verify that the event loop is not locked and no OOM occurred.