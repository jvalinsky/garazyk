from __future__ import annotations

from typing import Any, Optional

from ..transport import TransportLayer


class RecordsClient:
    def __init__(self, transport: TransportLayer):
        self._t = transport

    def create_record(
        self,
        repo: str,
        collection: str,
        record: dict[str, Any],
        token: str,
        rkey: Optional[str] = None,
        validate: bool = True,
    ) -> dict:
        body: dict[str, Any] = {
            "repo": repo,
            "collection": collection,
            "record": record,
            "validate": validate,
        }
        if rkey:
            body["rkey"] = rkey
        return self._t.post("com.atproto.repo.createRecord", body, token=token)

    def get_record(self, repo: str, collection: str, rkey: str) -> dict:
        return self._t.get(
            "com.atproto.repo.getRecord",
            {"repo": repo, "collection": collection, "rkey": rkey},
        )

    def delete_record(self, repo: str, collection: str, rkey: str, token: str) -> None:
        self._t.post(
            "com.atproto.repo.deleteRecord",
            {"repo": repo, "collection": collection, "rkey": rkey},
            token=token,
        )

    def put_record(
        self,
        repo: str,
        collection: str,
        rkey: str,
        record: dict[str, Any],
        token: str,
    ) -> dict:
        return self._t.post(
            "com.atproto.repo.putRecord",
            {"repo": repo, "collection": collection, "rkey": rkey, "record": record},
            token=token,
        )

    def list_records(
        self,
        repo: str,
        collection: str,
        limit: int = 50,
        token: Optional[str] = None,
    ) -> dict:
        return self._t.get(
            "com.atproto.repo.listRecords",
            {"repo": repo, "collection": collection, "limit": limit},
            token=token,
        )

    def apply_writes(
        self,
        repo: str,
        writes: list[dict[str, Any]],
        token: str,
    ) -> dict:
        return self._t.post(
            "com.atproto.repo.applyWrites",
            {"repo": repo, "writes": writes},
            token=token,
        )
