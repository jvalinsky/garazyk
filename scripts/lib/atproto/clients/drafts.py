from __future__ import annotations

from typing import Any

from ..transport import TransportLayer


class DraftsClient:
    def __init__(self, transport: TransportLayer):
        self._t = transport

    def create_draft(self, content: dict, token: str) -> dict:
        return self._t.post("app.bsky.draft.createDraft", {"content": content}, token=token)

    def update_draft(self, draft_id: str, content: dict, token: str) -> dict:
        return self._t.post(
            "app.bsky.draft.updateDraft",
            {"id": draft_id, "content": content},
            token=token,
        )

    def get_drafts(self, token: str) -> dict:
        return self._t.get("app.bsky.draft.getDrafts", token=token)

    def delete_draft(self, draft_id: str, token: str) -> dict:
        return self._t.post(
            "app.bsky.draft.deleteDraft", {"id": draft_id}, token=token
        )
