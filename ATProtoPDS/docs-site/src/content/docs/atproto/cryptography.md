---
title: Cryptography & Digital Identity
description: P-256 Signatures, DIDs, OpenSSL validation, and defending against transaction malleability
---

A foundational, non-negotiable principle of the AT Protocol is that your data is organically, cryptographically signed. In traditional web architectures, placing trust in a central server is mandatory; if the server says Jack posted "Hello Word", we trust that Jack actually posted it. 

In a federated ATProto environment, this trust model is completely inverted. If a remote Personal Data Server (PDS) goes rogue, is seized by a malicious actor, or suffers a catastrophic database breach, it absolutely **cannot** forge posts seemingly originating from your identity or steal your handle. This is fundamentally because all records in your repository MUST be digitally signed by your secure private key before being ingested into the global state. 

## Keys, Handles, and DIDs

To understand how `ATProtoPDS` secures your data, we must decouple human-readable names from cryptographic identities.

Your handle (e.g., `@jack.bsky.social`) is merely a domain name alias. It can change at any time (for instance, rotating a domain to `@jack.dev`). Your **DID** (Decentralized Identifier, e.g., `did:plc:ragtjsm...`) is the true cryptographic root of your identity. Most Bluesky users are assigned a `did:plc` (DID Placeholder) identifier, which is anchored to a public registry containing their cryptographic public keys.

When a client application (like the Bluesky mobile app) wants to mutate your repository (like creating a new post, deleting a like, or updating a profile picture), it constructs a raw JSON/CBOR payload. Critically, before dispatching this payload over HTTP, the client SDK computes an Elliptic Curve Digital Signature Algorithm (ECDSA) digital signature of that exact payload using the user's private key.

The server's job is to ruthlessly verify this signature against the public key declared in the user's DID Document. If the signature is invalid, the PDS aggressively drops the request with an HTTP 401 Unauthorized, protecting the repository.

## Validating Signatures with OpenSSL

Our Objective-C server securely utilizes the low-level OpenSSL C-API functions under the hood (specifically `libcrypto`). Native execution is drastically faster than dropping into runtimes like Node.js. 

We wrap these complex, potentially dangerous memory operations in an overarching, memory-safe `AuthCrypto` Objective-C architecture to prevent accidental leaks. Both the P-256 (secp256r1) and secp256k1 curves are strictly supported by ATProto.

```objc
- (BOOL)verifySignature:(NSData *)sig 
                forData:(NSData *)data 
              publicKey:(NSData *)pubKeyBytes
              algorithm:(NSString *)alg {
    
    // In actual implementation, we map ATProto algorithm strings (ES256K or ES256) 
    // to the appropriate OpenSSL EVP_PKEY and EVP_MD_CTX C-structures natively.
    
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    
    // Initialize the context for a SHA-256 digest payload
    EVP_DigestVerifyInit(ctx, NULL, EVP_sha256(), NULL, pkey);
    
    // Hash the target JSON CBOR payload exactly as the client constructed it
    EVP_DigestVerifyUpdate(ctx, data.bytes, data.length);
    
    // Verify the decrypted digest mathematically matches the provided signature
    int result = EVP_DigestVerifyFinal(ctx, sig.bytes, sig.length);
    
    // Always free the C-structs to prevent ARC leakage in high-throughput servers
    EVP_MD_CTX_free(ctx);
    
    return result == 1; // 1 == Secure Authorization Valid
}
```

## Defending Against ECDSA Signature Malleability (BIP-62)

Because ATProto natively allows signing identity payloads via the standard `secp256k1` elliptic curve (popularized by Bitcoin), signatures dispatched by clients are typically formatted in standard ASN.1/DER string encodings. This presents a critical vulnerability.

A severe **Transaction Malleability Attack** (originally codified, attacked, and heavily documented in Bitcoin's BIP-62 specification) occurs because the `r` and `s` integer constants in ECDSA signatures can theoretically be maliciously padded with multiple leading `0x00` zero-bytes over the network by a man-in-the-middle. 

A naive validation function simply parses this payload and passes the mutated signature array directly into the underlying OpenSSL crypto engine. Because `0` exactly equals `000` mathematically, the OpenSSL verification flawlessly succeeds in validating the signature! 

However, because the signature string is now physically longer and has different bytes, it fundamentally alters the signature's own checksum hash.

If the PDS records this mutated payload naively into the Merkle Search Tree (MST), a malicious actor might successfully alter the CID (Content Identifier) of the commit. Since the CID changes, the root hash of the MST changes, effectively allowing the attacker to poison the tree's hash validation and cause downstream relays to fork the state of the repository, essentially breaking synchronization.

### The Canonical Fix

To combat this, the `AuthCryptoECDSA` module inside `ATProtoPDS` explicitly enforces strict mathematical length properties. It strictly parses the ASN.1 tree and strips any invalid sequences of leading `0x00` from the integers to mathematically yield a pure, canonically minimized "Raw" ECDSA signature format *before* executing the OpenSSL `EVP_DigestVerifyFinal` operation.

```objc
// Iterate and slice raw NSData bytes safely out of memory
NSMutableData *r = [rData mutableCopy];

// Look for mathematically identical padding
while (r.length > 0 && ((const uint8_t *)r.bytes)[0] == 0x00) {
    // Strip zero padding aggressively to stop Malleability Attacks
    // We rewrite the byte array entirely.
    [r replaceBytesInRange:NSMakeRange(0, 1) withBytes:NULL length:0];
}
```

By guaranteeing a strictly canonical signature profile before writing it to SQLite or generating the block CID, `ATProtoPDS` robustly secures the Merkle Root from tampering and guarantees deterministic replication across the AT Protocol ecosystem.

> [!WARNING]
> If you are implementing a custom ATProto client or server, failing to account for Signature Malleability during CID generation is a critical bug that will eventually break federation with official relays when a padded signature enters the network.
