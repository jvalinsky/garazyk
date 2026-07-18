# skylab

Single-page Bluesky-style web portal that fronts the local ATProto stack.
Built with [Deno Fresh](https://fresh.deno.dev) and Preact. Renders one
HTML shell (`routes/index.tsx`) and proxies XRPC calls to PDS, AppView,
Relay, Chat, Video, Germ, PLC, and the Admin UI depending on the source
NSID prefix.

## Run

From this directory:

```sh
deno task dev      # hot reload at http://localhost:2591/skylab
deno task build    # production build of the Fresh manifest
deno task start    # production server (main.ts) at SKYLAB_PORT
deno task preview  # alias of `start` (both run the same main.ts)
```

Docker path: the included `Dockerfile` pins `denoland/deno:2.1.4`,
exposes `2591`, and runs `deno run -A main.ts`.

## Configuration

All settings come from environment variables. Defaults are tuned for the
local Docker network. Override any of these when running outside the
default setup.

| Variable          | Default                      | Purpose                                  |
| ----------------- | ---------------------------- | ---------------------------------------- |
| `SKYLAB_PORT`     | `2591`                       | HTTP listen port                         |
| `SKYLAB_HOST`     | `0.0.0.0`                    | HTTP listen host                         |
| `PDS_URL`         | `http://127.0.0.1:2583`      | Personal Data Server                     |
| `APPVIEW_URL`     | `http://127.0.0.1:3200`      | AppView / read-side aggregator           |
| `RELAY_URL`       | `http://127.0.0.1:2584`      | Relay (BGS)                              |
| `CHAT_URL`        | `http://127.0.0.1:2585`      | Chat / DM service                        |
| `VIDEO_URL`       | `http://127.0.0.1:2586`      | Video processing service                 |
| `GERM_URL`        | `http://127.0.0.1:8082`      | E2EE chat gateway                        |
| `PLC_URL`         | `http://127.0.0.1:2582`      | PLC directory                            |
| `UI_URL`          | `http://127.0.0.1:2590`      | Admin UI                                 |
| `VIDEO_SERVICE_DID` / `JELCZ_DID` | `did:web:localhost` | DID advertised by the video service      |

## Architecture

```
skylab/
├── main.ts          Production entry: starts Fresh with the manifest.
├── dev.ts           Dev entry: Fresh dev server with hot reload.
├── fresh.gen.ts     Generated manifest of routes/islands.
├── deno.json        Fresh + Preact import map and tasks.
├── Dockerfile       Production image.
├── routes/
│   └── index.tsx    SPA shell, injects service config inline.
├── services/
│   ├── config.ts        URL map, method routes, AppView read methods.
│   ├── routing.ts       NSID → service lookup, GET vs POST heuristic.
│   ├── proxy.ts         CORS proxy with filtered headers + binary passthrough.
│   └── control_bridge.ts Browser WS clients, command dispatch, event log.
└── static/          CSS, JS bundles, hls.js for video playback.
```

The SPA shell renders the same HTML on every load and reads its JSON
config from an inline `<script id="skylab-config">`, so first paint does
not need a separate `/api/config` round-trip. Bridge, timeline, chat,
video, admin, and firehose JavaScript modules are loaded as plain
`/js/*.js` scripts from the `static/` directory.

## Routing Logic

`services/routing.ts` decides which upstream service handles an XRPC call:

1. If the NSID starts with a known prefix (`chat.bsky`, `app.bsky.video`,
   `com.germnetwork`), route to that service.
2. Otherwise, if the method is in `APPVIEW_READ_METHODS` (timeline, feed
   generators, search skeletons, social graph reads, notifications),
   route to AppView.
3. Otherwise route to PDS.

GET vs POST is decided by `xrpcMethodUsesHttpGet()` — explicit lookup
for known query NSIDs, then a heuristic on the final NSID segment
(`get*`, `list*`, `search*`, `describe*`, `resolve*`).

## Proxy Behavior

`services/proxy.ts` forwards browser requests to the upstream service
selected by `routing.ts`. Only these request headers are forwarded:
`authorization`, `accept`, `content-type`, `user-agent`,
`atproto-accept-labelers`, `atproto-proxy`, `atproto-relay`. The
response is JSON-wrapped by default; `proxyPassthrough()` streams the
bytes unchanged for HLS segments and CDN assets where the browser
needs the real `Content-Type`. CORS is enabled on the passthrough path.

## Control Bridge

`services/control_bridge.ts` tracks connected browser WebSocket
clients, dispatches XRPC commands to the first connected client with a
30-second timeout, and keeps a 1000-entry circular event log. State
snapshots are returned as deep-copied plain objects so callers cannot
mutate the live store.
