"""SkyLab Python Test Driver — Drive the SkyLab web client from scenario scripts.

Provides both WebSocket+HTTP bridge (primary) and optional Playwright
integration for visual regression and accessibility testing.

Usage:
    driver = SkyLabDriver()
    await driver.connect()
    result = await driver.execute('app.bsky.feed.getTimeline', {'limit': 25})
    state = await driver.get_state()
    await driver.close()
"""

# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0

from __future__ import annotations

import asyncio
import json
import time
from typing import Any

try:
    import aiohttp
except ImportError:
    aiohttp = None

try:
    import websockets
except ImportError:
    websockets = None

from .config import SERVICE_URLS


SKYLAB_DEFAULT_URL = "http://127.0.0.1:2591"


class SkyLabDriver:
    """Drive the SkyLab web client from Python test harness.

    Communicates with the SkyLab server via HTTP and WebSocket.
    The server forwards XRPC commands to the connected browser,
    which executes them with full browser context (CORS, DPoP, cookies).
    """

    def __init__(self, base_url: str | None = None):
        self.base_url = (base_url or
                         SERVICE_URLS.get("skylab", SKYLAB_DEFAULT_URL))
        self._ws = None
        self._session = None
        self._cmd_counter = 0
        self._pending: dict[str, asyncio.Future] = {}
        self._ws_task: asyncio.Task | None = None
        self._events: list[dict[str, Any]] = []

    # ------------------------------------------------------------------
    # Connection lifecycle
    # ------------------------------------------------------------------

    async def connect(self) -> None:
        """Connect to the SkyLab server (HTTP session + WebSocket)."""
        if aiohttp is None:
            raise ImportError("aiohttp is required: pip install aiohttp")

        self._session = aiohttp.ClientSession()

        # Connect WebSocket for bidirectional communication
        ws_url = self.base_url.replace("http", "ws") + "/skylab/api/ws"
        try:
            self._ws = await self._session.ws_connect(ws_url)
            self._ws_task = asyncio.create_task(self._ws_listener())
        except Exception:
            # WebSocket is optional; HTTP-only mode still works
            self._ws = None

    async def close(self) -> None:
        """Close the connection."""
        if self._ws_task:
            self._ws_task.cancel()
            self._ws_task = None
        if self._ws:
            await self._ws.close()
            self._ws = None
        if self._session:
            await self._session.close()
            self._session = None

    # ------------------------------------------------------------------
    # XRPC execution (via Control Bridge)
    # ------------------------------------------------------------------

    async def execute(
        self,
        method: str,
        params: dict[str, Any] | None = None,
        body: dict[str, Any] | None = None,
        service: str | None = None,
        timeout: float = 30.0,
    ) -> dict[str, Any]:
        """Execute an XRPC call through the browser client.

        If a browser is connected, the command is forwarded via WebSocket
        and executed in the browser's XrpcBridge (testing the real code path).
        If no browser is connected, the server falls back to direct proxy.
        """
        if self._ws and not self._ws.closed:
            return await self._execute_via_ws(method, params, body, service, timeout)

        return await self._execute_via_http(method, params, body, service, timeout)

    async def _execute_via_ws(
        self,
        method: str,
        params: dict[str, Any] | None,
        body: dict[str, Any] | None,
        service: str | None,
        timeout: float,
    ) -> dict[str, Any]:
        """Send XRPC command via WebSocket and wait for result."""
        self._cmd_counter += 1
        cmd_id = f"py-{self._cmd_counter}"

        cmd = {
            "type": "execute",
            "id": cmd_id,
            "method": method,
            "params": params,
            "body": body,
            "service": service,
        }

        future = asyncio.get_event_loop().create_future()
        self._pending[cmd_id] = future

        await self._ws.send_json(cmd)

        try:
            result = await asyncio.wait_for(future, timeout=timeout)
            return result
        except asyncio.TimeoutError:
            self._pending.pop(cmd_id, None)
            return {"error": "timeout", "detail": f"No response within {timeout}s"}
        except Exception as exc:
            self._pending.pop(cmd_id, None)
            return {"error": "ws_error", "detail": str(exc)}

    async def _execute_via_http(
        self,
        method: str,
        params: dict[str, Any] | None,
        body: dict[str, Any] | None,
        service: str | None,
        timeout: float,
    ) -> dict[str, Any]:
        """Send XRPC command via HTTP POST (server-side proxy fallback)."""
        if not self._session:
            raise RuntimeError("Not connected. Call connect() first.")

        payload = {
            "method": method,
            "params": params,
            "body": body,
            "service": service,
        }

        async with self._session.post(
            f"{self.base_url}/skylab/api/execute",
            json=payload,
            timeout=aiohttp.ClientTimeout(total=timeout),
        ) as resp:
            return await resp.json()

    # ------------------------------------------------------------------
    # State and events
    # ------------------------------------------------------------------

    async def get_state(self) -> dict[str, Any]:
        """Get current client state snapshot."""
        if not self._session:
            raise RuntimeError("Not connected. Call connect() first.")

        async with self._session.get(f"{self.base_url}/skylab/api/state") as resp:
            return await resp.json()

    async def get_events(self) -> list[dict[str, Any]]:
        """Get event log from the server."""
        if not self._session:
            raise RuntimeError("Not connected. Call connect() first.")

        async with self._session.get(f"{self.base_url}/skylab/api/events") as resp:
            data = await resp.json()
            return data.get("events", [])

    async def set_auth(self, auth: dict[str, Any]) -> dict[str, Any]:
        """Set auth tokens on the browser client (for pre-authenticated scenarios)."""
        if not self._session:
            raise RuntimeError("Not connected. Call connect() first.")

        async with self._session.post(
            f"{self.base_url}/skylab/api/auth", json=auth,
        ) as resp:
            return await resp.json()

    async def reset(self) -> dict[str, Any]:
        """Clear all client state."""
        if not self._session:
            raise RuntimeError("Not connected. Call connect() first.")

        async with self._session.post(
            f"{self.base_url}/skylab/api/reset",
        ) as resp:
            return await resp.json()

    async def health(self) -> dict[str, Any]:
        """Check SkyLab server health."""
        if not self._session:
            raise RuntimeError("Not connected. Call connect() first.")

        async with self._session.get(
            f"{self.base_url}/skylab/api/health",
        ) as resp:
            return await resp.json()

    # ------------------------------------------------------------------
    # Wait for events
    # ------------------------------------------------------------------

    async def wait_for_event(
        self,
        event_type: str,
        timeout: float = 10.0,
    ) -> dict[str, Any] | None:
        """Wait for a specific event type from the browser client.

        Polls the event log until an event of the given type is found
        or the timeout expires.
        """
        start = time.monotonic()
        while time.monotonic() - start < timeout:
            events = await self.get_events()
            for event in events:
                if event.get("type") == event_type:
                    return event
            await asyncio.sleep(0.5)
        return None

    # ------------------------------------------------------------------
    # WebSocket listener
    # ------------------------------------------------------------------

    async def _ws_listener(self) -> None:
        """Background task to receive WebSocket messages."""
        if not self._ws:
            return

        try:
            async for msg in self._ws:
                if msg.type == aiohttp.WSMsgType.TEXT:
                    try:
                        data = json.loads(msg.data)
                    except json.JSONDecodeError:
                        continue

                    msg_type = data.get("type")

                    if msg_type == "result":
                        cmd_id = data.get("id")
                        if cmd_id in self._pending:
                            self._pending[cmd_id].set_result(data)
                            del self._pending[cmd_id]

                    elif msg_type == "event":
                        self._events.append(data.get("event", {}))

                elif msg.type in (aiohttp.WSMsgType.ERROR,
                                  aiohttp.WSMsgType.CLOSED):
                    break
        except asyncio.CancelledError:
            pass
        except Exception:
            pass

    # ------------------------------------------------------------------
    # Sync convenience methods
    # ------------------------------------------------------------------

    def execute_sync(self, method: str, **kwargs) -> dict[str, Any]:
        """Synchronous wrapper for execute()."""
        return asyncio.run(self.execute(method, **kwargs))

    def get_state_sync(self) -> dict[str, Any]:
        """Synchronous wrapper for get_state()."""
        return asyncio.run(self.get_state())


