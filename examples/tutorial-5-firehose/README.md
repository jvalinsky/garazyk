# Tutorial 5: Firehose Example

This example demonstrates implementing the Firehose (subscribeRepos) endpoint for real-time event streaming.

## Features

- WebSocket upgrade from HTTP
- Real-time commit event broadcasting
- Cursor-based replay
- Backpressure detection
- Slow consumer handling

## Building

```bash
mkdir -p build && cd build
cmake ..
make
```

## Running

```bash
./tutorial-5-firehose
```

The server will start on port 2583.

## Testing

### Connect to Firehose

```bash
# Using websocat
websocat ws://localhost:2583/xrpc/com.atproto.sync.subscribeRepos

# With cursor
websocat "ws://localhost:2583/xrpc/com.atproto.sync.subscribeRepos?cursor=0"
```

### Create a Record

```bash
curl -X POST http://localhost:2583/xrpc/com.atproto.repo.createRecord \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{
    "repo": "did:plc:test123",
    "collection": "app.bsky.feed.post",
    "record": {
      "$type": "app.bsky.feed.post",
      "text": "Hello Firehose!",
      "createdAt": "2026-03-03T12:00:00Z"
    }
  }'
```

## Files

- `src/main.m` — Entry point
- `src/WebSocketConnection.{h,m}` — WebSocket connection handler
- `src/EventFormatter.{h,m}` — Event encoding
- `src/SubscribeReposHandler.{h,m}` — Firehose handler
- `src/HttpServer.{h,m}` — HTTP server with WebSocket upgrade
- `CMakeLists.txt` — Build configuration

## See Also

- [Tutorial 5 Documentation](../../docs/10-tutorials/tutorial-5-firehose.md)
- [Firehose Overview](../../docs/08-sync-firehose/firehose-overview.md)
