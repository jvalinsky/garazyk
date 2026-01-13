# Building an AT Protocol PDS from Scratch

A comprehensive tutorial series on building a Personal Data Server in Objective-C, teaching first principles of Apple development, cryptography, and the AT Protocol.

## Tutorial Overview

This tutorial guides you through building **NSPds**, an AT Protocol Personal Data Server, from the ground up. Each chapter introduces new concepts with hands-on code examples from the actual production codebase.

## Part I: Foundations

| Chapter | Title | Topics |
|---------|-------|--------|
| [1](01-introduction-to-objective-c.md) | **Introduction to Objective-C** | Classes, messaging, properties, blocks, protocols |
| [2](02-foundation-framework.md) | **The Foundation Framework** | NSString, NSData, NSArray, NSDictionary, JSON |
| [3](03-build-systems.md) | **Build Systems** | CMake, XcodeGen, project structure |

## Part II: Core Data Structures

| Chapter | Title | Topics |
|---------|-------|--------|
| [4](04-content-identifiers.md) | **Content Identifiers (CIDs)** | Hashing, multicodec, multibase, CommonCrypto |
| [5](05-cbor-serialization.md) | **CBOR Serialization** | DAG-CBOR, deterministic encoding |
| [6](06-merkle-search-trees.md) | **Merkle Search Trees** | MST structure, tree operations |
| [7](07-car-files-commits.md) | **CAR Files & Commits** | Repository commits, TIDs, signing |

## Part III: Cryptography & Identity

| Chapter | Title | Topics |
|---------|-------|--------|
| [8](08-secp256k1-cryptography.md) | **Elliptic Curve Cryptography** | secp256k1, ECDSA, libsecp256k1 |
| [9](09-decentralized-identifiers.md) | **Decentralized Identifiers** | did:key, did:plc, DID documents |
| [10](10-plc-operations.md) | **PLC Operations** | Account creation, signing |

## Part IV: Networking

| Chapter | Title | Topics |
|---------|-------|--------|
| [11](11-http-server.md) | **HTTP Server** | BSD sockets, GCD, async I/O |
| [12](12-xrpc-endpoints.md) | **XRPC Endpoints** | Protocol implementation |

## Part V: Storage & Authentication

| Chapter | Title | Topics |
|---------|-------|--------|
| [13](13-sqlite-database.md) | **SQLite Database** | C API, prepared statements |
| [14](14-oauth-jwt.md) | **OAuth 2.1 & JWT** | Authentication flow |

## Part VI: Integration

| Chapter | Title | Topics |
|---------|-------|--------|
| [15](15-complete-pds.md) | **Complete PDS** | CLI, firehose, deployment |

---

## Prerequisites

- macOS 14.0 or later
- Xcode 15.0+
- Basic programming experience (C, Swift, or similar)
- Command line familiarity

## Quick Start

```bash
# Clone the repository
git clone https://github.com/jvalinsky/NSPds.git
cd NSPds

# Generate Xcode project
xcodegen generate

# Build the CLI
xcodebuild -scheme ATProtoPDS-CLI build

# Run the server
./build/bin/atprotopds-cli serve
```

## Companion Repository

All code from this tutorial is implemented in the [NSPds repository](file:///Users/jack/Software/objpds). Each chapter references specific source files you can explore.
