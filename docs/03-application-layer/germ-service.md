---
title: Germ E2EE Mailbox Service
---

# Germ E2EE Mailbox Service

**Germ** is a standalone mailbox service built using the AT Protocol foundations for End-to-End Encrypted (E2EE) messaging.

## Overview

Unlike a standard PDS which stores public repository data, Germ is designed to handle transient, encrypted payloads. It provides a "mailbox" where encrypted messages can be deposited and later claimed by their intended recipients using cryptographic addresses.

Germ provides two core services:
1.  **Mailbox Service**: Temporary storage and relay of encrypted messages.
2.  **Identity Service**: Resolution of messaging-specific identities and keys.

## Core Concepts

### Cryptographic Addresses
In Germ, mailboxes are referenced by a 32-byte hash (the "Address") rather than a human-readable handle. This address is typically derived from the recipient's public key or a shared secret.

### Ephemeral Storage
Messages in Germ are transient. By default, mailboxes have a TTL (Time-To-Live) and messages are purged once they are claimed or the mailbox expires.

## XRPC Interface

Germ implements a custom namespace: `com.germnetwork.*`.

### Mailbox Operations
*   `com.germnetwork.mailbox.claim`: Retrieves pending messages for an address.
*   `com.germnetwork.mailbox.deposit`: Deposits an encrypted payload into a mailbox.
*   `com.germnetwork.mailbox.rendezvous`: Creates a short-lived meeting point for two clients to exchange keys.

### Identity Operations
*   `com.germnetwork.identity.resolve`: Resolves a DID or handle to a Germ address and its associated encryption keys.

## Configuration

In the local developer network, the Germ service runs on port **8082** by default.

It uses its own isolated SQLite database (`germ-mailbox.db`) to manage the state of active mailboxes and rendezvous points.

## Why standalone?

While the PDS handles the public social graph (posts, follows, likes), Germ is architected as a separate service to:
1.  **Scale independently**: Messaging traffic patterns are highly volatile and differ from repository sync.
2.  **Ensure Privacy**: The PDS data is public by design; Germ data is opaque and ephemeral.
3.  **Support Non-ATProto Clients**: While built on ATProto XRPC, the Germ mailbox can be used by any system requiring a simple, authenticated E2EE relay.
