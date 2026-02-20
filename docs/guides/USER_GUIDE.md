# ATProto PDS Explorer User Guide

This guide provides procedures for using the web-based ATProto PDS Explorer to browse and analyze AT Protocol data.

## Overview

The ATProto PDS Explorer provides a web interface for exploring AT Protocol data stored in a Personal Data Server (PDS). Capabilities include:

- Browse accounts and repositories
- Examine record collections and individual records
- Resolve DIDs and handles
- Decode Content Identifiers (CIDs)
- View PLC operation logs

## Getting Started

### Accessing the PDS

1. Start the server:
   ```bash
   ./build/bin/kaszlak serve
   ```

2. Open browser: Visit `http://localhost:2583/explore/`

3. Verify functionality: Account list loads automatically

## Interface Options

### 1. Command-Line Interface (CLI)

The `kaszlak` tool is the primary way to manage your PDS server, accounts, and invite codes.

### Server Management

Start the PDS server:
```bash
./build/bin/kaszlak serve
```

Common options:
- `--port <port>`: Change the listen port (default: 2583)
- `--data-dir <path>`: Specify data directory
- `--verbose`: Enable detailed logging

### Account Management

List all registered accounts:
```bash
./build/bin/kaszlak account list
```

Create a new account:
```bash
./build/bin/kaszlak account create --email alice@example.com --handle alice.test
```

Show account details:
```bash
./build/bin/kaszlak account info alice.test
```

### Invite Codes

List all invite codes:
```bash
./build/bin/kaszlak invite list --used
```

Create a new invite code:
```bash
./build/bin/kaszlak invite create --uses 5
```

### Repository Inspection

View repository records for a DID:
```bash
./build/bin/kaszlak repo list did:plc:abc...
```

Get the root CID of a repository:
```bash
./build/bin/kaszlak repo root did:plc:abc...
```

## 2. Web Explorer

The ATProto PDS Explorer provides a web interface for exploring data visually.

### 2. Collections and Records

#### Browsing Collections
1. Select an account
2. Click "Collections" in the navigation
3. View all record namespaces (e.g., `app.bsky.feed.post`, `app.bsky.feed.like`)

#### Viewing Records
1. Click a collection name
2. Browse record list with:
   - RKey: Record key (unique within collection)
   - CID: Content identifier (shortened for display)
   - Timestamp: Creation/update time

#### Individual Record Details
1. Click any record in the list
2. View complete record content:
   - URI: Full AT Protocol URI
   - CID: Content identifier
   - Value: Complete JSON record data
   - Metadata: Timestamps and collection info

### 3. Identity Resolution

#### DID Document Lookup
1. Enter DID or handle in the lookup field
2. View resolved DID document
3. See service endpoints and verification methods

#### PLC Operations
1. Select an account or enter a DID
2. Click "PLC Operations"
3. View historical operations:
   - Create operations: Initial DID creation
   - Update operations: Key rotations, service changes
   - Operation metadata: Timestamps, signatures

### 4. Content Identifier Analysis

#### CID Decoding
1. Click "CID Decoder" in navigation
2. Enter a CID (e.g., `bafyreifac123...`)
3. View decoded information:
   - Multibase prefix: Encoding format
   - Multicodec: Content type
   - Multihash: Hash algorithm and digest
   - Raw bytes: Hexadecimal representation

#### CID Information
- Codec identification: File type, compression, etc.
- Hash verification: Algorithm used (SHA-256, etc.)
- Length information: Content size hints

## Advanced Features

### Keyboard Shortcuts

- Enter in lookup field: Resolve identity
- Enter in CID field: Decode CID
- Tab navigation: Move between interface elements

### Data Export

#### API Access
Data available via REST API:

```bash
# Get all accounts
curl http://localhost:2583/explore/api/accounts

# Get account details
curl "http://localhost:2583/explore/api/account-details?did=did:plc:..."

# Get records
curl "http://localhost:2583/explore/api/account-records?did=did:plc:...&collection=app.bsky.feed.post"
```

#### OpenAPI Specification
- Interactive docs: `http://localhost:2583/explore/api/docs`
- YAML download: `http://localhost:2583/explore/api/openapi.yaml`
- JSON format: `http://localhost:2583/explore/api/openapi.yaml?format=json`

### Performance Features

#### Client-Side Caching
- Instant reloads: Repeat views load instantly
- Background updates: Cache refreshes automatically
- Offline resilience: Cached data available when server is busy

#### Parallel Loading
- Fast account switching: Multiple API calls run simultaneously
- Reduced wait times: Load times reduced from 600ms to 250ms
- Responsive UI: Loading states prevent confusion

## Troubleshooting

### Common Issues

#### Accounts Not Loading
- Check server status: Verify server is running on port 2583
- Database connection: Ensure `data/pds.db` exists and is readable
- Network issues: Check internet connection for external API calls

#### DID Resolution Failing
- Invalid format: Ensure DID starts with `did:plc:` or handle has domain
- Network timeout: External PLC directory may be slow
- Cache issues: Try clearing browser cache

