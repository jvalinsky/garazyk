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
    """A parsed firehose event collected from subscribeRepos.

    seq is zero when the frame could not be decoded far enough to recover a
    sequence number. payload is either the decoded event body or the original
    bytes for tests that only need to assert that traffic arrived.
    """

    def __init__(self, seq: int, type: str, payload: dict | bytes):
        self.seq = seq
        self.type = type
        self.payload = payload

    def __repr__(self) -> str:
        return f"FirehoseEvent(seq={self.seq}, type={self.type!r})"


class FirehoseClient:
    """Async WebSocket client for the ATProto relay firehose.

    The client is deliberately lightweight: it connects to
    com.atproto.sync.subscribeRepos, parses enough of each frame for scenario
    assertions, and leaves CAR/block interpretation to tests that need it.

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
        """Collect firehose events for a bounded duration."""
        self.events = []
        await self.subscribe(lambda e: self.events.append(e), duration_s=duration_s, cursor=cursor)
        return self.events

    async def subscribe(
        self,
        callback: Optional[Callable[[FirehoseEvent], None]] = None,
        duration_s: float = 10.0,
        cursor: Optional[int] = None,
        max_errors: int = 3,
    ) -> None:
        """Subscribe to the firehose and invoke callback for each parsed event.

        Connection setup is retried a few times because local demo stacks can
        take a moment to bind the WebSocket route after the HTTP health endpoint
        starts responding.
        """
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
        error_count = 0
        while error_count < max_errors:
            try:
                async with websockets.connect(url, open_timeout=5, ping_timeout=5) as ws:
                    logger.info("Firehose connected")
                    error_count = 0 # Reset on success
                    firehose_connected = True
                    deadline = asyncio.get_event_loop().time() + duration_s
                    async for message in ws:
                        logger.debug("Received firehose message: %d bytes", len(message))
                        if asyncio.get_event_loop().time() > deadline:
                            logger.info("Firehose collection duration reached")
                            return # Normal exit
                        event = _parse_message(message)
                        if event and callback:
                            callback(event)
                    return # Socket closed normally
            except Exception as exc:
                error_count += 1
                logger.warning("Firehose connection attempt %d failed: %s", error_count, exc)
                if error_count >= max_errors:
                    logger.error("Max firehose connection attempts reached")
                    raise
                await asyncio.sleep(1)


    def wait_for_event(
        self,
        predicate: Callable[[FirehoseEvent], bool],
        timeout_s: float = 10.0,
    ) -> Optional[FirehoseEvent]:
        """Synchronously collect events until one satisfies predicate."""
        result = asyncio.run(self._wait_for_event_async(predicate, timeout_s))
        return result

    async def _wait_for_event_async(
        self,
        predicate: Callable[[FirehoseEvent], bool],
        timeout_s: float,
    ) -> Optional[FirehoseEvent]:
        """Collect for timeout_s seconds and return the first matching event."""
        matching: list[FirehoseEvent] = []

        def cb(event: FirehoseEvent) -> None:
            if predicate(event):
                matching.append(event)

        await self.subscribe(cb, duration_s=timeout_s)
        return matching[0] if matching else None


def _parse_message(message: bytes) -> Optional[FirehoseEvent]:
    """Parse a firehose WebSocket message.

    Message format: frame header (DAG-CBOR) with op and type, followed by the
    message body (DAG-CBOR). Some local tests and compatibility shims send JSON,
    so JSON is attempted first before falling back to CBOR framing.
    """
    try:
        if len(message) < 2:
            return None

        # Attempt JSON parse first (for compatibility)
        try:
            data = json.loads(message)
            return FirehoseEvent(
                seq=data.get("seq", 0),
                type=data.get("type", "unknown"),
                payload=data,
            )
        except (json.JSONDecodeError, UnicodeDecodeError):
            pass

        # Use cbor2 for ATProto DAG-CBOR framing
        try:
            import cbor2
            from io import BytesIO

            # ATProto DAG-CBOR uses tag 42 for CIDs.
            # We want to ignore tags for the purpose of finding 'seq'.
            def tag_decoder(decoder, tag):
                return decoder.decode()

            decoder = cbor2.decoder.CBORDecoder(BytesIO(message), tag_hook=tag_decoder)

            header = decoder.decode()
            # body might be missing in some frames (info/error)
            try:
                body = decoder.decode()
            except EOFError:
                body = {}

            if isinstance(header, dict) and header.get("op") == 1:
                t = header.get("t")
                seq = 0
                if isinstance(body, dict):
                    seq = body.get("seq", 0)
                return FirehoseEvent(seq=seq, type=t or "commit", payload=body)

            return FirehoseEvent(seq=0, type="cbor_frame", payload=message)
        except ImportError:
            # Fallback for when cbor2 is missing
            return FirehoseEvent(seq=0, type="cbor_frame", payload=message)
        except Exception as exc:
            logger.debug("CBOR parse failed: %s", exc)
            return FirehoseEvent(seq=0, type="cbor_frame", payload=message)

    except Exception as exc:
        logger.debug("Failed to parse firehose message: %s", exc)
        return None
