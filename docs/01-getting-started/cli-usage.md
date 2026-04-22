---
title: Kaszlak CLI Usage
---

# Kaszlak CLI Usage

**Kaszlak** is the primary command-line interface and daemon for the Garazyk Personal Data Server (PDS). It provides tools for server management, account administration, and interactive repository debugging.

## Core Commands

### `serve`
Starts the PDS daemon.

```bash
./kaszlak serve --config /path/to/config.json --data-dir /path/to/data --foreground
```

*   `--config`: Path to the JSON configuration file.
*   `--data-dir`: Directory where SQLite databases and blobs are stored.
*   `--foreground`: Runs the server in the current terminal session (useful for logging).

### `account`
Manage user accounts on the PDS.

*   `create`: Create a new user account.
*   `delete`: Remove an account and its repository.
*   `list`: List all registered accounts.
*   `reset-password`: Force a password reset for a user.

### `invite`
Manage registration invite codes.

*   `create`: Generate one or more invite codes.
*   `list`: View all active and used codes.

### `repo`
Low-level repository and MST management.

*   `inspect`: View the MST structure of a DID's repository.
*   `import`: Load a CAR file into a local repository.
*   `export`: Export a DID's repository as a CAR file.

## Interactive REPL

Kaszlak includes an interactive shell (REPL) for developers. It can be entered by running `kaszlak` without a command or via the `repl` subcommand.

```bash
./kaszlak repl
kaszlak> help
```

The REPL supports:
*   Live inspection of the service database.
*   Manual triggering of relay crawls.
*   Testing of DID and handle resolution logic.

## Environment Variables

In addition to CLI flags, Kaszlak respects the following environment variables:

| Variable | Description |
| --- | --- |
| `PDS_CONFIG_PATH` | Default path to the configuration file. |
| `PDS_DATA_DIR` | Default directory for data storage. |
| `PDS_ADMIN_SECRET` | Secret for admin-level XRPC calls. |
| `PDS_PLC_URL` | Override for the PLC directory endpoint. |

---

## Related
- [Architecture Overview](./architecture-overview)
- [Setup Guide](./setup)
- [Reference: CLI API](../11-reference/cli-reference)
