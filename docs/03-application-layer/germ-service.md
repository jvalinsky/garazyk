---
title: Germ E2EE Mailbox Service
---

# Germ E2EE Mailbox Service

**Germ** is a standalone mailbox service providing End-to-End Encrypted (E2EE) messaging foundations for the AT Protocol.

## Overview

While a standard PDS stores public repository data, Germ handles transient, encrypted payloads. It provides a "mailbox" infrastructure where encrypted messages are deposited and claimed by recipients using cryptographic addresses.

Germ provides two core services:
1.  **Mailbox Service**: Temporary storage and relay of encrypted messages.
2.  **Identity Service**: Resolution of messaging-specific identities and keys.

## Core Concepts

### Cryptographic Addresses
Mailboxes are referenced by a 32-byte hash (the "Address") rather than a handle. This address is derived from the recipient's public key or a shared secret.

### Ephemeral Storage
Messages are transient. Mailboxes utilize a Time-To-Live (TTL) mechanism, and messages are purged once they are claimed or the mailbox expires.

## XRPC Interface

Germ implements the `com.germnetwork.*` namespace.

### Mailbox Operations
- **`com.germnetwork.mailbox.claim`**: Retrieves pending messages for an address.
- **`com.germnetwork.mailbox.deposit`**: Deposits an encrypted payload into a mailbox.
- **`com.germnetwork.mailbox.rendezvous`**: Creates a short-lived meeting point for key exchange.

### Identity Operations
- **`com.germnetwork.identity.resolve`**: Resolves a DID or handle to a Germ address and encryption keys.

## Configuration

In the local developer network, Germ runs on port **8082**. It utilizes an isolated SQLite database (`germ-mailbox.db`) to manage active mailboxes and rendezvous points.

## Architecture and Scaling

Germ is architected as a separate service to:
1.  **Isolate Traffic**: Messaging patterns differ significantly from repository sync and social graph activity.
2.  **Privacy by Design**: Unlike public PDS data, Germ payloads are opaque and ephemeral.
3.  **Broad Compatibility**: The mailbox can be used by any system requiring an authenticated E2EE relay, even those outside the social AT Protocol.

## Related

- [Services Overview](./services-overview)
- [PDS Application Facade](./pds-application)
- [Safety and Compliance](./safety-and-compliance)
- [Cryptography](../02-core-concepts/cryptography)
- [Identity Resolution](../02-core-concepts/identity-resolution)
