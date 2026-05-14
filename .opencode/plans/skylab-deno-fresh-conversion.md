# SkyLab: FastAPI → Deno/Fresh Conversion Plan

## Goal

Replace the Python FastAPI server (`skylab/server.py`) with a Deno + Fresh application that serves the same SPA, provides the same Control Bridge API (HTTP + WebSocket), and runs the same CORS proxy — all in TypeScript using the patterns established in `scripts/scenario-dashboard/`.

The existing browser-side JS modules (`skylab-bridge.js`, `skylab-timeline.js`, etc.) and CSS (`skylab.css`) remain **unchanged** — they are static assets served by the new Deno server. The conversion is server-side only.

## Architecture

```
skylab/
├── deno.json                    # Deno config, imports, tasks
├── dev.ts                       # Fresh dev server entry
├── main.ts                      # Fresh production server entry
├── fresh.gen.ts                 # Auto-generated Fresh manifest
├── routes/
│   ├── index.tsx                # GET /skylab — serve SPA shell
│   ├── api/
│   │   ├── config.ts            # GET /skylab/api/config
│   │   ├── health.ts           # GET /skylab/api/health
│   │   ├── state.ts            # GET/POST /skylab/api/state
│   │   ├── events.ts          # GET/POST /skylab/api/events
│   │   ├── auth.ts            # POST /skylab/api/auth
│   │   ├── reset.ts           # POST /skylab/api/reset
│   │   ├── execute.ts         # POST /skylab/api/execute
│   │   ├── debug/
│   │   │   └── appview-timeline.ts  # GET /skylab/api/debug/appview-timeline
│   │   └── ws.ts              # WebSocket upgrade handler
│   └── proxy/
│       └── [service]/[...path].ts  # CORS proxy: /skylab/proxy/{service}/{path}
├── services/
│   ├── config.ts               # SERVICE_URLS, METHOD_ROUTES, APPVIEW_READ_METHODS
│   ├── routing.ts              # _route_method(), _xrpc_method_uses_http_get()
│   ├── control_bridge.ts       # Shared state: browser clients, pending commands, event log, client state
│   └── proxy.ts                # CORS proxy logic, upstream header filtering
├── static/                     # Existing static assets (moved from skylab/static/)
│   ├── skylab.html
│   ├── css/skylab.css
│   └── js/
│       ├── skylab-bridge.js
│       ├── skylab-timeline.js
│       ├── skylab-chat.js
│       ├── skylab-video.js
│       ├── skylab-admin.js
│       ├── skylab-firehose.js
│       ├── skylab-router.js
│       ├── skylab-post.js
│       ├── skylab-profile.js
│       ├── skylab-thread.js
│       ├── skylab-search.js
│       └── skylab-notifications.js
├── Dockerfile                  # Updated for Deno
└── requirements.txt            # REMOVED (no Python deps)
```

## Key Decisions

### 1. Fresh routes vs. raw Deno HTTP server

**Decision: Fresh routes for all endpoints.**

Fresh's file-based routing handles static serving, API endpoints, and page rendering uniformly. The scenario-dashboard already proves this pattern works. The one exception is the WebSocket endpoint — Fresh doesn't have native WebSocket support, so we'll use a raw `Deno.upgradeWebSocket()` call inside a Fresh handler (see §4 below).

### 2. SPA serving strategy

**Decision: Single Fresh route at `routes/index.tsx` that renders the SPA HTML shell.**

The SPA is a single HTML page (`skylab.html`) that loads all JS/CSS. Rather than serving it as a static file (which would require the `/skylab` prefix to match the static dir), we render it as a Fresh page component. This lets us inject the service config as a `<script>` tag for faster boot (no separate `/skylab/api/config` fetch needed on first load).

The JS/CSS files remain in `static/` and are served by Fresh's built-in static file handler at `/skylab/static/js/...` and `/skylab/static/css/...`.

### 3. Service configuration

**Decision: `services/config.ts` module with `Deno.env.get()` — mirrors `SERVICE_URLS` from `server.py`.**

