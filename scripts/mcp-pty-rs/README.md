# garazyk-ptyd

`garazyk-ptyd` is a small Rust PTY sidecar for MCP servers. It keeps the
native pseudo-terminal lifecycle outside of the MCP stdio process and talks over
newline-delimited JSON on stdin/stdout.

This is not an MCP server. It is the process that a Deno or Node MCP server can
spawn privately while keeping MCP stdout reserved for JSON-RPC.

## Protocol

Every command is one JSON object per line:

```json
{"id":"1","op":"start","sessionId":"s1","command":"/bin/cat","args":[],"cwd":"/tmp","cols":80,"rows":24}
{"id":"2","op":"write","sessionId":"s1","data":"hello\r"}
{"id":"3","op":"resize","sessionId":"s1","cols":100,"rows":30}
{"id":"4","op":"stop","sessionId":"s1"}
{"id":"5","op":"shutdown"}
```

Responses and events are also one JSON object per line:

```json
{"id":"1","ok":true,"result":{"sessionId":"s1","pid":12345,"cols":80,"rows":24,"running":true}}
{"event":"output","sessionId":"s1","data":"aGVsbG8NCg=="}
{"event":"exit","sessionId":"s1","exitCode":0}
```

`output.data` is base64-encoded raw terminal bytes. The MCP layer should feed
those bytes into the existing terminal emulator state model before snapshotting.

## Build

```sh
cargo build --manifest-path scripts/mcp-pty-rs/Cargo.toml
```

## Smoke Test

```sh
printf '%s\n' \
  '{"id":"1","op":"start","sessionId":"s1","command":"/bin/cat","args":[],"cols":80,"rows":24}' \
  '{"id":"2","op":"write","sessionId":"s1","data":"hello\r"}' \
  '{"id":"3","op":"stop","sessionId":"s1"}' \
  '{"id":"4","op":"shutdown"}' \
| cargo run --manifest-path scripts/mcp-pty-rs/Cargo.toml
```

The command intentionally does not implement command allowlisting. Keep
allowlisting in the MCP process so policy stays in one place.
