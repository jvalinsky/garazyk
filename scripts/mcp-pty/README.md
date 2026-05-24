# garazyk-pty MCP

`garazyk-pty` is a local MCP server for external terminal programs that need a real pseudo-terminal, such as `top`, `less`, `vim`, `vi`, `nano`, and `htop`.

This is intentionally separate from `scripts/mcp-tui/`. The existing `garazyk-tui` MCP is dashboard-specific and uses `VirtualTuiHarness` for semantic snapshots. This package uses `node-pty` to run real terminal processes and `@xterm/headless` to maintain a terminal buffer for snapshots.

## Install

```sh
cd scripts/mcp-pty
npm install
npm test
```

## Codex

Add this entry to `~/.codex/config.toml`:

```toml
[mcp_servers.garazyk-pty]
command = "node"
args = ["server.mjs"]
cwd = "/Users/jack/Software/garazyk/scripts/mcp-pty"
```

Restart Codex after changing MCP configuration.

## opencode

Add this entry alongside the existing `garazyk-tui` MCP server:

```json
{
  "mcp": {
    "garazyk-pty": {
      "type": "local",
      "command": ["node", "scripts/mcp-pty/server.mjs"],
      "enabled": true
    }
  }
}
```

## Tools

- `pty_start`: start a whitelisted command in a PTY and return `{ sessionId, pid, snapshot }`.
- `pty_snapshot`: return the current screen as YAML plus structured `{ lines, cursor, cols, rows }`.
- `pty_action`: send `press_key`, `type`, or `write` input and return an updated snapshot.
- `pty_resize`: resize the PTY and headless terminal model.
- `pty_stop`: stop a session with `SIGTERM`, with optional `SIGKILL` escalation.
- `pty_list`: list live sessions.
- `pty_rec_start`: begin asciicast v2 output recording.
- `pty_rec_stop`: stop recording and export `session.cast` plus `index.html`.

Snapshot text is optimized for agents:

```yaml
- terminal "top" [session=s1] [pid=123] [running] [box=0,0,80,24]
  - line 1 "Processes: ..."
  - line 2 "CPU usage: ..."
```

MCP results also include `structuredContent` with the same screen data as JSON.

## Key Input

`press_key` supports:

- `enter` -> `\r`
- `tab` -> `\t`
- `escape` -> `\x1b`
- `backspace` -> `\x7f`
- `up`, `down`, `right`, `left` -> ANSI cursor sequences
- `ctrl-c`, `ctrl-d`, `ctrl-z`, `ctrl-l` -> control bytes

Use `type` for literal text. Use `write` for raw bytes or escape strings in advanced tests.

## Security Defaults

The server does not run arbitrary shell commands by default. Commands must be absolute paths and present in the allowlist.

Default allowlist:

- `/usr/bin/top`
- `/usr/bin/less`
- `/usr/bin/vim`
- `/usr/bin/vi`
- `/usr/bin/nano`
- `/opt/homebrew/bin/htop`
- `/usr/bin/htop`
- `/etc/profiles/per-user/jack/bin/btop`

Add more commands with `GARAZYK_PTY_MCP_ALLOW`, using a colon-separated list of absolute paths:

```sh
GARAZYK_PTY_MCP_ALLOW=/bin/cat:/usr/bin/sed node scripts/mcp-pty/server.mjs
```

Shell entrypoints named `sh`, `bash`, and `zsh` stay blocked unless `GARAZYK_PTY_MCP_ALLOW_SHELL=1` is set. Keep that disabled for normal MCP use.

Other defaults:

- `TERM=xterm-256color`
- `cols=80`
- `rows=24`
- `GARAZYK_PTY_MCP_MAX_SESSIONS=4`
- idle sessions stop after 10 minutes
- input is not recorded unless `recordInput: true` is passed to `pty_rec_start`
- semantic bounding-box overlay is available in replay HTML with `semanticOverlay: true`
- recordings store the terminal size in the asciicast header and as an initial resize event, then record later `pty_resize` calls as additional resize events

## Examples

Start `top`:

```json
{
  "name": "pty_start",
  "arguments": {
    "command": "/usr/bin/top",
    "args": ["-s", "1", "-n", "5", "-stats", "pid,command,cpu,mem"],
    "cols": 100,
    "rows": 30,
    "title": "top"
  }
}
```

Quit:

```json
{
  "name": "pty_action",
  "arguments": {
    "sessionId": "s1",
    "action": "type",
    "value": "q"
  }
}
```

Open `less` for a temporary file, search, then quit:

```json
{
  "name": "pty_action",
  "arguments": {
    "sessionId": "s2",
    "action": "type",
    "value": "/pattern\rq"
  }
}
```

Record with semantic overlay enabled:

```json
{
  "name": "pty_rec_start",
  "arguments": {
    "sessionId": "s1",
    "title": "btop with boxes",
    "semanticOverlay": true
  }
}
```

The overlay is a browser-side heuristic parser for arbitrary PTY output. It scans the replay grid for box-drawing containers and draws their bounding boxes. Dashboard-specific semantic metadata still belongs to `garazyk-tui`.

If Codex cannot spawn local processes from MCP in a particular sandbox mode, keep the server allowlist intact and adjust the Codex launch or approval boundary instead.
