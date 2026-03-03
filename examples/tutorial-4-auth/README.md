# Tutorial 4: Authentication Example

This example demonstrates OAuth 2.0 with JWT verification and DPoP support.

## Features

- JWT signature verification
- OAuth 2.0 authorization code flow
- DPoP proof-of-possession
- Token refresh endpoint
- Secure API authentication

## Building

```bash
mkdir -p build && cd build
cmake ..
make
```

## Running

```bash
./tutorial-4-auth
```

The server will start on port 2583.

## Testing

See the tutorial documentation for complete testing instructions:
`docs/10-tutorials/tutorial-4-auth.md`

## Quick Test

```bash
# 1. Create account
curl -X POST http://localhost:2583/xrpc/com.atproto.server.createAccount \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password","handle":"testuser"}' | jq .

# 2. Save access token
ACCESS_TOKEN=$(curl -s -X POST http://localhost:2583/xrpc/com.atproto.server.createSession \
  -H "Content-Type: application/json" \
  -d '{"identifier":"testuser","password":"password"}' | jq -r '.accessJwt')

# 3. Create record with authentication
curl -X POST http://localhost:2583/xrpc/com.atproto.repo.createRecord \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"collection":"app.bsky.feed.post","record":{"text":"Hello!"}}' | jq .
```

## Components

- `JWTVerifier` — Verifies JWT signatures and claims
- `DPoPHandler` — Handles DPoP proof generation and verification
- `OAuth2Handler` — Implements OAuth 2.0 endpoints
- `XrpcDispatcher` — Routes requests with authentication

## Security Notes

This is a tutorial example with simplified cryptography. In production:
- Use proper ECDSA P-256 signature verification
- Implement key rotation
- Add token revocation
- Use secure key storage
- Enable rate limiting
- Require HTTPS

