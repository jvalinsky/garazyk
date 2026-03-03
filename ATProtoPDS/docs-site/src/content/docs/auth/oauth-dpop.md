---
title: OAuth2, PKCE, and DPoP
description: Demonstrating Proof-of-Possession at the Application Layer to prevent Token Theft
---

A Personal Data Server (PDS) holds the keys to the user's root cryptographic identity. If an attacker gains an active session token to a conventional Web2 service, they might read some emails or post spam. In a decentralized ATProtocol network, if a malicious actor gains a token with administrative scope to your PDS, they can mathematically and permanently destroy or irrevocably hijack the user's entire digital presence across the federation.

To rigorously defend against this catastrophic scenario, `ATProtoPDS` deliberately does *not* rely on standard, bare HTTP Bearer tokens for sensitive client-to-server API requests. Instead, it implements a highly secure, full-fledged **OAuth 2.0 Authorization Server** deeply integrated with **PKCE** (Proof Key for Code Exchange) and **DPoP** (Demonstrating Proof-of-Possession) precisely conforming to the rigorous [RFC 9449](https://datatracker.ietf.org/doc/html/rfc9449) specifications.

## The Vulnerability of Bearer Tokens

Traditional API Bearer tokens are exactly like physical hotel room keys: whoever physically holds the plastic keycard can open the door. The door lock doesn't know or care whose face is holding the card. 

If a long-lived API token is accidentally stolen from an AWS log file, dumped from an insecure MongoDB database, sniffed over a malicious corporate WiFi proxy, or extracted via an XSS vulnerability, the attacker instantly gains full, unmitigated access. They can impersonate the user, read entirely private data, and perform wildly destructive actions completely without needing the user's actual password credentials.

By implementing PKCE and DPoP flows natively inside the Objective-C networking stack, `ATProtoPDS` mathematically and continuously binds the issued access token exactly to the physical hardware client device that originally requested it, definitively neutralizing remote token theft.

---

## OAuth 2.0 & PKCE

When a mobile third-party app wants to log a user into our globally federated PDS, they must follow the established OAuth 2.0 Authorization Code flow. However, standard authorization flows deployed on mobile OS platforms (like iOS and Android) are inherently vulnerable to "Authorization Code Interception" attacks. In this attack vector, a malicious app silently installed on the victim's phone subtly registers the exact same custom URI routing scheme (e.g., `bluesky://`) to hijack the operating system redirect and steal the authorization code right out of the URL string.

The server decisively mitigates this mobile attack vector by strictly mandating **PKCE**:

1. **Generate**: The client app secretly generates a random, cryptographically secure 43+ character string locally called the `code_verifier`.
2. **Hash**: The client hashes the secret verifier using SHA-256 and base64url-encodes the result to strictly create a `code_challenge`.
3. **Authorize**: The client sends the `code_challenge` and `code_challenge_method` (mandated as `S256`) to the PDS during the initial browser authorize request.
4. **Exchange**: When the client attempts the backend API call to successfully exchange the returned `code` for an access token, the PDS violently mandates that they provide the original, raw `code_verifier`.

In the `OAuth2Server` initialization, the networking module mathematically validates this cryptographic guarantee to ensure the entity exchanging the code over the backend is definitively the exact same entity that initiated the initial front-end authorization request:

```objc
// Strict PKCE mathematical verification during the token exchange pathway
NSString *expectedChallenge = session.codeChallenge;
NSString *providedVerifier = request.codeVerifier;

if (expectedChallenge.length > 0) {
    // We recreate the S256 hash mathematically on the server side
    NSString *hashedVerifier = [PKCEUtil SHA256StringFrom:providedVerifier];
    
    // Constant-time string comparison to tightly prevent side-channel timing attacks
    if (![CryptoUtils constantTimeCompareString:hashedVerifier withString:expectedChallenge]) {
        // Attack definitively detected: The malicious interception client 
        // attempting to exchange the stolen code does not physically possess 
        // the original secret verifier string in its RAM.
        return @{ @"error": @"invalid_grant" };
    }
}
```

---

## DPoP (Demonstrating Proof-of-Possession)

PKCE elegantly secures the initial login flow. **DPoP [RFC 9449]** goes a massive step further by cryptographically binding the resulting access token to a specific private key held *only* on the client's local physical device (often heavily guarded within Apple's Secure Enclave or Android's hardware-backed keystore).

When the client securely requests an access token, they generate an entirely new Elliptic Curve keypair (e.g., NIST P-256). They send only their Public Key, formally encoded as a standard JSON Web Key (JWK), up to the PDS securely inside a signed `DPoP` HTTP header. The PDS then issues an access token JWT that is permanently mathematically bound to the thumbprint (JKT) of that exact Public Key.

### Verifying the DPoP Proof

For absolutely every single protected API request going forward, the client app cannot just send the token; it must use its local hardware Private Key to synchronously sign a brand new JWT specifically containing the requested HTTP Method, the exact URL, and a continuously rotating server-provided nonce. They attach this freshly computed JWT as the `DPoP` HTTP Header right alongside the standard `Authorization: DPoP <token>` header.

The highly optimized `AuthCryptoDPoP` module in `ATProtoPDS` rigorously enforces strict multi-stage verification to entirely prevent interception and dangerous replay attacks:

1. **Signature Verification**: Validates the JWT signature curve mathematically against the embedded Public Key (`jwk` header claim).
2. **Method & URI Binding**: Asserts the JWT's `htu` (HTTP Target URI claim) strictly matches the canonical URL the server actually routed to, and the `htm` (HTTP Method claim) strictly matches `GET`, `POST`, etc. If an attacker intercepts a read request for `/feed` and tries to blindly replay that signed Header to a `POST` on `/delete`, the `htm` validation will explicitly fail.
3. **Nonce Freshness**: Uses the `AuthCryptoDPoPNonceValidator` (backed by the thread-safe `PDSNonceManager`) to strictly verify the client actually included the latest cryptographic `nonce` provided independently by the server. If a nonce is totally missing or stale, the server aggressively rejects the request with a `use_dpop_nonce` error.
4. **Replay Protection**: Uses the `AuthCryptoDPoPReplayChecker` (backed by a fast LRU `PDSReplayCache`) to definitively verify the `jti` (JWT ID claim). It enforces a strict TTL constraint to fundamentally prevent an attacker from sniffing traffic and instantly replaying the exact same identical request byte-for-byte milliseconds later.
5. **Token Binding**: Finally, if an active access token is indeed presented on the socket, the server asserts that the `ath` (Access Token Hash) claim inside the meticulously verified DPoP signature flawlessly matches the SHA-256 hash of the presented Access Token.

```objc
// Core Server-side verification pipeline of an incoming DPoP proof
BOOL isValid = [AuthCryptoDPoP verifyProof:dpopJwtString
                                    method:request.HTTPMethod
                                       url:request.URL
                                     nonce:expectedServerNonce
                              requireNonce:YES
                            nonceValidator:(id<AuthCryptoDPoPNonceValidator>)[PDSNonceManager sharedManager]
                             replayChecker:(id<AuthCryptoDPoPReplayChecker>)[PDSReplayCache sharedCache]
                             outThumbprint:&verifiedThumbprint
                                     error:&cryptoError];

if (!isValid) {
    // Aggressively reject the request immediately. The proof may be fundamentally malformed, 
    // mathematically expired, physically replayed, or forged with the wrong key.
    return NO;
}

// Ensure the request's actual Access Token string flawlessly matches the token 
// that the client's DPoP signature explicitly mathematically expects.
NSString *expectedAthHash = dpopPayload[@"ath"];
NSString *actualAthHash = [CryptoUtils sha256Base64UrlEncodedString:accessTokenString];

if (![expectedAthHash isEqualToString:actualAthHash]) {
    // Attack detected! DPoP signature mathematically is valid for the endpoint, 
    // but the access token was maliciously swapped out by a proxy, 
    // or the DPoP signature was illegally reused on a totally different token.
    return NO; 
}
```

### The Strict Nonce Mechanism

To further structurally prevent intelligent attackers from maliciously pre-generating hundreds of mathematically valid DPoP proofs for future predicted requests and storing them, `ATProtoPDS` heavily relies on DPoP Nonces.

1. The server seamlessly includes a `DPoP-Nonce` HTTP header in its standard API responses.
2. The client must intelligently extract this fresh nonce and precisely embed it into the payload of their *very next* outgoing DPoP proof JWT.
3. If the server receives an inbound proof without a nonce, or with an expired/stale nonce, it gracefully but firmly responds with a `401 Unauthorized` and `WWW-Authenticate: DPoP error="use_dpop_nonce"`, providing a brand new fresh nonce for the client connection to immediately retry.

---

## Conclusion

By strictly enforcing both PKCE during the initial OAuth authorization graph and DPoP for absolutely all proceeding live API requests, `ATProtoPDS` architecturally guarantees that even if a Bearer token is stolen or leaked publicly on Pastebin, the attacker cannot execute a single API request on behalf of the user without also somehow physically stealing the user's silicon private key from their phone. This extreme, multi-layered defensive strategy provides the incredibly robust, application-layer cryptographic security necessary for a planetary decentralized identity network.