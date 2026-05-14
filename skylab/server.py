"""SkyLab: Programmable Bluesky Web Client Server.

A standalone FastAPI application that serves a complete Bluesky web client
with dual-audience design: visual feedback for engineers and programmatic
API for the Python test harness.

Three core concerns:
1. Static file serving for the SkyLab SPA
2. Control Bridge API (HTTP + WebSocket) for test harness integration
3. CORS proxy for local development (avoids browser CORS issues)

Usage:
    python -m skylab.server
    # or: uvicorn skylab.server:app --port 2591
"""

# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0

from __future__ import annotations

import asyncio
import json
import os
import time
from pathlib import Path
from typing import Any

import httpx
from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SKYLAB_PORT = int(os.environ.get("SKYLAB_PORT", "2591"))
SKYLAB_HOST = os.environ.get("SKYLAB_HOST", "0.0.0.0")

SERVICE_URLS: dict[str, str] = {
    "pds": os.environ.get("PDS_URL", "http://127.0.0.1:2583"),
    "appview": os.environ.get("APPVIEW_URL", "http://127.0.0.1:3200"),
    "relay": os.environ.get("RELAY_URL", "http://127.0.0.1:2584"),
    "chat": os.environ.get("CHAT_URL", "http://127.0.0.1:2585"),
    "video": os.environ.get("VIDEO_URL", "http://127.0.0.1:2586"),
    "germ": os.environ.get("GERM_URL", "http://127.0.0.1:8082"),
    "plc": os.environ.get("PLC_URL", "http://127.0.0.1:2582"),
    "ui": os.environ.get("UI_URL", "http://127.0.0.1:2590"),
}

# Method-to-service routing (mirrors skylab-bridge.js logic)
METHOD_ROUTES: dict[str, str] = {
    "chat.bsky": "chat",
    "app.bsky.video": "video",
    "com.germnetwork": "germ",
}

# Read methods that should route to AppView
APPVIEW_READ_METHODS = {
    "app.bsky.feed.getTimeline",
    "app.bsky.feed.getAuthorFeed",
    "app.bsky.feed.getPostThread",
    "app.bsky.feed.getLikes",
    "app.bsky.feed.getRepostedBy",
    "app.bsky.feed.getPosts",
    "app.bsky.feed.getActorLikes",
    "app.bsky.feed.getFeed",
    "app.bsky.feed.getFeedGenerator",
    "app.bsky.feed.getFeedGenerators",
    "app.bsky.feed.getSuggestions",
    "app.bsky.actor.getProfile",
    "app.bsky.actor.getProfiles",
    "app.bsky.actor.searchActors",
    "app.bsky.actor.searchActorsTypeahead",
    "app.bsky.graph.getFollows",
    "app.bsky.graph.getFollowers",
    "app.bsky.graph.getBlocks",
    "app.bsky.graph.getMutes",
    "app.bsky.graph.getRelationships",
    "app.bsky.graph.getStarterPack",
    "app.bsky.graph.getActorStarterPacks",
    "app.bsky.graph.getStarterPacks",
    "app.bsky.graph.getList",
    "app.bsky.graph.getLists",
    "app.bsky.graph.getListMutes",
    "app.bsky.notification.listNotifications",
    "app.bsky.notification.getUnreadCount",
    "app.bsky.unspecced.searchActorsSkeleton",
    "app.bsky.unspecced.searchPostsSkeleton",
    "app.bsky.unspecced.searchStarterPacksSkeleton",
}

STATIC_DIR = Path(__file__).parent / "static"

# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

app = FastAPI(
    title="SkyLab",
    description="Programmable Bluesky Web Client with test bridge",
    version="0.1.0",
)

# CORS — wide open for local dev
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Shared state for Control Bridge
# ---------------------------------------------------------------------------

# Connected browser clients (WebSocket)
_browser_clients: list[WebSocket] = []

# Pending commands awaiting responses from browser
_pending_commands: dict[str, asyncio.Future] = {}

