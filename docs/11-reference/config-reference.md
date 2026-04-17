---
title: Configuration Reference
---

# Configuration Reference

## Overview

This page documents the configuration keys that `PDSConfiguration` actually reads today. It is intentionally narrower and more operational than older config docs.

The most important rule is simple:

> Use the keys the loader reads, not the keys older examples happened to show.

## Two Sources of Truth

September configuration comes from:

- JSON config files loaded through `PDSConfiguration`
- environment variables that override config-file values

Contributor confusion usually comes from mixing those two layers or assuming the runtime defaults are secure production defaults.

## Real Key Shapes

### Server

| Key | Purpose |
| --- | --- |
| `server.host` | bind host |
| `server.port` | bind port |
| `server.data_dir` | base data directory |
| `server.issuer` | canonical issuer, if explicitly set |
| `server.available_user_domains` | allowed handle domains |

Related env overrides:

- `PDS_HOST`
- `PDS_HOSTNAME`
- `PDS_DATA_DIR`
- `PDS_ISSUER`
- `PDS_AVAILABLE_USER_DOMAINS`

### PLC

| Key | Purpose |
| --- | --- |
| `plc.url` | PLC directory URL |
| `plc.retry_count` | retry count |
| `plc.retry_delay_ms` | retry delay in milliseconds |

### Debug

| Key | Purpose |
| --- | --- |
| `debug.verbose_logging` | verbose debug logging toggle |
| `debug.in_memory_databases` | use in-memory DBs |
| `debug.reset_on_startup` | reset state at startup |
| `debug.use_new_repository` | opt into alternate repository implementation |

### Database pools

| Key | Purpose |
| --- | --- |
| `database.user_pool_max_size` | actor-store pool size |
| `database.service_pool_max_size` | shared service DB pool size |
| `database.did_cache_pool_max_size` | DID cache pool size |
| `database.sequencer_pool_max_size` | sequencer pool size |

### Session

| Key | Purpose |
| --- | --- |
| `session.access_token_ttl_seconds` | access token TTL |
| `session.refresh_token_ttl_seconds` | refresh token TTL |
| `session.invite_code_required` | registration policy toggle |

### Verification and email

| Key | Purpose |
| --- | --- |
| `phone_verification.provider` | verification provider selector |
| `email.provider` | `none`, `mock`, `smtp`, or `resend` |
| `email.smtp_host` | SMTP host |
| `email.smtp_port` | SMTP port |
| `email.smtp_username` | SMTP username |
| `email.smtp_password` | SMTP password |
| `email.smtp_use_tls` | SMTP TLS toggle |
| `email.resend_api_key_source` | Resend secret source |
| `email.resend_api_key_env_var` | env var name for Resend key |
| `email.resend_keychain_service` | keychain service name |
| `email.resend_keychain_account` | keychain account name |
| `email.resend_from_address` | default from address |
| `email.resend_api_endpoint` | optional Resend API override |

### Rate limiting

| Key | Purpose |
| --- | --- |
| `rate_limit.enabled` | master toggle |
| `rate_limit.requests_per_minute` | general request budget |
| `rate_limit.burst_size` | burst allowance |
| `rate_limit.did_limit` | DID-scoped request limit |
| `rate_limit.did_window` | DID window in seconds |
| `rate_limit.ip_limit` | IP-scoped request limit |
| `rate_limit.ip_window` | IP window in seconds |
| `rate_limit.blob_limit` | blob upload limit |
| `rate_limit.blob_window` | blob limit window |

Key env overrides use the `PDS_RATELIMIT_*` prefix.

### Logging

| Key | Purpose |
| --- | --- |
| `logging.file_path` | log file path |
| `logging.level` | `debug`, `info`, `warn`, or `error` |
| `logging.format` | `text`, `json`, or `both` |
| `logging.max_file_size_mb` | rotation size |
| `logging.max_files` | retained rotated files |
| `logging.async` | async logging toggle |
| `logging.components` | enabled component list |

### NodeInfo and links

| Key | Purpose |
| --- | --- |
| `nodeinfo.enabled` | NodeInfo route toggle |
| `nodeinfo.software_name` | NodeInfo software name |
| `nodeinfo.software_version` | NodeInfo software version |
| `nodeinfo.repository_url` | repository URL |
| `nodeinfo.homepage_url` | homepage URL |
| `nodeinfo.open_registrations` | open registration flag for discovery |
| `links.privacy_policy` | privacy policy URL |
| `links.terms_of_service` | terms URL |

### Relays and AppView

| Key | Purpose |
| --- | --- |
| `relays` | relay URL array |
| `appview.url` | upstream AppView URL |
| `appview.did` | upstream AppView DID |
| `appview.local_enabled` | local AppView toggle |

This `appview` block is the current loader shape. Older camelCase examples such as `appViewURL` and `localAppViewEnabled` should be treated as stale unless the code changes.

## Defaults vs Recommended Practice

`PDSConfiguration` includes development-oriented defaults. Some of the important ones are surprising if you read them as deployment guidance:

| Runtime default | Why it exists | Production implication |
| --- | --- | --- |
| `invite_code_required = NO` | friction-free local setup | do not copy into production docs |
| `server.port = 8080` in config object | class-level default before CLI overrides | `kaszlak serve` still defaults to 2583 |

Use runtime defaults to understand the code. Use deployment docs to understand the safe operational baseline.

## Minimal Local Example

```json
{
  "server": {
    "host": "0.0.0.0",
    "port": 2583,
    "data_dir": "./pds-data"
  },
  "plc": { "url": "mock" },
  "session": { "invite_code_required": false }
}
```

## Recommended Production Baseline

For production-oriented contributor work, keep these expectations in mind:

- real issuer
- real PLC directory
- invite codes enabled
- debug flags disabled
- explicit AppView settings if proxying remote AppView traffic
- explicit `PDS_TRUST_PROXY_HEADERS=1` when running behind the documented nginx setup

Use [Tutorial 6: Deployment](../10-tutorials/tutorial-6-deployment) for the operational walkthrough.

## Common Drift Patterns

These are the config mistakes older docs tended to make:

- camelCase keys instead of snake_case
- documenting keys the loader does not read
- treating class defaults as safe deployment defaults
- omitting the environment-variable override layer

If a config example and the code disagree, trust `PDSConfiguration`.

## Related Reading

- [Setup](../01-getting-started/setup)
- [Email & Verification](../06-authentication/email-and-verification)
- [Tutorial 6: Deployment](../10-tutorials/tutorial-6-deployment)
