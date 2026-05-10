"""Low-level HTTP transport for ATProto XRPC and admin endpoints.

Extracted from client.py to separate transport concerns (retry, logging,
connection pooling) from domain-specific XRPC method wrappers.
"""

from __future__ import annotations

import json
import logging
import time
from typing import Any, Optional

import requests

logger = logging.getLogger("atproto.scenario")

_REQUEST_TIMEOUT = 20
_RETRY_ATTEMPTS = 3
_RETRY_BACKOFF = 1.0
_RING_BUFFER_MAX = 20


class XrpcError(Exception):
    """Raised when an XRPC or adjacent admin call fails.

    Attributes:
        method: XRPC method id or HTTP path used for the request.
        status: HTTP status code; 0 means the request did not reach a server.
        body: Decoded JSON error body when available, otherwise response text.
    """

    def __init__(self, method: str, status: int, body: dict | str):
        self.method = method
        self.status = status
        self.body = body
        super().__init__(f"XRPC {method} failed ({status}): {body}")


def _safe_json(resp: requests.Response) -> Any:
    """Decode a response body for diagnostics."""
    try:
        return resp.json()
    except (json.JSONDecodeError, ValueError):
        return resp.text


class TransportLayer:
    """Low-level HTTP transport with retry, logging, and response history.

    Provides the wire-protocol methods (xrpc_get, xrpc_post, http_get, etc.)
    that domain-specific sub-clients delegate to.
    """

    def __init__(self, base_url: str = "http://localhost:2583"):
        self._base_url = base_url.rstrip("/")
        self._session = requests.Session()
        self._last_responses: list[dict] = []
        self._max_attempts = _RETRY_ATTEMPTS
        self._base_delay = _RETRY_BACKOFF

    # ── Response history ─────────────────────────────────────────────

    @property
    def last_responses(self) -> list[dict]:
        return list(self._last_responses)

    @property
    def last_response(self) -> Optional[dict]:
        return self._last_responses[-1] if self._last_responses else None

    def _record(self, method: str, status: int, body: Any) -> None:
        self._last_responses.append({
            "method": method, "status": status, "body": body,
            "time": time.time(),
        })
        if len(self._last_responses) > _RING_BUFFER_MAX:
            self._last_responses.pop(0)

    # ── Logging ───────────────────────────────────────────────────────

    def _log_request(self, method: str, url: str, body: Any = None) -> None:
        if not logger.isEnabledFor(logging.DEBUG):
            return
        safe_body: str | None = None
        if body is not None and body != "":
            raw = json.dumps(body, default=str)
            safe_body = raw[:500] + ("..." if len(raw) > 500 else "")
        logger.debug("REQ %s %s body=%s", method, url, safe_body or "(none)")

    def _log_response(self, url: str, status: int, body: Any) -> None:
        if not logger.isEnabledFor(logging.DEBUG):
            return
        raw = json.dumps(body, default=str) if body is not None else ""
        safe = raw[:1000] + ("..." if len(raw) > 1000 else "")
        logger.debug("RSP %s %s body=%s", status, url, safe)

    # ── Core request with hand-rolled retry ───────────────────────────

    def _request(
        self,
        method: str,
        url: str,
        *,
        json_body: Optional[dict] = None,
        headers: Optional[dict[str, str]] = None,
        params: Optional[dict[str, Any]] = None,
        data: Optional[bytes] = None,
        success_status: tuple[int, ...] = (200,),
        retry: bool = True,
        method_name: str = "",
    ) -> dict:
        """Issue an HTTP request with optional retry.

        Retries on transport errors and 5xx responses when retry=True.
        Returns the decoded JSON body on success_status.
        """
        last_error: XrpcError | None = None
        max_attempts = self._max_attempts if retry else 1

        for attempt in range(1, max_attempts + 1):
            try:
                resp = self._session.request(
                    method, url,
                    params=params, json=json_body, data=data,
                    headers=headers, timeout=_REQUEST_TIMEOUT,
                )
                if resp.status_code in success_status:
                    body = resp.json()
                    self._log_response(url, resp.status_code, body)
                    self._record(method_name or url, resp.status_code, body)
                    return body
                err_body = _safe_json(resp)
                last_error = XrpcError(method_name or url, resp.status_code, err_body)
                self._log_response(url, resp.status_code, err_body)
                self._record(method_name or url, resp.status_code, err_body)
                if resp.status_code < 500 or not retry:
                    raise last_error
            except requests.RequestException as exc:
                last_error = XrpcError(method_name or url, 0, str(exc))
                self._record(method_name or url, 0, str(exc))
                if not retry:
                    raise last_error
            if attempt < max_attempts:
                time.sleep(self._base_delay * attempt)

        raise last_error

    # ── XRPC methods ─────────────────────────────────────────────────

    def get(self, method: str, params: Optional[dict] = None,
            token: Optional[str] = None) -> dict:
        url = f"{self._base_url}/xrpc/{method}"
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        self._log_request("GET", url, {"params": params})
        return self._request("GET", url, params=params, headers=headers, method_name=method)

    def get_binary(self, method: str, params: Optional[dict] = None,
                   token: Optional[str] = None) -> tuple[int, str, bytes]:
        url = f"{self._base_url}/xrpc/{method}"
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        self._log_request("GET", url, {"params": params})
        for attempt in range(1, self._max_attempts + 1):
            try:
                resp = self._session.get(
                    url, params=params, headers=headers, timeout=_REQUEST_TIMEOUT,
                )
                if 200 <= resp.status_code < 300:
                    ct = resp.headers.get("Content-Type", "")
                    self._log_response(url, resp.status_code, f"<{len(resp.content)} bytes {ct}>")
                    return (resp.status_code, ct, resp.content)
                err_body = _safe_json(resp)
                if resp.status_code < 500:
                    raise XrpcError(method, resp.status_code, err_body)
                self._log_response(url, resp.status_code, err_body)
            except requests.RequestException:
                pass
            if attempt < self._max_attempts:
                time.sleep(self._base_delay * attempt)
        raise XrpcError(method, 0, "binary request failed after retries")

    def post(self, method: str, body: Optional[dict] = None,
             token: Optional[str] = None) -> dict:
        url = f"{self._base_url}/xrpc/{method}"
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        self._log_request("POST", url, body)
        return self._request("POST", url, json_body=body, headers=headers,
                             success_status=(200, 201), method_name=method)

    def post_raw(self, method: str, data: bytes, content_type: str,
                 token: Optional[str] = None) -> dict:
        url = f"{self._base_url}/xrpc/{method}"
        headers = {"Content-Type": content_type}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        self._log_request("POST", url, f"<{len(data)} bytes {content_type}>")
        resp = self._session.post(url, data=data, headers=headers, timeout=60)
        if resp.status_code in (200, 201):
            data_json = resp.json()
            self._log_response(url, resp.status_code, data_json)
            self._record(method, resp.status_code, data_json)
            return data_json
        err_body = _safe_json(resp)
        self._log_response(url, resp.status_code, err_body)
        self._record(method, resp.status_code, err_body)
        raise XrpcError(method, resp.status_code, err_body)

    # ── Non-XRPC HTTP helpers ────────────────────────────────────────

    def http_get(self, path: str, params: Optional[dict] = None,
                 token: Optional[str] = None) -> dict:
        url = f"{self._base_url}{path}"
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        self._log_request("GET", url, {"params": params})
        return self._request("GET", url, params=params, headers=headers, method_name=path)

    def http_post(self, path: str, body: Optional[dict] = None,
                  token: Optional[str] = None) -> dict:
        url = f"{self._base_url}{path}"
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        self._log_request("POST", url, body)
        return self._request("POST", url, json_body=body, headers=headers,
                             success_status=(200, 201), method_name=path)

    # ── Special: repeated-param GET (getLabels) ──────────────────────

    def get_labels(self, uris: list[str], token: Optional[str] = None) -> dict:
        params = [("uris[]", u) for u in uris]
        url = f"{self._base_url}/xrpc/com.atproto.label.getLabels"
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        resp = self._session.get(url, params=params, headers=headers, timeout=_REQUEST_TIMEOUT)
        if resp.status_code == 200:
            return resp.json()
        raise XrpcError("com.atproto.label.getLabels", resp.status_code, _safe_json(resp))

    # ── Health ────────────────────────────────────────────────────────

    def health_check(self) -> bool:
        try:
            resp = self._session.get(f"{self._base_url}/_health", timeout=2)
            return resp.status_code == 200
        except requests.RequestException:
            return False

    def wait_for_healthy(self, timeout: int = 30) -> None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.health_check():
                return
            time.sleep(0.5)
        raise RuntimeError(f"Service at {self._base_url} not healthy after {timeout}s")
