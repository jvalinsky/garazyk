from __future__ import annotations

from ..transport import TransportLayer


class ContactClient:
    def __init__(self, transport: TransportLayer):
        self._t = transport

    def start_phone_verification(self, phone_number: str, token: str) -> dict:
        return self._t.post(
            "app.bsky.contact.startPhoneVerification",
            {"phoneNumber": phone_number},
            token=token,
        )

    def verify_phone(self, phone_number: str, code: str, token: str) -> dict:
        return self._t.post(
            "app.bsky.contact.verifyPhone",
            {"phoneNumber": phone_number, "code": code},
            token=token,
        )

    def import_contacts(self, contacts: list, import_token: str, token: str) -> dict:
        return self._t.post(
            "app.bsky.contact.importContacts",
            {"token": import_token, "contacts": contacts},
            token=token,
        )

    def get_contact_matches(self, token: str) -> dict:
        return self._t.get("app.bsky.contact.getMatches", token=token)

    def dismiss_contact_match(self, did: str, token: str) -> dict:
        return self._t.post("app.bsky.contact.dismissMatch", {"did": did}, token=token)

    def get_contact_sync_status(self, token: str) -> dict:
        return self._t.get("app.bsky.contact.getSyncStatus", token=token)

    def remove_contact_data(self, token: str) -> dict:
        return self._t.post("app.bsky.contact.removeData", token=token)
