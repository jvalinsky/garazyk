---
title: Configuration Reference
---

# Configuration Reference

Garazyk configuration is loaded via JSON files and can be overridden by environment variables. If the code and this documentation disagree, the `PDSConfiguration` source is the final authority.

## Core Settings

### Server
| Key | Env Override | Purpose |
| --- | --- | --- |
| `server.host` | `PDS_HOST` | Bind host address. |
| `server.port` | `PDS_PORT` | Bind port number. |
| `server.data_dir` | `PDS_DATA_DIR` | Base directory for databases and blobs. |
| `server.issuer` | `PDS_ISSUER` | Canonical service DID. |

### PLC
| Key | Purpose |
| --- | --- |
| `plc.url` | PLC directory URL. Use `mock` for local tests. |
| `plc.retry_count` | Number of retries for failed PLC requests. |

### Database Pools
| Key | Purpose |
| --- | --- |
| `database.user_pool_max_size` | Max connections for actor-store databases. |
| `database.service_pool_max_size` | Max connections for the shared service database. |

### Rate Limiting
| Key | Env Override | Purpose |
| --- | --- | --- |
| `rate_limit.enabled` | `PDS_RATELIMIT_ENABLED` | Master toggle. |
| `rate_limit.requests_per_minute` | `PDS_RATELIMIT_RPM` | General request budget. |

### Logging
| Key | Values | Purpose |
| --- | --- | --- |
| `logging.level` | `debug`, `info`, `warn`, `error` | Minimum log level. |
| `logging.format` | `text`, `json` | Output format. |

## External Services

### Relays and AppView
| Key | Purpose |
| --- | --- |
| `relays` | Array of relay URLs to notify of updates. |
| `appview.url` | Upstream AppView endpoint. |
| `appview.did` | Upstream AppView DID. |

### Blob Storage
| Key | Values | Purpose |
| --- | --- | --- |
| `blob_storage.storage_type` | `disk`, `s3` | Storage backend. |
| `blob_storage.s3_bucket` | (string) | S3 bucket name. |

## Video Processing

| Key | Mode | Purpose |
| --- | --- | --- |
| `PDS_VIDEO_MODE` | `internal` | Process video in the PDS. |
| | `external` | Delegate to the `jelcz` side-car. |

## Example Configuration

```json
{
  "server": {
    "host": "0.0.0.0",
    "port": 2583,
    "data_dir": "./pds-data"
  },
  "plc": { "url": "https://plc.directory" },
  "session": { "invite_code_required": true }
}
```

## Related

- [Setup](../01-getting-started/setup)
- [Email & Verification](../06-authentication/email-and-verification)
- [Deployment](../10-tutorials/tutorial-6-deployment)
- [Documentation Map](./documentation-map)