# ======================================================================
# Optional Playwright integration
# ======================================================================

class SkyLabPlaywright:
    """Optional Playwright driver for visual regression and accessibility.

    Requires: pip install playwright && playwright install

    Usage:
        pw = SkyLabPlaywright()
        await pw.launch()
        await pw.screenshot_panel('timeline', 'timeline.png')
        await pw.check_accessibility('timeline')
        await pw.close()
    """

    def __init__(self, base_url: str | None = None):
        self.base_url = base_url or SKYLAB_DEFAULT_URL
        self._browser = None
        self._page = None

    async def launch(self, headless: bool = True) -> None:
        """Launch the browser and navigate to SkyLab."""
        try:
            from playwright.async_api import async_playwright
        except ImportError:
            raise ImportError("Playwright is required: pip install playwright && playwright install")

        pw = await async_playwright().start()
        self._browser = await pw.chromium.launch(headless=headless)
        self._page = await self._browser.new_page()
        await self._page.goto(f"{self.base_url}/skylab")

    async def screenshot_panel(self, panel_name: str, path: str) -> None:
        """Capture a screenshot of a specific panel."""
        if not self._page:
            raise RuntimeError("Browser not launched. Call launch() first.")

        # Navigate to the panel
        await self._page.click(f'[data-panel="{panel_name}"]')
        await self._page.wait_for_timeout(500)  # Let panel render

        panel = await self._page.query_selector(f"#panel-{panel_name}")
        if panel:
            await panel.screenshot(path=path)
        else:
            await self._page.screenshot(path=path)

    async def check_accessibility(self, panel_name: str) -> list[dict[str, Any]]:
        """Run accessibility audit on a panel."""
        if not self._page:
            raise RuntimeError("Browser not launched. Call launch() first.")

        # Navigate to the panel
        await self._page.click(f'[data-panel="{panel_name}"]')
        await self._page.wait_for_timeout(500)

        # Run axe-core or built-in accessibility checks
        violations = await self._page.evaluate("""
            () => {
                // Basic accessibility checks
                const issues = [];
                const panel = document.getElementById('panel-' + arguments[0]);
                if (!panel) return issues;

                // Check for images without alt
                panel.querySelectorAll('img:not([alt])').forEach(el => {
                    issues.push({ type: 'missing_alt', selector: el.outerHTML.substring(0, 80) });
                });

                // Check for inputs without labels
                panel.querySelectorAll('input:not([aria-label]):not([aria-labelledby])').forEach(el => {
                    const id = el.id;
                    const hasLabel = id && document.querySelector(`label[for="${id}"]`);
                    if (!hasLabel) {
                        issues.push({ type: 'missing_label', selector: el.outerHTML.substring(0, 80) });
                    }
                });

                // Check for buttons without text
                panel.querySelectorAll('button').forEach(el => {
                    if (!el.textContent.trim() && !el.getAttribute('aria-label')) {
                        issues.push({ type: 'empty_button', selector: el.outerHTML.substring(0, 80) });
                    }
                });

                return issues;
            }
        """, panel_name)

        return violations

    async def close(self) -> None:
        """Close the browser."""
        if self._browser:
            await self._browser.close()
            self._browser = None
            self._page = None
