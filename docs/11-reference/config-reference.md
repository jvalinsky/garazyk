---
title: Configuration Reference
---

# Configuration Reference

## Configuration File

The PDS is configured via `config.json` in the working directory.

## Server Configuration

### server.host

**Type:** string  
**Default:** `0.0.0.0`  
**Description:** Server bind address

```json
{
  "server": {
    "host": "0.0.0.0"
  }
}
```json

### server.port

**Type:** integer  
**Default:** `2583`  
**Description:** Server port

```json
{
  "server": {
    "port": 2583
  }
}
```json

### server.issuer

**Type:** string  
**Required:** Yes  
**Description:** Server DID or URL (used as JWT issuer)

```json
{
  "server": {
    "issuer": "https://pds.example.com"
  }
}
```json

## Database Configuration

### database.path

**Type:** string  
**Default:** `./pds-data/db`  
**Description:** Path to database directory

```json
{
  "database": {
    "path": "./pds-data/db"
  }
}
```json

### database.maxConnections

**Type:** integer  
**Default:** `10`  
**Description:** Maximum database connections

```json
{
  "database": {
    "maxConnections": 10
  }
}
```json

## PLC Configuration

### plc.url

**Type:** string  
**Default:** `https://plc.directory`  
**Description:** PLC directory URL

```json
{
  "plc": {
    "url": "https://plc.directory"
  }
}
```json

### plc.timeout

**Type:** integer  
**Default:** `5000`  
**Description:** PLC request timeout in milliseconds

```json
{
  "plc": {
    "timeout": 5000
  }
}
```json

## Session Configuration

### session.inviteCodeRequired

**Type:** boolean  
**Default:** `true`  
**Description:** Require invite codes for account creation

```json
{
  "session": {
    "inviteCodeRequired": true
  }
}
```json

### session.accessTokenExpiry

**Type:** integer  
**Default:** `3600`  
**Description:** Access token expiry in seconds

```json
{
  "session": {
    "accessTokenExpiry": 3600
  }
}
```json

### session.refreshTokenExpiry

**Type:** integer  
**Default:** `2592000`  
**Description:** Refresh token expiry in seconds (30 days)

```json
{
  "session": {
    "refreshTokenExpiry": 2592000
  }
}
```json

## Rate Limiting Configuration

### rateLimit.enabled

**Type:** boolean  
**Default:** `true`  
**Description:** Enable rate limiting

```json
{
  "rateLimit": {
    "enabled": true
  }
}
```json

### rateLimit.requestsPerHour

**Type:** integer  
**Default:** `1000`  
**Description:** Requests per hour limit

```json
{
  "rateLimit": {
    "requestsPerHour": 1000
  }
}
```json

### rateLimit.authenticatedRequestsPerHour

**Type:** integer  
**Default:** `10000`  
**Description:** Authenticated requests per hour limit

```json
{
  "rateLimit": {
    "authenticatedRequestsPerHour": 10000
  }
}
```json

## Debug Configuration

### debug.verbose

**Type:** boolean  
**Default:** `false`  
**Description:** Enable verbose logging

```json
{
  "debug": {
    "verbose": false
  }
}
```json

### debug.logLevel

**Type:** string  
**Default:** `info`  
**Options:** `debug`, `info`, `warn`, `error`  
**Description:** Log level

```json
{
  "debug": {
    "logLevel": "info"
  }
}
```json

### debug.enableProfiling

**Type:** boolean  
**Default:** `false`  
**Description:** Enable performance profiling

```json
{
  "debug": {
    "enableProfiling": false
  }
}
```json

## Complete Example

```json
{
  "server": {
    "host": "0.0.0.0",
    "port": 2583,
    "issuer": "https://pds.example.com"
  },
  "database": {
    "path": "./pds-data/db",
    "maxConnections": 10
  },
  "plc": {
    "url": "https://plc.directory",
    "timeout": 5000
  },
  "session": {
    "inviteCodeRequired": true,
    "accessTokenExpiry": 3600,
    "refreshTokenExpiry": 2592000
  },
  "rateLimit": {
    "enabled": true,
    "requestsPerHour": 1000,
    "authenticatedRequestsPerHour": 10000
  },
  "debug": {
    "verbose": false,
    "logLevel": "info",
    "enableProfiling": false
  }
}
```json

## Environment Variables

Configuration can also be set via environment variables:

```bash
# Server
export PDS_SERVER_HOST=0.0.0.0
export PDS_SERVER_PORT=2583
export PDS_SERVER_ISSUER=https://pds.example.com

# Database
export PDS_DATABASE_PATH=./pds-data/db

# PLC
export PDS_PLC_URL=https://plc.directory

# Session
export PDS_SESSION_INVITE_CODE_REQUIRED=true

# Rate Limiting
export PDS_RATE_LIMIT_ENABLED=true

# Debug
export PDS_DEBUG_VERBOSE=false
export PDS_DEBUG_LOG_LEVEL=info
```json

## Configuration Priority

Configuration is loaded in this order (later overrides earlier):

1. Default values
2. `config.json` file
3. Environment variables
4. Command-line arguments

## Validation

The PDS validates configuration on startup:

```bash
# Check configuration
./kaszlak --config config.json --validate-config
```json

## Next Steps

- **[CLI Reference](cli-reference)** — Command-line interface
- **[Troubleshooting](troubleshooting)** — Common issues
