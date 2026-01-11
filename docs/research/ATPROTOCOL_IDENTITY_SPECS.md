# AT Protocol: Identity and Content Identifiers Research

**Research Date:** January 11, 2026  
**Source:** [atproto.com/specs](https://atproto.com/specs)  
**Fetched:** 2026-01-11 00:15:23 UTC

---

## Table of Contents

1. [DID (Decentralized Identifier)](#did-decentralized-identifier)
2. [Handle](#handle)
3. [CID (Content Identifier)](#cid-content-identifier)
4. [Record Keys (TID)](#record-keys-tid)
5. [AT URI Scheme](#at-uri-scheme)
6. [Repository Structure](#repository-structure)

---

## DID (Decentralized Identifier)

**Source:** [atproto.com/specs/did](https://atproto.com/specs/did)

### Overview

DIDs are the long-term persistent identifiers for accounts in AT Protocol. They are a W3C standard with many implementations, but AT Protocol supports only two methods:

- **`did:plc`** - Bluesky's novel DID method (recommended)
- **`did:web`** - W3C standard based on HTTPS/DNS

### did:plc Format

```
did:plc:z72i7hdynmk6r22z27h6tvur
```

**Structure:**
- Prefix: `did:`
- Method: `plc` (lowercase letters only)
- Identifier: 24 character base32-like string (contains `a-z`, `0-9`)

### did:web Format

```
did:web:blueskyweb.xyz
```

**Structure:**
- Method: `web` (lowercase letters only)
- Identifier: hostname (no path-based DIDs supported)

### DID Document Structure

A resolved DID document contains:

```json
{
  "id": "did:plc:z72i7hdynmk6r22z27h6tvur",
  "alsoKnownAs": ["at://alice.bsky.social"],
  "verificationMethod": [{
    "id": "did:plc:...#atproto",
    "type": "Multikey",
    "controller": "did:plc:...",
    "publicKeyMultibase": "zQ3sh..."
  }],
  "service": [{
    "id": "#atproto_pds",
    "type": "AtprotoPersonalDataServer",
    "serviceEndpoint": "https://pds.example.com"
  }]
}
```

**Key Fields:**
- `alsoKnownAs[0]` - Current handle URI (`at://handle`)
- `verificationMethod` with `id` ending `#atproto`, type `Multikey`
- `service` with `id` ending `#atproto_pds`, type `AtprotoPersonalDataServer`

### Validation

**Regex:**
```regex
/^did:[a-z]+:[a-zA-Z0-9._:%-]*[a-zA-Z0-9._-]$/
```

**Examples:**

| DID | Status |
|-----|--------|
| `did:plc:z72i7hdynmk6r22z27h6tvur` | ✓ Valid (supported method) |
| `did:web:blueskyweb.xyz` | ✓ Valid (supported method) |
| `did:key:zQ3shZc2QzApp...` | ✓ Valid syntax, unsupported method |
| `did:METHOD:val` | ✗ Invalid (uppercase method) |
| `did:method:` | ✗ Invalid (ends with colon) |

---

## Handle

**Source:** [atproto.com/specs/handle](https://atproto.com/specs/handle)

### Overview

Handles are human-friendly identifiers for accounts. They are valid network hostnames with additional restrictions.

### Syntax Rules

- **Max length:** 253 characters
- **Segments:** 2+ segments separated by `.`
- **Segment rules:** 1-63 characters, `a-z`, `0-9`, `-`
- **Hyphens:** Cannot start/end segment with hyphen
- **TLD:** Cannot start with digit
- **Case:** Insensitive (normalize to lowercase)

### Validation Regex

```regex
/^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/
```

### Examples

| Handle | Status | Reason |
|--------|--------|--------|
| `jay.bsky.social` | ✓ Valid | Standard format |
| `8.cn` | ✓ Valid | Short TLD |
| `xn--notarealidn.com` | ✓ Valid | Punycode |
| `a.co` | ✓ Valid | Minimum format |
| `jo@hn.test` | ✗ Invalid | Contains `@` |
| `john..test` | ✗ Invalid | Double dot |
| `cn.8` | ✗ Invalid | TLD starts with digit |
| `www.masełkowski.pl.com` | ✗ Invalid | Non-ASCII |

### Disallowed TLDs

These TLDs fail resolution (though some pass syntax validation):

- `.alt`
- `.arpa`
- `.example`
- `.internal`
- `.invalid`
- `.local`
- `.localhost`
- `.onion`
- `.test` (allowed in development)

### Resolution Methods

#### 1. DNS TXT (Preferred)

```
Record: _atproto.bsky.app
Type: TXT
Value: did=did:plc:z72i7hdynmk6r22z27h6tvur
```

#### 2. HTTPS well-known

```
GET https://bsky.app/.well-known/atproto-did

HTTP/1.1 200 OK
Content-Type: text/plain

did:plc:z72i7hdynmk6r22z27h6tvur
```

### Best Practices

- Cache resolution results
- Validate bidirectionally (handle → DID → handle)
- Normalize to lowercase
- Use 244 character max for handle (to allow `_atproto.` prefix)

---

## CID (Content Identifier)

**Source:** [atproto.com/specs/repository](https://atproto.com/specs/repository)

### Overview

CIDs are self-describing content hashes used to identify repository data.

### Blessed Format (AT Protocol)

| Parameter | Value |
|-----------|-------|
| CID Version | v1 |
| Multicodec | `dag-cbor` (0x71) |
| Multihash | `sha-256` (0x12, 256 bits) |

### Structure

```
<version><codec><hash-alg><hash-length><hash-bytes>
```

### Examples

```
bafyreifqpitkfmqu4xwajb6xtupulh6nhj4kxsxn5wmwmwmwmwmwmwmwmwm
bafyrei3775b1d004f25f3894c3e9be4856e34ac0f457754753725e5984d50d3
```

### CID Components

1. **Version** - Always 1 for CIDv1
2. **Codec** - `dag-cbor` (0x71) for AT Protocol
3. **Hash Algorithm** - `sha-256` (0x12)
4. **Hash** - 32 bytes (256 bits)

### Usage in AT Protocol

- **Commit objects** - Repository commits
- **MST nodes** - Merkle Search Tree structure
- **Records** - Stored as DAG-CBOR, linked by CID

---

## Record Keys (TID)

**Source:** [atproto.com/specs/tid](https://atproto.com/specs/tid)

### Format

Timestamp-based identifier combining timestamp and random component:

```
<timestamp><random>
```

### Example

```
3k5d3f4g5h6j7
```

### Properties

- Lexicographically sortable by creation time
- Approximately chronological ordering
- 13 characters (base32-like)

---

## AT URI Scheme

**Source:** [atproto.com/specs/at-uri-scheme](https://atproto.com/specs/at-uri-scheme)

### Format

```
at://<did-or-handle>/<collection>/<rkey>
```

### Examples

```
at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.post/3k5d3f4g5h6j7
at://alice.bsky.social/app.bsky.graph.follow/223mc4a55jfg4
at://bob.test/app.bsky.feed.like/abc123def456
```

### Components

1. **Authority:** DID or handle
2. **Path:** `<collection>/<rkey>`
   - Collection: NSID format
   - Record Key: TID format

---

## Repository Structure

**Source:** [atproto.com/specs/repository](https://atproto.com/specs/repository)

### Overview

Repositories are per-account storage for public content. They use a Merkle Search Tree (MST) for efficient key/value storage.

### Commit Object

```json
{
  "did": "did:plc:z72i7hdynmk6r22z27h6tvur",
  "version": 3,
  "data": "bafyreix...",        // CID to MST root
  "rev": "3k5d3f4g5h6j7",       // TID revision
  "prev": null,                 // Previous commit CID (usually null)
  "sig": <signature-bytes>      // Raw signature bytes
}
```

### MST Structure

```
MST Root
├── l: CID (left subtree)
├── e: [TreeEntry, ...]
│   ├── {p: 0, k: "app.bsky.feed.post/", v: "bafyrei...", t: CID}
│   └── {p: 0, k: "app.bsky.graph.follow/", v: "bafyrei...", t: CID}
└── t: CID (right subtree)
```

### Record Paths

```
<collection>/<record-key>
```

**Examples:**
- `app.bsky.feed.post/3k5d3f4g5h6j7`
- `app.bsky.graph.follow/223mc4a55jfg4`
- `app.bsky.feed.like/abc123def456`

### Key Properties

- Sorted by collection (efficient enumeration)
- TID keys provide chronological sorting within collection
- Content-addressed (verifiable from commit signature)

---

## Quick Reference

| Element | Format | Example |
|---------|--------|---------|
| DID | `did:plc:<24-char>` | `did:plc:z72i7hdynmk6r22z27h6tvur` |
| Handle | `user.domain.tld` | `alice.bsky.social` |
| CID | `bafyrei...` (base32) | `bafyreifqpitkfmqu4xwajb6xtupulh6` |
| AT-URI | `at://did/coll/rkey` | `at://did:plc:.../app.bsky.feed.post/3k5d3f` |
| Record Key | TID format | `3k5d3f4g5h6j7` |

---

## References

1. AT Protocol Specifications. (2026). *DID*. atproto.com. https://atproto.com/specs/did
2. AT Protocol Specifications. (2026). *Handle*. atproto.com. https://atproto.com/specs/handle
3. AT Protocol Specifications. (2026). *Repository*. atproto.com. https://atproto.com/specs/repository
4. AT Protocol Specifications. (2026). *TID*. atproto.com. https://atproto.com/specs/tid
5. AT Protocol Specifications. (2026). *AT URI Scheme*. atproto.com. https://atproto.com/specs/at-uri-scheme
6. AT Protocol Specifications. (2026). *Cryptography*. atproto.com. https://atproto.com/specs/cryptography

---

*Document generated: 2026-01-11 00:15:23 UTC*  
*Last updated: 2026-01-11 00:15:23 UTC*
