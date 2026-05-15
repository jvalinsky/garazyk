---
title: CLI Reference
---

# CLI Reference

The CLI grammar is `kaszlak <command> [flags]`. Invoke the built binary directly: `./build/bin/kaszlak`.

Global flags must appear **after** the command name (e.g., `./build/bin/kaszlak account --help`). For top-level usage, run `./build/bin/kaszlak help`.

## Global Flags

| Flag | Purpose |
| --- | --- |
| `--config`, `-c` | Config file path. |
| `--data-dir`, `-d` | Data directory. |
| `--verbose`, `-v` | Debug-level logging. |
| `--json`, `-j` | JSON output for supported commands. |
| `--help`, `-h` | Command-specific help. |

## Command Map

| Command | Action |
| --- | --- |
| `serve` | Start the PDS server. |
| `status` | Check local config, storage, and reachability. |
| `account` | Manage account lifecycle and creation. |
| `invite` | Manage invite codes. |
| `oauth` | Register and inspect OAuth clients. |
| `repo` | Inspect and mutate repositories. |
| `admin` | Manage administrative users. |
| `relay` | Manage in-process relay. |
| `daemon` | Background process management. |
| `init` | Interactive configuration bootstrap. |
| `install` | macOS service installation. |
| `nuke-data` | Destructive data reset. |
| `repl` | Interactive shell mode. |

## `serve`
Starts the PDS server.
```bash
./build/bin/kaszlak serve --config ./config.json --data-dir ./pds-data --foreground
```

## `account`
Manages accounts.
- `list`: List all accounts.
- `info <did|handle>`: Show account details.
- `create`: Create a new account.
- `delete <did>`: Remove an account.

## `repo`
Provides direct repository access.
- `list <did>`: List records in a repository.
- `get <did> <uri>`: Retrieve a specific record.
- `root <did>`: Show the repository root CID.

## `nuke-data`
Resets local state by removing databases, blobs, and cached data.
```bash
./build/bin/kaszlak nuke-data
```

## Recommended Usage

### Build and Run
```bash
xcodegen generate
xcodebuild -scheme kaszlak build
./build/bin/kaszlak serve --config ./config.json --data-dir ./pds-data --foreground
```

### Local Inspection
```bash
./build/bin/kaszlak account list
./build/bin/kaszlak repo root did:plc:example
```

## Related

- [Setup](../01-getting-started/setup)
- [Config Reference](./config-reference)
- [Testing Map](./testing-map)
- [Relay Service](../03-application-layer/relay-service)
- [Documentation Map](./documentation-map)

