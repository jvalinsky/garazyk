"""Scenario 33: "The Tortoise Consumer" — Firehose Backpressure

Verify firehose backpressure / slow consumer disconnection.
Connect to com.atproto.sync.subscribeRepos via a raw TCP socket, read the
HTTP upgrade response, then stop reading. Generate enough traffic to fill
the PDS's TCP send buffer. The PDS will eventually detect the slow consumer
and close the connection (either via backpressure check or heartbeat timeout).

Services: PDS
"""

from __future__ import annotations

import logging
import socket
import sys
import time
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, ScenarioResult, timed_call

logger = logging.getLogger("atproto.scenario")


def _connect_raw_ws(host: str, port: int, path: str) -> socket.socket:
    """Open a raw TCP socket, perform HTTP upgrade to WebSocket, and return
    the connected socket. Does NOT read any WebSocket frames after upgrade."""
    import hashlib
    import base64

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(10)
    sock.connect((host, port))

    # Generate WebSocket upgrade request
    key = base64.b64encode(bytes([i for i in range(16)])).decode()
    request = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        f"Upgrade: websocket\r\n"
        f"Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        f"Sec-WebSocket-Version: 13\r\n"
        f"\r\n"
    )
    sock.sendall(request.encode())

    # Read HTTP upgrade response
    response = b""
    while b"\r\n\r\n" not in response:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("Connection closed during upgrade")
        response += chunk

    if b"101" not in response.split(b"\r\n")[0]:
        raise ConnectionError(f"Upgrade failed: {response.decode(errors='replace')}")

    return sock


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

    # Parse PDS URL to get host and port
    from urllib.parse import urlparse
    parsed = urlparse(PDS1)
    host = parsed.hostname or "localhost"
    port = parsed.port or 80

    # Connect to firehose via raw TCP socket
    ws_path = "/xrpc/com.atproto.sync.subscribeRepos"
    try:
        sock = _connect_raw_ws(host, port, ws_path)
        result.step_passed("Connect to firehose")
    except Exception as exc:
        result.step_failed("Connect to firehose", str(exc))
        result.finish()
        return result

    # Read a few initial frames to confirm the connection works
    sock.settimeout(5)
    initial_count = 0
    try:
        for _ in range(5):
            data = sock.recv(65536)
            if data:
                initial_count += 1
            else:
                break
    except socket.timeout:
        pass  # No more initial data

    # Now set a very small receive buffer on the socket to limit the TCP
    # receive window. This causes the PDS's TCP send buffer to fill up,
    # which makes the PDS's internal outbound queue grow, eventually
    # triggering the ConsumerTooSlow backpressure check.
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)

    # Stop reading from the socket entirely. The TCP receive window will
    # close, the PDS's writes will block, and the PDS will detect the
    # slow consumer.
    sock.settimeout(120)  # Long timeout to wait for server-initiated close

    # Generate records to fill the PDS's outbound queue
    POST_COUNT = 600
    print(f"Generating {POST_COUNT} posts to fill server outbound queue...")
    for i in range(POST_COUNT):
        try:
            client.records.create_record(
                volt.did,
                "app.bsky.feed.post",
                {
                    "$type": "app.bsky.feed.post",
                    "text": f"backpressure test {i}",
                    "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                },
                volt.access_jwt,
            )
        except Exception as exc:
            logger.debug("Record creation %d failed: %s", i, exc)
            pass
        
        if i > 0 and i % 100 == 0:
            print(f"  Sent {i} records...")

    # Wait for the server to close the connection
    print("Waiting for PDS to drop slow consumer...")
    close_detected = False
    close_code = None
    start_time = time.time()
    timeout = 90

    while time.time() - start_time < timeout:
        # Try to read from the socket — if the server closed it, we'll get
        # empty data or an error
        try:
            data = sock.recv(65536)
            if not data:
                # Connection closed by server
                close_detected = True
                break
        except (ConnectionResetError, BrokenPipeError, OSError):
            close_detected = True
            break
        except socket.timeout:
            continue
        except Exception:
            close_detected = True
            break

        time.sleep(0.5)

    try:
        sock.close()
    except Exception:
        pass

    if close_detected:
        # The PDS closed the connection — this is the expected behavior for
        # slow consumers. We can't easily parse the WebSocket close code from
        # a raw socket, but the disconnection itself proves backpressure works.
        result.step_passed("Firehose disconnected (slow consumer dropped)",
                           f"Server closed connection after {initial_count} initial frames")
    else:
        result.step_failed("Firehose disconnected",
                           "Connection still open or timed out")

    result.finish()
    return result


if __name__ == "__main__":
    res = run()
    res.print_summary()
    sys.exit(res.exit_code)
