"""Scenario 33: "The Tortoise Consumer" — Firehose Backpressure

Verify firehose backpressure/slow consumer disconnection.
Connect to com.atproto.sync.subscribeRepos, consume very slowly (5s delay),
and generate enough traffic to fill the PDS's 10MB buffer.
Assert the PDS closes the connection with code 1009 (Message Too Big / Buffer Full).

Services: PDS
"""

from __future__ import annotations

import asyncio
import logging
import random
import string
import sys
import threading
import time
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, ScenarioResult, timed_call

logger = logging.getLogger("atproto.scenario")


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _generate_large_text(kb: int = 100) -> str:
    """Generate a large string of random characters."""
    return ''.join(random.choices(string.ascii_letters + string.digits + " ", k=kb * 1024))


async def _slow_consumer(ws_url: str, stop_event: threading.Event, result_store: dict):
    """A firehose consumer that waits 5 seconds between receiving frames."""
    try:
        import websockets
    except ImportError:
        result_store["error"] = "websockets package not installed"
        return

    try:
        async with websockets.connect(ws_url, open_timeout=5) as ws:
            result_store["connected"] = True
            logger.info("Slow consumer connected to %s", ws_url)
            while not stop_event.is_set():
                try:
                    # Receive one message
                    _message = await ws.recv()
                    result_store["received_count"] = result_store.get("received_count", 0) + 1
                    
                    # Wait 5 seconds as required by the scenario
                    await asyncio.sleep(5)
                except websockets.exceptions.ConnectionClosed as exc:
                    result_store["close_code"] = exc.code
                    result_store["close_reason"] = exc.reason
                    logger.info("Connection closed by server: code=%d, reason=%s", exc.code, exc.reason)
                    break
                except Exception as exc:
                    result_store["error"] = str(exc)
                    break
    except Exception as exc:
        result_store["error"] = str(exc)
        logger.error("Slow consumer connection error: %s", exc)


def run() -> ScenarioResult:
    result = ScenarioResult("Firehose Backpressure (Tortoise Consumer)")
    result.start()

    client = XrpcClient(PDS1)
    timed_call(result, "Server health check", lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    volt = get_character("volt")
    session = timed_call(
        result, f"Create account: {volt.handle}",
        lambda: client.accounts.create_account(volt.handle, volt.email, volt.password),
    )
    if not session:
        result.finish()
        return result
    volt.did = session["did"]
    volt.access_jwt = session["accessJwt"]

    # Use PDS firehose
    ws_url = PDS1.replace("http://", "ws://").replace("https://", "wss://") + "/xrpc/com.atproto.sync.subscribeRepos"
    
    stop_event = threading.Event()
    result_store = {"received_count": 0, "connected": False}
    
    def start_consumer():
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            loop.run_until_complete(_slow_consumer(ws_url, stop_event, result_store))
        finally:
            loop.close()

    consumer_thread = threading.Thread(target=start_consumer, daemon=True)
    consumer_thread.start()
    
    # Wait for connection
    timeout = 10
    start_time = time.time()
    while not result_store.get("connected") and not result_store.get("error") and time.time() - start_time < timeout:
        time.sleep(0.5)
    
    if not result_store.get("connected"):
        result.step_failed("Connect to firehose", result_store.get("error", "Timeout"))
        result.finish()
        return result
    
    result.step_passed("Connect to firehose")

    # Generate 100 records with large random text to fill the 10MB buffer
    # Each record approx 100KB -> 100 * 100KB = 10MB
    POST_COUNT = 100
    LARGE_TEXT_SIZE_KB = 105 
    
    print(f"Generating {POST_COUNT} large records to fill buffer...")
    for i in range(POST_COUNT):
        if result_store.get("close_code"):
            print(f"Disconnection detected at record {i}")
            break
            
        text = _generate_large_text(LARGE_TEXT_SIZE_KB)
        try:
            # Using a custom collection to avoid lexicon validation overhead/limits if any
            client.raw.xrpc_post(
                "com.atproto.repo.createRecord",
                {
                    "repo": volt.did,
                    "collection": "com.example.test",
                    "record": {"$type": "com.example.test", "data": text, "createdAt": _now()}
                },
                token=volt.access_jwt
            )
        except Exception as exc:
            # PDS might start rejecting if it's overloaded
            logger.debug("Record creation %d failed (expected if PDS is under pressure): %s", i, exc)
            pass
        
        if i > 0 and i % 20 == 0:
            print(f"  Sent {i} records...")
            # Brief sleep to allow PDS to process and buffer
            time.sleep(0.1)

    # Wait for disconnection
    print("Waiting for PDS to drop slow consumer...")
    timeout = 60
    start_time = time.time()
    while not result_store.get("close_code") and time.time() - start_time < timeout:
        time.sleep(1)

    stop_event.set()
    consumer_thread.join(timeout=5)

    close_code = result_store.get("close_code")
    if close_code == 1009:
        result.step_passed("Firehose disconnected with 1009", 
                           f"Received {result_store['received_count']} frames before drop")
    elif close_code:
        result.step_failed("Firehose disconnected", 
                           f"Expected 1009, got {close_code} (reason: {result_store.get('close_reason', 'N/A')})")
    else:
        result.step_failed("Firehose disconnected", 
                           "Connection still open or timed out without 1009")

    result.finish()
    return result


if __name__ == "__main__":
    res = run()
    res.print_summary()
    sys.exit(res.exit_code)
