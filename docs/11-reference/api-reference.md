# API Reference

## Overview

This document provides a comprehensive reference for all XRPC endpoints implemented by the PDS.

## Server Methods (com.atproto.server.*)

### describeServer

Get server information.

**Endpoint:** `GET /xrpc/com.atproto.server.describeServer`

**Parameters:** None

**Response:**
```json
{
  "did": "did:web:pds.example.com",
  "availableUserDomains": ["example.com"],
  "inviteCodeRequired": false,
  "phoneNumberRequired": false,
  "links": {
    "privacyPolicy": "https://pds.example.com/privacy",
    "termsOfService": "https://pds.example.com/terms"
  }
}
```

### createAccount

Create a new user account.

**Endpoint:** `POST /xrpc/com.atproto.server.createAccount`

**Parameters:**
```json
{
  "email": "user@example.com",
  "handle": "user.example.com",
  "password": "password123",
  "inviteCode": "optional-invite-code"
}
```

**Response:**
```json
{
  "did": "did:plc:user123",
  "handle": "user.example.com",
  "email": "user@example.com",
  "accessJwt": "eyJhbGc...",
  "refreshJwt": "eyJhbGc..."
}
```

### createSession

Authenticate and create a session.

**Endpoint:** `POST /xrpc/com.atproto.server.createSession`

**Parameters:**
```json
{
  "identifier": "user.example.com",
  "password": "password123"
}
```

**Response:**
```json
{
  "did": "did:plc:user123",
  "handle": "user.example.com",
  "email": "user@example.com",
  "accessJwt": "eyJhbGc...",
  "refreshJwt": "eyJhbGc..."
}
```

### refreshSession

Refresh an access token.

**Endpoint:** `POST /xrpc/com.atproto.server.refreshSession`

**Headers:**
```
Authorization: Bearer <refresh-token>
```

**Response:**
```json
{
  "did": "did:plc:user123",
  "handle": "user.example.com",
  "accessJwt": "eyJhbGc...",
  "refreshJwt": "eyJhbGc..."
}
```

## Repository Methods (com.atproto.repo.*)

### createRecord

Create a new record in a repository.

**Endpoint:** `POST /xrpc/com.atproto.repo.createRecord`

**Headers:**
```
Authorization: Bearer <access-token>
```

**Parameters:**
```json
{
  "repo": "did:plc:user123",
  "collection": "app.bsky.feed.post",
  "record": {
    "text": "Hello, world!",
    "createdAt": "2024-01-01T00:00:00Z"
  }
}
```

**Response:**
```json
{
  "uri": "at://did:plc:user123/app.bsky.feed.post/abc123",
  "cid": "bafyreiabc123..."
}
```

### getRecord

Get a record from a repository.

**Endpoint:** `GET /xrpc/com.atproto.repo.getRecord`

**Parameters:**
```
repo=did:plc:user123
collection=app.bsky.feed.post
rkey=abc123
```

**Response:**
```json
{
  "uri": "at://did:plc:user123/app.bsky.feed.post/abc123",
  "cid": "bafyreiabc123...",
  "value": {
    "text": "Hello, world!",
    "createdAt": "2024-01-01T00:00:00Z"
  }
}
```

### updateRecord

Update an existing record.

**Endpoint:** `PUT /xrpc/com.atproto.repo.updateRecord`

**Headers:**
```
Authorization: Bearer <access-token>
```

**Parameters:**
```json
{
  "repo": "did:plc:user123",
  "collection": "app.bsky.feed.post",
  "rkey": "abc123",
  "record": {
    "text": "Updated text",
    "createdAt": "2024-01-01T00:00:00Z"
  }
}
```

**Response:**
```json
{
  "uri": "at://did:plc:user123/app.bsky.feed.post/abc123",
  "cid": "bafyreiabc123..."
}
```

### deleteRecord

Delete a record from a repository.

**Endpoint:** `DELETE /xrpc/com.atproto.repo.deleteRecord`

**Headers:**
```
Authorization: Bearer <access-token>
```

**Parameters:**
```
repo=did:plc:user123
collection=app.bsky.feed.post
rkey=abc123
```

**Response:**
```json
{}
```

### listRecords

List records in a collection.

**Endpoint:** `GET /xrpc/com.atproto.repo.listRecords`

**Parameters:**
```
repo=did:plc:user123
collection=app.bsky.feed.post
limit=50
cursor=optional-cursor
```

**Response:**
```json
{
  "records": [
    {
      "uri": "at://did:plc:user123/app.bsky.feed.post/abc123",
      "cid": "bafyreiabc123...",
      "value": { "text": "Hello" }
    }
  ],
  "cursor": "next-cursor"
}
```

## Sync Methods (com.atproto.sync.*)

### subscribeRepos

Subscribe to repository updates via WebSocket.

**Endpoint:** `GET /xrpc/com.atproto.sync.subscribeRepos` (WebSocket upgrade)

**Parameters:**
```
cursor=optional-sequence-number
```

**Events:**
```json
{
  "t": "#commit",
  "commit": {
    "root": "bafyreiabc123...",
    "prev": "bafyredef456...",
    "timestamp": "2024-01-01T00:00:00Z",
    "did": "did:plc:user123"
  },
  "seq": 12345,
  "time": "2024-01-01T00:00:00Z"
}
```

## Blob Methods (com.atproto.repo.*)

### uploadBlob

Upload a blob (file).

**Endpoint:** `POST /xrpc/com.atproto.repo.uploadBlob`

**Headers:**
```
Authorization: Bearer <access-token>
Content-Type: image/jpeg
```

**Body:** Binary blob data

**Response:**
```json
{
  "blob": {
    "cid": "bafyreiabc123...",
    "mimeType": "image/jpeg",
    "size": 12345
  }
}
```

### getBlob

Get a blob by CID.

**Endpoint:** `GET /xrpc/com.atproto.repo.getBlob`

**Parameters:**
```
did=did:plc:user123
cid=bafyreiabc123...
```

**Response:** Binary blob data

## Error Responses

### Error Format

All errors follow this format:

```json
{
  "error": "ErrorCode",
  "message": "Human-readable error message"
}
```

### Common Error Codes

| Code | Status | Description |
|------|--------|-------------|
| InvalidRequest | 400 | Malformed request |
| Unauthorized | 401 | Authentication required |
| Forbidden | 403 | Permission denied |
| NotFound | 404 | Resource not found |
| Conflict | 409 | Resource already exists |
| RateLimited | 429 | Too many requests |
| InternalServerError | 500 | Server error |

## Authentication

### JWT Token

Include in Authorization header:

```
Authorization: Bearer <jwt-token>
```

### DPoP Proof

Include DPoP proof header:

```
DPoP: <dpop-jwt>
```

## Rate Limiting

### Headers

```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1234567890
```

### Limits

- **Default:** 1000 requests per hour
- **Authenticated:** 10000 requests per hour
- **Admin:** Unlimited

## Pagination

### Cursor-Based Pagination

Use `cursor` parameter to get next page:

```
GET /xrpc/com.atproto.repo.listRecords?cursor=abc123
```

Response includes `cursor` for next page:

```json
{
  "records": [...],
  "cursor": "def456"
}
```

## Content Types

### Supported Content Types

- `application/json` — JSON data
- `application/cbor` — CBOR data
- `image/jpeg` — JPEG images
- `image/png` — PNG images
- `video/mp4` — MP4 videos

## Next Steps

- **[Configuration Reference](./config-reference.md)** — Configuration options
- **[CLI Reference](./cli-reference.md)** — Command-line interface
- **[Troubleshooting](./troubleshooting.md)** — Common issues