# Event log (circular buffer, last 1000 events)
_event_log: list[dict[str, Any]] = []
_EVENT_LOG_MAX = 1000

# Client state snapshot
_client_state: dict[str, Any] = {
    "auth": None,
    "profile": None,
    "timeline": [],
    "chats": [],
    "firehose": {"connected": False, "seq": 0},
}


def _route_method(method: str) -> str:
    """Determine which service handles a given XRPC method."""
    for prefix, service in METHOD_ROUTES.items():
        if method.startswith(prefix):
            return service
    if method in APPVIEW_READ_METHODS:
        return "appview"
    return "pds"


def _xrpc_method_uses_http_get(method: str) -> bool:
    """True when the XRPC method is a lexicon query (HTTP GET + query params).

    Match on the final NSID segment: app.bsky.feed.getTimeline -> getTimeline.
    Full-NSID prefix checks are wrong because NSIDs start with the domain.
    """
    if not method:
        return False
    seg = method.rsplit(".", 1)[-1].lower()
    return seg.startswith(("get", "list", "search", "describe", "resolve"))


# ---------------------------------------------------------------------------
# Static file serving
# ---------------------------------------------------------------------------

app.mount("/skylab/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


@app.get("/skylab", response_class=HTMLResponse)
@app.get("/skylab/", response_class=HTMLResponse)
async def skylab_index():
    """Serve the SkyLab SPA shell."""
    html_path = STATIC_DIR / "skylab.html"
    if html_path.exists():
        return HTMLResponse(content=html_path.read_text())
    return HTMLResponse(content="<h1>SkyLab SPA not found</h1>", status_code=404)


# ---------------------------------------------------------------------------
# Service configuration endpoint
# ---------------------------------------------------------------------------

@app.get("/skylab/api/config")
async def get_config():
    """Return service URLs and configuration to the browser client."""
    return {
        "services": SERVICE_URLS,
        "methodRoutes": METHOD_ROUTES,
        "appviewReadMethods": list(APPVIEW_READ_METHODS),
    }


@app.get("/skylab/api/debug/appview-timeline")
async def debug_appview_timeline(request: Request, limit: int = 25) -> JSONResponse:
    """GET AppView home timeline as JSON (for curl / checks without the browser).

    Example:
        TOKEN=$(curl -s -X POST .../createSession ... | jq -r .accessJwt)
        curl -s -H "Authorization: Bearer $TOKEN" \\
          "http://127.0.0.1:2591/skylab/api/debug/appview-timeline?limit=10"
    """
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return JSONResponse(
            {
                "ok": False,
                "error": "expected Authorization: Bearer <accessJwt from PDS createSession>",
            },
            status_code=401,
        )
    appview = SERVICE_URLS["appview"]
    url = f"{appview}/xrpc/app.bsky.feed.getTimeline"
    lim = max(1, min(limit, 100))
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get(
                url,
                params={"limit": lim},
                headers={"Authorization": auth},
            )
    except httpx.RequestError as exc:
        return JSONResponse(
            {"ok": False, "error": "proxy_error", "detail": str(exc)},
            status_code=502,
        )
    content_type = resp.headers.get("content-type", "")
    payload: Any
    if content_type.startswith("application/json"):
        try:
            payload = resp.json()
        except json.JSONDecodeError:
            payload = {"raw": resp.text}
    else:
        payload = {"raw": resp.text}
    feed_len = 0
    if isinstance(payload, dict) and isinstance(payload.get("feed"), list):
        feed_len = len(payload["feed"])
    out = {
        "ok": resp.is_success,
        "upstreamStatus": resp.status_code,
        "appview": appview,
        "feedItemCount": feed_len,
        "xrpc": payload,
    }
    return JSONResponse(out, status_code=resp.status_code)


# ---------------------------------------------------------------------------
# Control Bridge: HTTP API
# ---------------------------------------------------------------------------

@app.post("/skylab/api/execute")
async def execute_xrpc(request: Request):
    """Execute an XRPC call via the connected browser client.

    The server forwards the command to the browser via WebSocket,
    waits for the result, and returns it. This tests the actual
    browser code path (CORS, DPoP, cookie handling, etc.).

    If no browser is connected, falls back to direct server-side
    proxy (useful for headless testing).
    """
    body = await request.json()
    method = body.get("method", "")
    params = body.get("params", {})
    xrpc_body = body.get("body")
    service = body.get("service") or _route_method(method)
    cmd_id = f"cmd-{time.monotonic_ns()}"

    # Try browser client first
    if _browser_clients:
        cmd = {
            "type": "execute",
            "id": cmd_id,
            "method": method,
            "params": params,
            "body": xrpc_body,
            "service": service,
        }
        future = asyncio.get_event_loop().create_future()
        _pending_commands[cmd_id] = future

        # Send to first connected browser
        ws = _browser_clients[0]
        try:
            await ws.send_json(cmd)
            # Wait for response with timeout
            result = await asyncio.wait_for(future, timeout=30.0)
            return JSONResponse(content=result)
        except asyncio.TimeoutError:
            _pending_commands.pop(cmd_id, None)
            return JSONResponse(
                content={"error": "timeout", "detail": "Browser did not respond within 30s"},
                status_code=504,
            )
        except Exception as exc:
            _pending_commands.pop(cmd_id, None)
            return JSONResponse(
                content={"error": "browser_error", "detail": str(exc)},
                status_code=500,
            )

    # Fallback: direct server-side proxy
    target_url = SERVICE_URLS.get(service, SERVICE_URLS["pds"])
    is_query = _xrpc_method_uses_http_get(method)
    url = f"{target_url}/xrpc/{method}"

    headers = {}
    auth_header = body.get("authorization")
    if auth_header:
        headers["Authorization"] = auth_header

    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            if is_query and not xrpc_body:
                resp = await client.get(url, params=params, headers=headers)
            else:
                resp = await client.post(url, json=xrpc_body or params, headers=headers)
            return JSONResponse(
                content=resp.json() if resp.headers.get("content-type", "").startswith("application/json") else {"raw": resp.text},
                status_code=resp.status_code,
            )
        except httpx.RequestError as exc:
            return JSONResponse(
                content={"error": "proxy_error", "detail": str(exc)},
                status_code=502,
            )


@app.get("/skylab/api/state")
async def get_state():
    """Return current client state snapshot."""
    return _client_state


@app.post("/skylab/api/state")
async def update_state(request: Request):
    """Update client state (called by browser)."""
    body = await request.json()
    for key, value in body.items():
        _client_state[key] = value
    return {"ok": True}


@app.get("/skylab/api/events")
async def get_events():
    """Return event log since last check."""
    after = int(os.environ.get("SKYLAB_EVENT_AFTER", "0"))
    events = [e for e in _event_log if e.get("seq", 0) > after]
    return {"events": events, "total": len(_event_log)}


@app.post("/skylab/api/events")
async def record_event(request: Request):
    """Record an event from the browser client."""
    body = await request.json()
    event = {
        "seq": len(_event_log) + 1,
        "timestamp": time.time(),
        **body,
    }
    _event_log.append(event)
    if len(_event_log) > _EVENT_LOG_MAX:
        _event_log.pop(0)
    return {"ok": True, "seq": event["seq"]}


@app.post("/skylab/api/auth")
async def set_auth(request: Request):
    """Set auth tokens (for pre-authenticated test scenarios)."""
    body = await request.json()
    _client_state["auth"] = body
    # Forward to connected browsers
    for ws in _browser_clients:
        try:
            await ws.send_json({"type": "auth_update", "auth": body})
        except Exception:
            pass
    return {"ok": True}


@app.post("/skylab/api/reset")
async def reset_state():
    """Clear all client state."""
    _client_state.update({
        "auth": None,
        "profile": None,
        "timeline": [],
        "chats": [],
        "firehose": {"connected": False, "seq": 0},
    })
    _event_log.clear()
    # Forward to connected browsers
    for ws in _browser_clients:
        try:
            await ws.send_json({"type": "reset"})
        except Exception:
            pass
    return {"ok": True}


# ---------------------------------------------------------------------------
# Control Bridge: WebSocket
# ---------------------------------------------------------------------------

@app.websocket("/skylab/api/ws")
async def websocket_bridge(websocket: WebSocket):
    """Bidirectional command channel between Python harness and browser.

    Protocol:
    - Python → Browser: {"type": "execute", "id": "...", "method": "...", ...}
    - Browser → Python: {"type": "result", "id": "...", "status": "success", "data": ...}
    - Browser → Python: {"type": "event", "event": "...", ...}
    - Python → Browser: {"type": "auth_update", "auth": {...}}
    - Python → Browser: {"type": "reset"}
    """
    await websocket.accept()
    _browser_clients.append(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            try:
                msg = json.loads(data)
            except json.JSONDecodeError:
                continue

            msg_type = msg.get("type")

            if msg_type == "result":
                # Response to a pending command
                cmd_id = msg.get("id")
                if cmd_id in _pending_commands:
                    _pending_commands[cmd_id].set_result(msg)
                    del _pending_commands[cmd_id]

            elif msg_type == "event":
                # Browser event (post created, message received, etc.)
                event = {
                    "seq": len(_event_log) + 1,
                    "timestamp": time.time(),
                    **msg.get("event", {}),
                }
                _event_log.append(event)
                if len(_event_log) > _EVENT_LOG_MAX:
                    _event_log.pop(0)

            elif msg_type == "state_update":
                # Browser pushing state changes
                for key, value in msg.get("state", {}).items():
                    _client_state[key] = value

    except WebSocketDisconnect:
        pass
    finally:
        if websocket in _browser_clients:
            _browser_clients.remove(websocket)
        # Cancel any pending commands for this client
        for cmd_id, future in list(_pending_commands.items()):
            if not future.done():
                future.cancel()
            del _pending_commands[cmd_id]


# ---------------------------------------------------------------------------
# CORS Proxy
# ---------------------------------------------------------------------------

@app.api_route("/skylab/proxy/{service}/{path:path}", methods=["GET", "POST", "PUT", "DELETE"])
async def proxy_to_service(service: str, path: str, request: Request):
    """Proxy XRPC calls to the correct service, adding CORS headers.

    This avoids browser CORS issues during local development.
    The browser can call /skylab/proxy/pds/xrpc/com.atproto.server.getSession
    instead of http://localhost:2583/xrpc/... directly.
    """
    target_url = SERVICE_URLS.get(service)
    if not target_url:
        return JSONResponse(
            content={"error": "unknown_service", "detail": f"Service '{service}' not configured"},
            status_code=400,
        )

    target = f"{target_url}/{path}"
    if request.url.query:
        target += f"?{request.url.query}"

    # Forward headers (except host)
    headers = dict(request.headers)
    headers.pop("host", None)

    body = await request.body()

    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            resp = await client.request(
                method=request.method,
                url=target,
                headers=headers,
                content=body if body else None,
            )
            # Return with CORS headers (already handled by middleware)
            response = JSONResponse(
                content=resp.json() if resp.headers.get("content-type", "").startswith("application/json") else {"raw": resp.text},
                status_code=resp.status_code,
            )
            return response
        except httpx.RequestError as exc:
            return JSONResponse(
                content={"error": "proxy_error", "detail": str(exc)},
                status_code=502,
            )


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------

@app.get("/skylab/api/health")
async def health():
    return {
        "status": "ok",
        "browsers_connected": len(_browser_clients),
        "events_logged": len(_event_log),
        "services": {k: v for k, v in SERVICE_URLS.items()},
    }


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=SKYLAB_HOST, port=SKYLAB_PORT)
