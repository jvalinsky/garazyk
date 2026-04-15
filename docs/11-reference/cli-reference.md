---
title: CLI Reference
---

# CLI Reference

## Overview

The CLI grammar is `kaszlak <command> [flags]`. In this repository you will usually invoke the built binary directly, for example `./build/bin/kaszlak`.

This page documents the commands that are actually registered in the current codebase.

## Global Flags

| Flag | Purpose |
| --- | --- |
| `--config`, `-c` | config file path |
| `--data-dir`, `-d` | data directory |
| `--verbose`, `-v` | debug-level logging |
| `--json`, `-j` | JSON output for supported commands |
| `--help`, `-h` | usage output |

## Command Map

| Command | What it does |
| --- | --- |
| `serve` | start the PDS server |
| `status` | local status checks against config, storage, DBs, daemon state, and HTTP reachability (`health` remains an alias) |
| `account` | account creation and account lifecycle management |
| `invite` | invite code management |
| `oauth` | OAuth client registration and inspection |
| `repo` | direct repository inspection and mutation helpers |
| `admin` | administrator management |
| `relay` | in-process relay helper commands (`bgs` and `relayd` aliases) |
| `daemon` | background-process lifecycle management |
| `init` | interactive config bootstrap |
| `install` | service installation and related management |
| `nuke-data` | destructive data reset command |
| `repl` | interactive shell mode (`shell` and `interactive` aliases) |
| `help` | help output |
| `version` | version output |

## `serve`

Use `serve` for normal local development and most manual verification.

Supported options include:

- `--port`
- `--data-dir`
- `--config`
- `--log-level`
- `--log-components`
- `--foreground`

Aliases: `start`, `run`, `server`

Example:

```bash
./build/bin/kaszlak serve --config ./config.json --data-dir ./pds-data --foreground
```

## `status`

`status` is a local operator check, not a replacement for application-level protocol tests. It inspects:

- expected databases,
- storage availability,
- memory usage,
- daemon status,
- and HTTP reachability of `describeServer`.

Alias: `health`

## `account`

This command owns contributor and operator flows for account state. Current subcommands:

- `list`
- `info <did|handle>`
- `create`
- `deactivate <did>`
- `reactivate <did>`
- `delete <did>`
- `update-email <did> <email>`
- `update-handle <did> <handle>`
- `update-plc-endpoint <did> <endpoint>`

Contributor note:

- `create` can prompt interactively on a TTY
- `list` and `info` support `--json`

## `invite`

Current subcommands:

- `list`
- `create`
- `revoke <code>`

Use `invite create` and `invite list` when validating registration policy changes.

## `oauth`

Current command family:

- `oauth client register`
- `oauth client list`
- `oauth client delete`

This command talks to the service database and is useful when you are testing OAuth client metadata and registration flows without going through the browser.

## `repo`

Current subcommands:

- `list <did>`
- `get <did> <uri>`
- `root <did>`
- `create-record <did> <collection> [rkey] <json>`
- `delete-record <did> <collection> <rkey>`
- `repair <did>`

This is the fastest CLI path for validating repository behavior without building a separate client.

## `admin`

Current subcommands:

- `list`
- `add <did|handle>`
- `remove <did>`
- `create`

This manages administrator DIDs and admin account creation. It is separate from application-level moderation APIs.

## `relay`

Current subcommands:

- `serve`
- `start`
- `stop`
- `status`
- `upstream add|remove|list`

`relay serve` requires at least one `--upstream` URL. It accepts relay-specific options such as `--port`, `--retention`, and `--mode`.

This command is separate from the standalone `zuk` binary and from `PDSRelayService`, which only sends crawl hints after local record changes. For the service-layer distinction, read [Relay Service](../03-application-layer/relay-service).

## `daemon`

Current subcommands:

- `start`
- `stop`
- `restart`
- `status`

Use this when you want a background local process and PID-file-based lifecycle management instead of foreground `serve`.

## `init`

`init` is the interactive setup wizard. It writes a config file and prompts for:

- host and port,
- data directory,
- PLC mode,
- email provider basics,
- registration policy.

It is useful for bootstrapping, but contributors should still validate the output against [Config Reference](./config-reference) because older wizard output and older docs have not always stayed perfectly aligned.

## `install`

`install` handles macOS-style service installation and related helper flows. Its subcommands include:

- `daemon`
- `agent`
- `all`
- `uninstall`
- `service`
- `status`

This is a service-management convenience layer, not the main development path.

## `repl`

`repl` starts an interactive `kaszlak>` shell. It supports command history and REPL-only dot commands:

- `.help`
- `.history`
- `.clear`
- `.exit`

Aliases: `shell`, `interactive`

## `nuke-data`

This is the destructive reset command. It removes:

- actor databases,
- service and sequencer databases,
- DID cache data,
- blobs,
- and related runtime data.

Aliases: `reset`, `nuke`

Use it only when you explicitly intend to destroy local state.

## Recommended Contributor Usage Patterns

### Build and run

```bash
xcodegen generate
xcodebuild -scheme kaszlak build
./build/bin/kaszlak serve --config ./config.json --data-dir ./pds-data --foreground
```

### Inspect local state

```bash
./build/bin/kaszlak account list
./build/bin/kaszlak invite list
./build/bin/kaszlak repo root did:plc:example
```

## Common Documentation Drift to Avoid

The CLI docs were previously wrong in two ways:

- documenting command names that are not registered anymore,
- and omitting registered commands such as `serve`, `status`, `relay`, `daemon`, `oauth`, `repl`, `install`, and `nuke-data`.

If this page drifts again, regenerate it from the registered command implementations instead of copying old examples forward.

## Related Reading

- [Setup](../01-getting-started/setup)
- [Build Guide](../../BUILD.md)
- [Config Reference](./config-reference)
- [Testing Map](./testing-map)
- [Relay Service](../03-application-layer/relay-service)