```typescript
// services/config.ts
export const SERVICE_URLS: Record<string, string> = {
  pds: Deno.env.get("PDS_URL") || "http://127.0.0.1:2583",
  appview: Deno.env.get("APPVIEW_URL") || "http://127.0.0.1:3200",
  relay: Deno.env.get("RELAY_URL") || "http://127.0.0.1:2584",
  chat: Deno.env.get("CHAT_URL") || "http://127.0.0.1:2585",
  video: Deno.env.get("VIDEO_URL") || "http://127.0.0.1:2586",
  germ: Deno.env.get("GERM_URL") || "http://127.0.0.1:8082",
  plc: Deno.env.get("PLC_URL") || "http://127.0.0.1:2582",
  ui: Deno.env.get("UI_URL") || "http://127.0.0.1:2590",
};

export const SKYLAB_PORT = parseInt(Deno.env.get("SKYLAB_PORT") || "2591");
```

### 4. WebSocket handling

**Decision: Use `Deno.upgradeWebSocket()` inside a Fresh handler.**

Fresh doesn't have a WebSocket abstraction, but Deno's built-in `Deno.upgradeWebSocket()` works inside a Fresh handler by returning a `Response` with status 101. The handler file `routes/api/ws.ts` will:

1. Call `Deno.upgradeWebSocket(req)` to get `{ response, socket }`
2. Wire up `socket.onopen`, `socket.onmessage`, `socket.onclose`, `socket.onerror`
3. Register the socket with `control_bridge.ts` shared state
4. Return the `response`

This is the same approach used in Deno's WebSocket examples and works with Fresh's handler pattern.

### 5. CORS proxy

**Decision: Fresh route with dynamic path params at `routes/proxy/[service]/[...path].ts`.**

The proxy handler:
1. Looks up `SERVICE_URLS[service]` to get the target base URL
2. Concatenates the remaining path segments
3. Forwards the request using `fetch()` with filtered upstream headers
4. Returns the response with CORS headers (handled by Fresh middleware)

### 6. Control Bridge shared state

**Decision: Singleton module `services/control_bridge.ts` with in-memory state.**

The Python server uses module-level globals (`_browser_clients`, `_pending_commands`, `_event_log`, `_client_state`). We replicate this with a TypeScript module that exports singleton state and functions:

```typescript
// services/control_bridge.ts
interface BrowserClient { socket: WebSocket; id: string }

const browserClients: BrowserClient[] = [];
const pendingCommands: Map<string, { resolve: Function; timer: number }> = new Map();
const eventLog: Event[] = [];
const EVENT_LOG_MAX = 1000;
let clientState: Record<string, unknown> = { auth: null, profile: null, ... };

export function registerClient(ws: WebSocket): string { ... }
export function unregisterClient(id: string): void { ... }
export function dispatchCommand(cmd: Command): Promise<Result> { ... }
export function recordEvent(event: unknown): void { ... }
export function getState(): Record<string, unknown> { ... }
export function updateState(partial: Record<string, unknown>): void { ... }
export function resetState(): void { ... }
export function broadcastToBrowsers(msg: unknown): void { ... }
```

### 7. XRPC execution fallback

**Decision: Direct server-side proxy when no browser is connected.**

The `execute` endpoint tries browser clients first (via WebSocket), then falls back to a direct `fetch()` to the target service. This mirrors the Python `httpx.AsyncClient` fallback exactly.

## Implementation Steps

### Phase 1: Scaffolding (5 files)

1. **`skylab/deno.json`** — Deno config mirroring scenario-dashboard's imports (Fresh 1.7.3, Preact 10.22.0, std@0.224.0). Add `SKYLAB_PORT` env var support.

2. **`skylab/dev.ts`** — Fresh dev entry point, port from `SKYLAB_PORT` env (default 2591).

3. **`skylab/main.ts`** — Fresh production entry point.

4. **`skylab/services/config.ts`** — Service URLs, method routes, appview read methods.

5. **`skylab/services/routing.ts`** — `routeMethod()` and `xrpcMethodUsesHttpGet()` functions.

### Phase 2: Control Bridge core (1 file)

6. **`skylab/services/control_bridge.ts`** — All shared state: browser clients, pending commands, event log, client state. Functions for register/unregister, dispatch, broadcast, record event, state management.

### Phase 3: CORS proxy service (1 file)

