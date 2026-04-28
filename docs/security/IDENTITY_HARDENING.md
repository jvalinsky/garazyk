---
title: Identity Security Hardening (March 2026)
---

# Identity Security Hardening (March 2026)

This document outlines the security enhancements implemented for ATProto PDS identity management, focusing on rotation keys and JWT signing keys.

## Overview

The PDS identity system relies on two critical key types:
1. **PLC Rotation Keys**: Used to sign operations that update a DID's state (e.g., handle updates, service endpoint changes).
2. **JWT Signing Keys**: Used to issue authenticated sessions for users.

We have implemented a multi-layered security model to protect these keys at rest and during use.

## Hardening Measures

### 1. File & Directory Permissions
Enforced strict operating system-level permissions for all key storage:
- **Keys Directory**: `0700` (Owner read/write/execute only).
- **Key Files**: `0600` (Owner read/write only).

Implemented in `PLCRotationKeyManager.m` to ensure the singleton rotation key is protected from other users on the system.

### 2. Encryption at Rest (Master Secret)
Persistent keys are now encrypted using AES-256-CBC with a key derived from a `PDS_MASTER_SECRET`.
- **Singleton Rotation Key**: Decrypted into memory at startup; re-encrypted if stored in plain text.
- **Per-DID Rotation Keys**: Stored in account databases (`ActorStore`), now encrypted using the master secret instead of user passwords. This allows background PLC operations (like migrations) without user password input.

### 3. macOS Secure Enclave Integration
Optional hardware-backed security for JWT signing keys:
- **PDS_USE_SECURE_ENCLAVE**: When enabled, the PDS generates non-exportable keys within the Apple Secure Enclave.
- **Reference Storage**: Only the Keychain label/tag is stored in the database. The actual private key never leaves the secure hardware.
- **Fallback**: Automatically falls back to Keychain or OpenSSL if Secure Enclave is unavailable (on non-supported systems).

### 4. Per-DID Rotation Key Activation
Enabled account-specific rotation keys to resolve handle update issues for migrated accounts:
- **Priority**: The PDS checks for a per-DID rotation key in the `ActorStore` before falling back to the server-wide singleton key.
- **Compatibility**: This matches the reference ATProto PDS implementation, supporting account mobility.

## Technical Components

- **CryptoUtils**: Centralized PBKDF2 and AES-256-CBC implementation using `CommonCrypto`.
- **ActorStore**: Database layer for per-account data, updated to handle encrypted rotation keys.
- **PDSAppleKeyManager**: Refactored to support hardware-backed key generation and storage by reference.
- **XrpcIdentityMethods**: Integrated priority-based key loading for identity operations.

## Security Audit Results

A codebase-wide audit confirmed that all sensitive `secp256k1` private keys are now handled through one of the following secure paths:
1. **Hardware-bound** (Secure Enclave).
2. **Encrypted at rest** (`PDS_MASTER_SECRET`).
3. **Keychain-protected** (macOS Keychain).
4. **Non-persistent** (In-memory only for ephemeral debug sessions).
