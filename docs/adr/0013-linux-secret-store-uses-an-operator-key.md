# ADR 0013 — Linux secret store uses an operator key

**Status:** Accepted
**Date:** 2026-07-27

## Context

Apple `SecItem` storage is protected by the platform keychain. The Linux
compatibility implementation instead persists its items in a local SQLite
database. Filesystem permissions alone do not protect that database from disk
images, backups, or another process running as the same user.

Minimal Linux and container deployments cannot reliably depend on a desktop OS
keyring. The encryption key therefore has to be an explicit operator-managed
secret rather than an implicit platform facility.

## Decision

The Linux `SecItem` store encrypts each persisted item with a key derived from
one of these startup settings:

1. `PDS_LINUX_KEYCHAIN_KEY`, supplied by the service manager's secret
   environment; or
2. `PDS_LINUX_KEYCHAIN_KEY_FILE`, a root-readable file containing the key.

The key file is preferred where the service manager can mount a protected
secret file. The store retains its `0700` parent-directory and `0600` database
permissions; encryption is additional protection, not a replacement for those
permissions.

If neither source supplies a usable key, the service fails startup. It never
opens the store or writes plaintext as a fallback. Existing plaintext rows are
read only as part of the migration and are rewritten as encrypted rows once a
key is available. That legacy reader remains for at least one release after
the encrypted format ships.

## Consequences

- Linux protection is operator-key-based encryption at rest, **not**
  hardware-backed keychain protection.
- Operators must provision and preserve the key before upgrading an existing
  installation. Losing the key makes encrypted secret-store contents
  unrecoverable; restoring a database backup without its matching key does not
  recover those secrets.
- A missing or unreadable key prevents startup loudly, which may require an
  operational fix during deployment but avoids a silent downgrade to
  plaintext.
- Upgrades migrate existing plaintext rows transactionally. Operators should
  back up both the database and the key material before deployment.
