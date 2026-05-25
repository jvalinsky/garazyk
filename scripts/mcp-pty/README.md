# garazyk-pty MCP

`garazyk-pty` is a local MCP server for trusted local terminal programs that need a real pseudo-terminal, such as `top`, `htop`, `btop`, and terminal games.

This is intentionally separate from `scripts/mcp-tui/`. The existing `garazyk-tui` MCP is dashboard-specific and uses `VirtualTuiHarness` for semantic snapshots. This package uses `node-pty` (or an optional Rust sidecar) to run real terminal processes and `@xterm/headless` to maintain a terminal buffer for snapshots.

## PTY Backend

By default `node-pty` spawns child processes directly. The Rust sidecar (`garazyk-ptyd`) is an alternative backend that uses `portable-pty` and communicates via a private JSONL protocol over stdin/stdout. The sidecar process is spawned once and reused for all sessions.

### Building the Rust Sidecar

```sh
cargo build --manifest-path scripts/mcp-pty-rs/Cargo.toml
```

The binary is placed at `scripts/mcp-pty-rs/target/debug/garazyk-ptyd`.

### Running with the Sidecar

Add `--sidecar` to the server command:

```sh
node scripts/mcp-pty/server.mjs --sidecar
```

Or in MCP client configuration:

```json
{
  "mcp": {
    "garazyk-pty": {
      "type": "local",
      "command": ["node", "scripts/mcp-pty/server.mjs", "--sidecar"],
      "enabled": true
    }
  }
}
```

Set `GARAZYK_PTY_SIDECAR_BINARY` to point to the built binary. Without this env var, the sidecar attempts to find `garazyk-ptyd` in `PATH`.

### Sidecar Protocol

The sidecar speaks a private JSONL protocol (not MCP). The MCP server spawns `garazyk-ptyd` privately and translates MCP tool calls to sidecar commands. Output bytes arrive base64-encoded and are decoded to UTF-8 before being fed into `@xterm/headless` for snapshots. Allowlisting stays entirely in the MCP process.

Sidecar tools also accept `--sidecar`. Usage:

```sh
node scripts/mcp-pty/corpus/runner.mjs tests/top.yaml --sidecar --record
```

## Install

