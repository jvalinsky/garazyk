---
title: CLI Reference
---

# CLI Reference

## Overview

The PDS command-line interface is provided by the `kaszlak` binary (macOS) or `september` binary (Linux).

## Global Options

### --help

Display help message.

```bash
./kaszlak --help
```

### --version

Display version information.

```bash
./kaszlak --version
```

### --config

Specify configuration file path.

```bash
./kaszlak --config ./config.json
```

### --data-dir

Specify data directory path.

```bash
./kaszlak --data-dir ./pds-data
```

### --verbose

Enable verbose logging.

```bash
./kaszlak --verbose
```

### --json

Output in JSON format.

```bash
./kaszlak --json
```

## Commands

### server

Start the PDS server.

```bash
./kaszlak server --config config.json --data-dir ./pds-data
```

**Options:**
- `--config` — Configuration file path
- `--data-dir` — Data directory path
- `--port` — Server port (overrides config)
- `--verbose` — Verbose logging

### account

Manage user accounts.

#### account create

Create a new user account.

```bash
./kaszlak account create \
  --email user@example.com \
  --handle user.example.com \
  --password password123
```

**Options:**
- `--email` — User email (required)
- `--handle` — User handle (required)
- `--password` — User password (required)
- `--invite-code` — Invite code (if required)

**Output:**
```json
{
  "did": "did:plc:user123",
  "handle": "user.example.com",
  "email": "user@example.com"
}
```

#### account delete

Delete a user account.

```bash
./kaszlak account delete --did did:plc:user123
```

**Options:**
- `--did` — User DID (required)

#### account list

List all user accounts.

```bash
./kaszlak account list --limit 10
```

**Options:**
- `--limit` — Number of accounts to list
- `--cursor` — Pagination cursor

### invite

Manage invite codes.

#### invite create

Create an invite code.

```bash
./kaszlak invite create
```

**Output:**
```json
{
  "code": "abc123def456",
  "createdAt": "2024-01-01T00:00:00Z",
  "expiresAt": "2024-02-01T00:00:00Z"
}
```

#### invite list

List all invite codes.

```bash
./kaszlak invite list
```

**Output:**
```json
{
  "invites": [
    {
      "code": "abc123def456",
      "createdAt": "2024-01-01T00:00:00Z",
      "expiresAt": "2024-02-01T00:00:00Z",
      "usedBy": "did:plc:user123"
    }
  ]
}
```

#### invite revoke

Revoke an invite code.

```bash
./kaszlak invite revoke --code abc123def456
```

**Options:**
- `--code` — Invite code (required)

### database

Manage databases.

#### database migrate

Run database migrations.

```bash
./kaszlak database migrate
```

#### database backup

Backup databases.

```bash
./kaszlak database backup --output ./backup.tar.gz
```

**Options:**
- `--output` — Output file path (required)

#### database restore

Restore databases from backup.

```bash
./kaszlak database restore --input ./backup.tar.gz
```

**Options:**
- `--input` — Input file path (required)

### admin

Administrative commands.

#### admin takedown

Takedown a record.

```bash
./kaszlak admin takedown --uri at://did:plc:user123/app.bsky.feed.post/abc123
```

**Options:**
- `--uri` — Record URI (required)

#### admin suspend

Suspend a user account.

```bash
./kaszlak admin suspend --did did:plc:user123
```

**Options:**
- `--did` — User DID (required)

#### admin label

Apply a label to a record.

```bash
./kaszlak admin label --uri at://did:plc:user123/app.bsky.feed.post/abc123 --label spam
```

**Options:**
- `--uri` — Record URI (required)
- `--label` — Label to apply (required)

### health

Check server health.

```bash
./kaszlak health
```

**Output:**
```json
{
  "status": "ok",
  "uptime": 3600,
  "version": "1.0.0"
}
```

### config

Manage configuration.

#### config validate

Validate configuration file.

```bash
./kaszlak config validate --config config.json
```

**Options:**
- `--config` — Configuration file path (required)

#### config show

Display current configuration.

```bash
./kaszlak config show
```

## Examples

### Start Server

```bash
./kaszlak server \
  --config ./config.json \
  --data-dir ./pds-data \
  --verbose
```

### Create Account

```bash
./kaszlak account create \
  --email alice@example.com \
  --handle alice.example.com \
  --password secure-password-123
```

### Create Invite Code

```bash
./kaszlak invite create
```

### Backup Database

```bash
./kaszlak database backup --output ./backup-$(date +%Y%m%d).tar.gz
```

### Check Health

```bash
./kaszlak health --json
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Command-line syntax error |
| 3 | Configuration error |
| 4 | Database error |
| 5 | Network error |

## Environment Variables

### PDS_CONFIG

Configuration file path.

```bash
export PDS_CONFIG=./config.json
./kaszlak server
```

### PDS_DATA_DIR

Data directory path.

```bash
export PDS_DATA_DIR=./pds-data
./kaszlak server
```

### PDS_LOG_LEVEL

Log level.

```bash
export PDS_LOG_LEVEL=debug
./kaszlak server
```

## Troubleshooting

### Command not found

```bash
# Make sure binary is in PATH
export PATH=$PATH:./build/bin
./kaszlak --version
```

## Configuration error

```bash
# Validate configuration
./kaszlak config validate --config config.json
```

## Database error

```bash
# Check database
./kaszlak database migrate
```

## Next Steps

- **[API Reference](api-reference)** — API endpoints
- **[Troubleshooting](troubleshooting)** — Common issues
