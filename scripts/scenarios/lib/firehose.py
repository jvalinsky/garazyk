"""WebSocket firehose subscriber for ATProto scenario scripts.

Connects to com.atproto.sync.subscribeRepos on a Relay and collects
commit events for verification in scenario steps.
"""

from __future__ import annotations

import asyncio
import json
import logging
import struct
from typing import Any, Callable, Optional

logger = logging.getLogger("atproto.scenario")


class FirehoseEvent:
    """A parsed firehose event."""

    def __init__(self, seq: int, type: str, payload: dict | bytes):
        self.seq = seq
        self.type = type
        self.payload = payload

    def __repr__(self) -> str:
        return f"FirehoseEvent(seq={self.seq}, type={self.type!r})"


class FirehoseClient:
    """Async WebSocket client for the ATProto firehose.

    Usage:
        client = FirehoseClient("ws://localhost:2584")
        events = await client.collect(duration_s=5)
        # or
        await client.subscribe(callback, duration_s=10)
    """

    def __init__(self, relay_url: str = "ws://localhost:2584"):
        # Convert http to ws if needed
        self.ws_url = relay_url.replace("http://", "ws://").replace("https://", "wss://")
        self.ws_url = self.ws_url.rstrip("/")
        self.events: list[FirehoseEvent] = []

    async def collect(self, duration_s: float = 5.0, cursor: Optional[int] = None) -> list[FirehoseEvent]:
        """Collect firehose events for a given duration. Returns collected events."""
        self.events = []
        await self.subscribe(lambda e: self.events.append(e), duration_s=duration_s, cursor=cursor)
        return self.events

    async def subscribe(
        self,
        callback: Callable[[FirehoseEvent], None],
        duration_s: float = 10.0,
        cursor: Optional[int] = None,
    ) -> None:
        """Subscribe to the firehose and call callback for each event."""
        try:
            import websockets
        except ImportError:
            raise ImportError(
                "websockets package is required for firehose support. "
                "Install with: pip install websockets"
            )

        url = f"{self.ws_url}/xrpc/com.atproto.sync.subscribeRepos"
        if cursor is not None:
            url += f"?cursor={cursor}"

        logger.info("Connecting to firehose: %s", url)
        try:
            async with websockets.connect(url) as ws:
                deadline = asyncio.get_event_loop().time() + duration_s
                async for message in ws:
                    if asyncio.get_event_loop().time() > deadline:
                        break
                    event = _parse_message(message)
                    if event:
                        callback(event)
        except Exception as exc:
            logger.warning("Firehose connection ended: %s", exc)

    def wait_for_event(
        self,
        predicate: Callable[[FirehoseEvent], bool],
        timeout_s: float = 10.0,
    ) -> Optional[FirehoseEvent]:
        """Synchronous helper: collect events until one matches the predicate."""
        result = asyncio.run(self._wait_for_event_async(predicate, timeout_s))
        return result

    async def _wait_for_event_async(
        self,
        predicate: Callable[[FirehoseEvent], bool],
        timeout_s: float,
    ) -> Optional[FirehoseEvent]:
        """Async: wait for a matching event."""
        matching: list[FirehoseEvent] = []

        def cb(event: FirehoseEvent) -> None:
            if predicate(event):
                matching.append(event)

        await self.subscribe(cb, duration_s=timeout_s)
        return matching[0] if matching else None


def _parse_message(message: bytes) -> Optional[FirehoseEvent]:
    """Parse a firehose WebSocket message.

    Message format: frame header (DAG-CBOR) with seq number and type.
    This is a simplified parser — full implementation would use cbor2.
    """
    try:
        # Try to extract the frame header
        # ATProto firehose messages are DAG-CBOR framed
        # For scenario testing, we do a best-effort parse
        if len(message) < 2:
            return None

        # Attempt JSON parse (some relay implementations may send JSON)
        try:
            data = json.loads(message)
            return FirehoseEvent(
                seq=data.get("seq", 0),
                type=data.get("type", "unknown"),
                payload=data,
            )
        except (json.JSONDecodeError, UnicodeDecodeError):
            pass

        # For CBOR messages, we'll store the raw payload
        # Real parsing would need cbor2 library
        return FirehoseEvent(
            seq=0,
            type="cbor_frame",
            payload=message,
        )
    except Exception as exc:
        logger.debug("Failed to parse firehose message: %s", exc)
        return None