7. **`skylab/services/proxy.ts`** — `PROXY_HEADER_ALLOW` set, `proxyUpstreamHeaders()` function, `proxyRequest()` function using `fetch()`.

### Phase 4: API routes (9 files)

8. **`skylab/routes/api/config.ts`** — GET: return SERVICE_URLS + method routes + appview read methods.

9. **`skylab/routes/api/health.ts`** — GET: return status, browser count, event count, service URLs.

10. **`skylab/routes/api/state.ts`** — GET: return client state. POST: update client state.

11. **`skylab/routes/api/events.ts`** — GET: return event log. POST: record event.

12. **`skylab/routes/api/auth.ts`** — POST: set auth tokens, broadcast to browsers.

13. **`skylab/routes/api/reset.ts`** — POST: clear all state, broadcast reset to browsers.

14. **`skylab/routes/api/execute.ts`** — POST: try browser execution, fallback to direct proxy.

15. **`skylab/routes/api/debug/appview-timeline.ts`** — GET: proxy AppView timeline with auth passthrough.

16. **`skylab/routes/api/ws.ts`** — WebSocket upgrade handler, wires into control_bridge.

### Phase 5: CORS proxy route (1 file)

17. **`skylab/routes/proxy/[service]/[...path].ts`** — Dynamic proxy route.

### Phase 6: SPA page route (1 file)

18. **`skylab/routes/index.tsx`** — Renders the SPA HTML shell. Injects service config as inline `<script>` for instant boot. Links to static JS/CSS.

### Phase 7: Static assets & cleanup

19. Move `skylab/static/` to remain as `skylab/static/` (Fresh serves from `staticDir`).

20. Update `skylab/Dockerfile` for Deno (replace Python base image with `denoland/deno`, install deps, expose port 2591).

21. Delete `skylab/requirements.txt` and `skylab/server.py` (after verification).

### Phase 8: Verification

22. Run `deno task dev` and verify:
    - SPA loads at `http://localhost:2591/skylab`
    - All panels render (timeline, chat, video, firehose, admin)
    - Login flow works (createSession → auth state → profile load)
    - CORS proxy works (`/skylab/proxy/pds/xrpc/...`)
    - Control Bridge WebSocket connects
    - `/skylab/api/execute` works (browser + fallback)
    - `/skylab/api/health`, `/skylab/api/state`, `/skylab/api/events` work
    - `/skylab/api/debug/appview-timeline` works with Bearer token

## Port & URL Mapping

| Service | Current (Python) | New (Deno) |
|---------|-------------------|------------|
| SkyLab server | `0.0.0.0:2591` | `0.0.0.0:2591` (same) |
| SPA URL | `/skylab` | `/skylab` (same) |
| Static files | `/skylab/static/` | `/skylab/static/` (same) |
| API base | `/skylab/api/` | `/skylab/api/` (same) |
| WebSocket | `/skylab/api/ws` | `/skylab/api/ws` (same) |
| CORS proxy | `/skylab/proxy/{service}/{path}` | `/skylab/proxy/{service}/{path}` (same) |

All URLs remain identical — the browser-side JS requires zero changes.

## Fresh Route Prefix Handling

Fresh routes are mounted at `/` by default. To match the `/skylab/` prefix, we set `router.basePath` in the Fresh config:

```typescript
// dev.ts / main.ts
await dev(import.meta.url, "fresh.gen.ts", {
  router: {
    basePath: "/skylab",
    trailingSlash: false,
  },
  staticDir: join(dir, "static"),
  server: { port: SKYLAB_PORT },
});
```

This makes all routes automatically prefixed with `/skylab/` — the file `routes/api/health.ts` becomes `/skylab/api/health`, `routes/proxy/[service]/[...path].ts` becomes `/skylab/proxy/{service}/{path}`, etc.

## What Gets Deleted

After verification:
- `skylab/server.py` — replaced by Deno/Fresh
- `skylab/requirements.txt` — no Python deps needed
- `skylab/server.log` — Deno logs to stdout

## What Stays Unchanged

- All files in `skylab/static/` (HTML, CSS, JS) — served as-is by Fresh's static handler
- `skylab/Dockerfile` — updated, not deleted
