from __future__ import annotations

from ..transport import TransportLayer


class BlobsClient:
    def __init__(self, transport: TransportLayer):
        self._t = transport

    def upload_blob(self, data: bytes, content_type: str, token: str) -> dict:
        return self._t.post_raw(
            "com.atproto.repo.uploadBlob", data, content_type, token=token
        )
