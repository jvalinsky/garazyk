from __future__ import annotations

from typing import Any, Optional

from ..transport import TransportLayer


class AgeAssuranceClient:
    def __init__(self, transport: TransportLayer):
        self._t = transport

    def begin_age_assurance(
        self,
        email: str,
        language: str,
        country_code: str,
        region_code: Optional[str] = None,
        token: Optional[str] = None,
    ) -> dict:
        body: dict[str, Any] = {
            "email": email,
            "language": language,
            "countryCode": country_code,
        }
        if region_code:
            body["regionCode"] = region_code
        return self._t.post("app.bsky.ageassurance.begin", body, token=token)

    def get_age_assurance_config(self, token: Optional[str] = None) -> dict:
        return self._t.get("app.bsky.ageassurance.getConfig", token=token)

    def get_age_assurance_state(
        self,
        country_code: str,
        region_code: Optional[str] = None,
        token: Optional[str] = None,
    ) -> dict:
        params: dict[str, Any] = {"countryCode": country_code}
        if region_code:
            params["regionCode"] = region_code
        return self._t.get("app.bsky.ageassurance.getState", params, token=token)
