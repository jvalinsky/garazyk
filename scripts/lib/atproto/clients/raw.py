from __future__ import annotations

from typing import Any, Optional

from ..transport import TransportLayer


class RawClient:
    """Non-XRPC HTTP methods for admin routes and other raw endpoints."""

    def __init__(self, transport: TransportLayer):
        self._t = transport

    def http_get(
        self,
        path: str,
        params: Optional[dict[str, Any]] = None,
        token: Optional[str] = None,
    ) -> dict:
        return self._t.http_get(path, params=params, token=token)

    def http_post(
        self,
        path: str,
        body: Optional[dict[str, Any]] = None,
        token: Optional[str] = None,
    ) -> dict:
        return self._t.http_post(path, body=body, token=token)

    def xrpc_get(
        self,
        method: str,
        params: Optional[dict[str, Any]] = None,
        token: Optional[str] = None,
    ) -> dict:
        return self._t.get(method, params=params, token=token)

    def xrpc_post(
        self,
        method: str,
        body: Optional[dict[str, Any]] = None,
        token: Optional[str] = None,
    ) -> dict[str, Any]:
        return self._t.post(method, body=body, token=token)

    def post_raw(
        self,
        method: str,
        data: bytes,
        content_type: str,
        params: Optional[dict[str, Any]] = None,
        token: Optional[str] = None,
    ) -> dict[str, Any]:
        """POST raw binary data to an XRPC endpoint."""
        return self._t.post_raw(method, data, content_type=content_type, token=token)

    def xrpc_get_binary(
        self,
        method: str,
        params: Optional[dict[str, Any]] = None,
        token: Optional[str] = None,
        headers: Optional[dict[str, str]] = None,
    ) -> tuple[int, str, bytes]:
        return self._t.get_binary(method, params=params, token=token, headers=headers)
