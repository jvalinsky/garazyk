---
title: Kaszlak CLI Usage
---

# Kaszlak CLI Usage

**Kaszlak** is the primary command-line interface and daemon for the Garazyk Personal Data Server (PDS). It provides tools for server management, account administration, and interactive repository debugging.

## Invocation

The grammar is `kaszlak <command> [flags]`. Global options (`--config`, `--data-dir`, `--verbose`, `--json`) are parsed **after** the command name, not before it. For example, use `kaszlak help` for a command list, not `kaszlak --help` (the latter is rejected).

See [CLI Reference](../11-reference/cli-reference) for the full command map and per-command flags.

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

Kaszlak includes an interactive shell (REPL) for developers. Start it with the `repl` command (aliases: `shell`, `interactive`). A bare `kaszlak` invocation with no command exits with an error; always pass `repl` or another subcommand.

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
