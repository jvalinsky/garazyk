from __future__ import annotations

from typing import Any, Optional

from ..transport import TransportLayer


class AdminClient:
    def __init__(self, transport: TransportLayer):
        self._t = transport

    def get_subject_status(self, did: str, token: str) -> dict:
        return self._t.get("com.atproto.admin.getSubjectStatus", {"did": did}, token=token)

    def update_subject_status(
        self,
        subject: dict[str, Any],
        takedown: Optional[dict[str, Any]] = None,
        token: Optional[str] = None,
    ) -> dict:
        body: dict[str, Any] = {"subject": subject}
        if takedown:
            body["takedown"] = takedown
        return self._t.post("com.atproto.admin.updateSubjectStatus", body, token=token)

    def create_report(
        self,
        reason_type: str,
        subject: dict[str, Any],
        reason: str,
        token: str,
    ) -> dict:
        return self._t.post(
            "com.atproto.moderation.createReport",
            {"reasonType": reason_type, "subject": subject, "reason": reason},
            token=token,
        )

    def get_labels(self, uris: list[str], token: Optional[str] = None) -> dict:
        return self._t.get_labels(uris, token=token)
