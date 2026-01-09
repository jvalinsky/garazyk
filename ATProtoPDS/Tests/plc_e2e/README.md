# PLC Directory E2E Tests

This directory contains end-to-end tests for simulating writes to the PLC (Public Ledger of Credentials) directory when creating new accounts with `did:plc`.

## Overview

The PLC directory is a critical component of the ATProto identity system. When a new account is created, the PDS needs to:
1. Generate a DID using the PLC method
2. Create a genesis operation that defines the identity
3. Submit the operation to the PLC directory
4. Verify the DID can be resolved

## Directory Structure

```
plc_e2e/
├── docker-compose.yml          # Docker Compose for PLC server and PostgreSQL
├── init-plc.sql                # PostgreSQL initialization script
├── run-plc-tests.sh           # PLC standalone tests
├── run-integration-tests.sh   # PDS + PLC integration tests
├── plc-server/                # Test PLC server implementation
│   ├── Dockerfile
│   ├── package.json
│   ├── tsconfig.json
│   └── src/
│       └── index.ts           # PLC server implementation
└── README.md
```

## Quick Start

### 1. Start the PLC Server

```bash
cd tests/plc_e2e

# Start PLC database and server
docker compose up -d

# Verify PLC is running
curl http://localhost:2582/xrpc/_health
# Expected: {"status":"ok"}
```

### 2. Run PLC Tests

```bash
# Run all PLC tests
./run-plc-tests.sh all

# Or run individual tests
./run-plc-tests.sh health        # Health check
./run-plc-tests.sh create        # Create account
./run-plc-tests.sh resolve did:plc:xxx  # Resolve DID
```

### 3. Run Integration Tests

```bash
# Make sure PDS is also running on port 2583
./run-integration-tests.sh
```

## Test Coverage

### PLC Server Tests

- **Health Check**: Verify PLC server is running and database is accessible
- **Account Creation**: Test `plc.createAccount` endpoint
- **Get Account**: Test `plc.getAccount` endpoint
- **DID Resolution**: Test `com.atproto.identity.resolveDid` endpoint
- **Account Update**: Test `plc.updateAccount` endpoint
- **Operation Log**: Test `plc.getOperationLog` endpoint

### Integration Tests

- **PDS Account Creation with PLC**: Full flow of creating an account on PDS and verifying PLC registration

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PLC_URL` | `http://localhost:2582` | PLC server URL |
| `PDS_URL` | `http://localhost:2583` | PDS server URL |
| `DB_HOST` | `localhost` | PostgreSQL host |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_USER` | `plc` | PostgreSQL user |
| `DB_PASSWORD` | `plc_secret` | PostgreSQL password |
| `DB_NAME` | `plc` | PostgreSQL database name |

## PLC Directory API

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/xrpc/_health` | Health check |
| POST | `/xrpc/plc.createAccount` | Create new DID |
| POST | `/xrpc/plc.updateAccount` | Update existing DID |
| GET | `/xrpc/plc.getAccount` | Get DID account |
| GET | `/xrpc/plc.getOperationLog` | Get operation history |
| GET | `/xrpc/com.atproto.identity.resolveDid` | Resolve DID to document |

### Example: Create Account

```bash
curl -X POST http://localhost:2582/xrpc/plc.createAccount \
  -H "Content-Type: application/json" \
  -d '{
    "signingKey": "kixi7nxzyoun6zhxrhs64oizlq37wd9ku6q6mws6lwhl77k6",
    "rotationKeys": [
      "kixk7nxzyoun6zhxrhs64oizlq37wd9ku6q6mws6lwhl77k6",
      "kixl7nxzyoun6zhxrhs64oizlq37wd9ku6q6mws6lwhl77k6"
    ],
    "handle": "user.example.com",
    "services": {
      "atproto_pds": {
        "type": "AtprotoPersonalDataServer",
        "endpoint": "http://localhost:2583"
      }
    }
  }'
```

### Example: Resolve DID

```bash
curl "http://localhost:2582/xrpc/com.atproto.identity.resolveDid?did=did:plc:ewvi7nxzyoun6zhxrhs64oiz"
```

## Cleanup

```bash
# Stop PLC services
docker compose down

# Remove data volumes
docker compose down -v
```

## References

- [DID PLC Method Specification](https://github.com/did-method-plc/did-method-plc)
- [ATProto Identity](https://atproto.com/docs/identity)
- [PLC Directory](https://web.plc.directory/)
