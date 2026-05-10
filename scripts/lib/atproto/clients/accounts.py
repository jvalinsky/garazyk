from __future__ import annotations

import logging
import time
from typing import Any, Optional

from ..transport import TransportLayer, XrpcError

logger = logging.getLogger("atproto.scenario")


class AccountsClient:
    def __init__(self, transport: TransportLayer):
        self._t = transport

    def create_account(
        self, handle: str, email: str, password: str, _retries: int = 3
    ) -> dict:
        logger.info("Creating account: %s", handle)
        last_error = None
        for attempt in range(1, _retries + 1):
            try:
                return self._t.post(
                    "com.atproto.server.createAccount",
                    {"email": email, "handle": handle, "password": password},
                )
            except XrpcError as exc:
                last_error = exc
                if exc.status == 400 and isinstance(exc.body, dict):
                    msg = str(exc.body.get("message", "")).lower()
                    if any(s in msg for s in ("network connection", "could not connect", "timed out")):
                        logger.warning(
                            "Account creation retry %d/%d for %s: %s",
                            attempt, _retries, handle, exc.body.get("message"),
                        )
                        if attempt < _retries:
                            time.sleep(1.0 * attempt)
                            continue
                raise
        raise last_error

    def create_session(self, identifier: str, password: str) -> dict:
        logger.info("Creating session: %s", identifier)
        return self._t.post(
            "com.atproto.server.createSession",
            {"identifier": identifier, "password": password},
        )

    def get_session(self, token: str) -> dict:
        return self._t.get("com.atproto.server.getSession", token=token)

    def refresh_session(self, refresh_jwt: str) -> dict:
        return self._t.post("com.atproto.server.refreshSession", token=refresh_jwt)

    def delete_session(self, token: str) -> None:
        try:
            self._t.post("com.atproto.server.deleteSession", token=token)
        except XrpcError:
            pass

    def describe_server(self) -> dict:
        return self._t.get("com.atproto.server.describeServer")

    def admin_login(self, password: str) -> str:
        url = f"{self._t._base_url}/admin/login"
        try:
            resp = self._t._session.post(
                url,
                json={"password": password},
                headers={"Content-Type": "application/json"},
                timeout=20,
            )
        except Exception as exc:
            raise XrpcError("/admin/login", 0, str(exc))
        if resp.status_code != 200:
            raise XrpcError("/admin/login", resp.status_code, resp.text)
        token = resp.json().get("token", "")
        if not token:
            raise XrpcError("/admin/login", 200, {"error": "missing token in response"})
        return token