#### Collections Empty
- No records: Account may not have published content yet
- Permission issues: Some collections may be private
- Sync delays: New records may take time to appear

#### CID Decoding Errors
- Invalid CID: Check format starts with `bafy` or similar
- Unsupported codec: Some CID types may not be fully decoded
- Network issues: External resolution may fail

### Debug Information

#### Server Logs
```bash
tail -f server.log
```

#### API Health Check
```bash
curl http://localhost:2583/explore/api/accounts
```

#### Cache Status
```bash
curl http://localhost:2583/explore/api/debug
```

### Getting Help

1. Check server logs for error messages
2. Test API endpoints individually
3. Clear browser cache and reload
4. Restart server if issues persist

## API Reference

### Core Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/explore/api/accounts` | GET | List all accounts |
| `/explore/api/repositories` | GET | List all repositories |
| `/explore/api/collections` | GET | List collections for account |
| `/explore/api/describe` | GET | Describe repository |
| `/explore/api/account-records` | GET | List records for account |
| `/explore/api/record` | GET | Get single record by URI |
| `/explore/api/record-details` | GET | Get detailed record info |
| `/explore/api/lookup` | GET | Resolve handle to DID |
| `/explore/api/did` | GET | Fetch DID document |
| `/explore/api/plc-log` | GET | Get PLC operation log |
| `/explore/api/cid-decode` | GET | Decode CID |
| `/explore/api/cid-info` | GET | Get CID information |

### Query Parameters

#### Common Parameters
- `did`: DID of account/repository
- `handle`: Handle to resolve
- `uri`: AT Protocol URI
- `collection`: Record collection namespace
- `cid`: Content identifier
- `limit`: Maximum results (default 50, max 200)

### Response Formats

#### Success Response Format
```json
{
  "accounts": [...],
  "count": 6
}
```

#### Error Response Format
```json
{
  "error": "Description of error",
  "details": "Additional context"
}
```

#### Record Structure
```json
{
  "uri": "at://did:plc:.../collection/rkey",
  "did": "did:plc:...",
  "collection": "app.bsky.feed.post",
  "rkey": "abc123",
  "cid": "bafyreifac...",
  "value": { /* record content */ },
  "createdAt": "2024-01-08T20:30:00Z"
}
```

## Best Practices

### Browsing

1. Start with accounts: Get overview of available data
2. Focus on collections: Most records are in feed collections
3. Use search: Enter specific DIDs when known
4. Check PLC logs: Understand account history and changes

### Performance Tips

1. Reuse tabs: Keep explorer open for multiple sessions
2. Batch operations: Resolve multiple DIDs in sequence
3. Cache awareness: Data stays fresh for 5-10 minutes
4. Network monitoring: Watch for slow external API calls

### Data Analysis

1. Collection patterns: Understand different record types
2. CID relationships: Track content changes over time
3. PLC operations: Monitor account security and updates
4. DID resolution: Verify identity authenticity

## Security Considerations

### Data Privacy
- Local operation: All data stays on your server
- No external uploads: Explorer only reads existing data
- Cache management: Sensitive data cached temporarily

### Network Security
- HTTPS ready: Server supports TLS termination
- CORS configuration: Configurable origin restrictions
- Rate limiting: Built-in protection against abuse

## Advanced Usage

### Programmatic Access

```javascript
// Fetch accounts
const accounts = await fetch('/explore/api/accounts')
  .then(r => r.json());

// Get records for a collection
const records = await fetch('/explore/api/account-records?' +
  new URLSearchParams({
    did: 'did:plc:...',
    collection: 'app.bsky.feed.post',
    limit: 20
  }))
  .then(r => r.json());
```

### Custom Queries

```bash
# Get specific record
curl "http://localhost:2583/explore/api/record?uri=at://did:plc:.../app.bsky.feed.post/abc123"

# Search by collection
curl "http://localhost:2583/explore/api/account-records?did=did:plc:...&collection=app.bsky.feed.like"
```

### Monitoring

```bash
# Server health
curl http://localhost:2583/explore/api/debug

# API usage logs
tail -f server.log | grep "handleApi"
```

For API development details, see the [API Documentation](http://localhost:2583/explore/api/docs) or [OpenAPI Specification](http://localhost:2583/explore/api/openapi.yaml).

## Related Documentation

- **[Setup Guide](SETUP_GUIDE.md)** - Installation and server startup
- **[Developer Guide](DEVELOPER_GUIDE.md)** - API development procedures
- **[XRPC Protocol Reference](XRPC_PROTOCOL_REFERENCE.md)** - Protocol method reference
- **[Architecture Diagrams](../architecture/ARCHITECTURE_DIAGRAMS.md)** - System visual overview
- **[Data Models](../architecture/atproto_data_models.md)** - DID, CID, and record structures
- **[OAuth 2.0 Overview](../oauth2/README.md)** - Authentication for programmatic access