```sh
cd scripts/mcp-pty
npm install

# Build the optional Rust sidecar
cargo build --manifest-path scripts/mcp-pty-rs/Cargo.toml

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
- `pty_semantic_snapshot`: return detector output plus a normalized `TuiWorld` object graph.
- `pty_world_query`: query the current `TuiWorld` with strict locators, spatial lookup, relations, actions, explanations, or validation.
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

## TuiWorld Reasoning Graph

`pty_semantic_snapshot` preserves the detector-specific arrays (`tables`, `controls`, `lists`, `popups`, `gameElements`, `charts`, and so on), then adds a normalized graph:

- `snapshot.world`: canonical graph object.
- `snapshot.elements`: alias for `snapshot.world.nodes`.
- `snapshot.relations`: alias for `snapshot.world.edges`.
- `snapshot.actions`: alias for `snapshot.world.actions`.
- `snapshot.diagnostics`: alias for `snapshot.world.diagnostics`.

The public graph shape is:

```ts
interface TuiWorld {
  frameId: string;
  viewport: { width: number; height: number };
  sources: SourceLayer[];
  nodes: TuiNode[];
  edges: TuiEdge[];
  actions: TuiAction[];
  diagnostics: TuiDiagnostic[];
}
```

`TuiNode` is the stable object representation for any detected terminal object:

```ts
interface TuiNode {
  id: string;
  ref: string;
  source: string;
  domain: "generic" | "card_game" | "table" | "form" | "chart" | "editor";
  role: string;
  label?: string;
  bounds: { x: number; y: number; w: number; h: number };
  boundsAccuracy: "exact" | "row" | "estimated";
  state: Record<string, unknown>;
  confidence: number;
  evidence: EvidenceRef[];
}
```

`ref` is the external locator key. Use `id` only for edges inside one graph. Bounds are terminal-cell coordinates with half-open width and height. `boundsAccuracy` matters: row-only or heuristic nodes are useful but should not be treated as precise layout truth.

Materialized relation edges are intentionally high-signal:

- `contains`
- `overlaps`
- `focusedBy`
- `selectedBy`
- `activates`
- `labels`
- `controls`
- `derivedFromCell`
- `derivedFromHeuristic`

Directional relations such as `above`, `below`, `leftOf`, `rightOf`, `sameRow`, and `sameColumn` are computed on demand by query helpers instead of being stored for every node pair.

`TuiAction` describes what an agent can safely do:

```ts
interface TuiAction {
  id: string;
  kind: "key" | "activate" | "focus" | "dismiss" | "select";
  key?: string;
  label?: string;
  source: string;
  sourceRef?: string;
  targetRef?: string;
  confidence: number;
}
```

`TuiDiagnostic` records graph problems rather than hiding them:

```ts
interface TuiDiagnostic {
  id: string;
  severity: "error" | "warning" | "info";
  code: string;
  message: string;
  refs: string[];
}
```

### `pty_world_query`

`pty_world_query` takes a fresh semantic snapshot and runs one query against `snapshot.world`.

Supported operations:

- `getByRole`: strict role/name/domain lookup.
- `getByRef`: resolve a node ref.
- `find`: filtered node search.
- `related`: relation lookup around a node.
- `nearest`: nearest node in a direction.
- `explain`: evidence, edges, actions, and diagnostics for one node.
- `actionsFor`: actions targeting or sourced from one node.
- `primaryAction`: best action for one node.
- `validate`: graph invariant diagnostics.

Examples:

```json
{
  "sessionId": "s1",
  "op": "getByRole",
  "role": "button",
  "name": "OK"
}
```

```json
{
  "sessionId": "s1",
  "op": "nearest",
  "ref": "card_game:cardface:k_2,1",
  "direction": "below",
  "role": "cardFace"
}
```

Strict lookup is the default. If two nodes match, `pty_world_query` returns an ambiguity error with candidate refs instead of guessing.

## Corpus Scenario Runner

`scripts/mcp-pty/corpus/runner.mjs` executes YAML scenarios against real PTY
apps. New scenarios should assert through `snapshot.world` when possible and
fall back to legacy detector arrays only for compatibility.

World-aware step types:

- `assert_world_node`
- `assert_world_relation`
- `assert_world_action`
- `assert_world_valid`
- `activate_primary`
- `select_by_role`

The corpus manifest supports curated and candidate tiers. Default batch runs
target curated scenarios; pass `--include-candidates` to include generated or
install-dependent candidates.

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
- `/opt/homebrew/bin/htop`
- `/usr/bin/htop`
- `/etc/profiles/per-user/jack/bin/btop`
- `/opt/homebrew/bin/ttysolitaire`

Add more commands with `GARAZYK_PTY_MCP_ALLOW`, using a colon-separated list of absolute paths:

```sh
GARAZYK_PTY_MCP_ALLOW=/bin/cat:/usr/bin/sed node scripts/mcp-pty/server.mjs
```

Explicitly allowed apps are trusted-local software. Apps such as pagers, editors, file managers, and terminal multiplexers can expose their own shell or file features even when the MCP server blocks direct shell entrypoints.

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

Start an explicitly allowlisted pager for a temporary file:

```json
{
  "name": "pty_start",
  "arguments": {
    "command": "/usr/bin/less",
    "args": ["/tmp/example.log"],
    "title": "less"
  }
}
```

Start the server with `GARAZYK_PTY_MCP_ALLOW=/usr/bin/less` before using that example.

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

## Testing the Sidecar

Sidecar-specific tests require the binary to be built:

```sh
cargo build --manifest-path scripts/mcp-pty-rs/Cargo.toml
node --test --test-timeout=30000 test/sidecar_test.mjs test/sidecar_corpus_test.mjs
```

Cargo tests cover the Rust sidecar itself:

```sh
cargo test --manifest-path scripts/mcp-pty-rs/Cargo.toml
```
