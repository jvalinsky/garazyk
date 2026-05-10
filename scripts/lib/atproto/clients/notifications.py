from __future__ import annotations

from typing import Any, Optional

from ..transport import TransportLayer


class NotificationsClient:
    def __init__(self, transport: TransportLayer):
        self._t = transport

    def list_notifications(self, token: str, limit: int = 50) -> dict:
        return self._t.get(
            "app.bsky.notification.listNotifications", {"limit": limit}, token=token
        )

    def update_seen(self, token: str, limit: int = 0) -> dict:
        return self._t.post(
            "app.bsky.notification.updateSeen", {"limit": limit}, token=token
        )

    def register_push(
        self,
        service_did: str,
        token: str,
        platform: str,
        app_id: str,
        auth_token: str,
    ) -> dict:
        return self._t.post(
            "app.bsky.notification.registerPush",
            {"serviceDid": service_did, "token": token, "platform": platform, "appId": app_id},
            token=auth_token,
        )

    def unregister_push(
        self,
        service_did: str,
        token: str,
        platform: str,
        app_id: str,
        auth_token: str,
    ) -> dict:
        return self._t.post(
            "app.bsky.notification.unregisterPush",
            {"serviceDid": service_did, "token": token, "platform": platform, "appId": app_id},
            token=auth_token,
        )

    def get_notification_preferences(self, token: str) -> dict:
        return self._t.get("app.bsky.notification.getPreferences", token=token)

    def put_notification_preferences(self, preferences: dict, token: str) -> dict:
        return self._t.post(
            "app.bsky.notification.putPreferences",
            {"priority": preferences.get("priority", False)},
            token=token,
        )

    def list_activity_subscriptions(self, token: str, limit: int = 50) -> dict:
        return self._t.get(
            "app.bsky.notification.listActivitySubscriptions",
            {"limit": limit},
            token=token,
        )

    def put_activity_subscription(
        self, subject: str, post_enabled: bool, reply_enabled: bool, token: str
    ) -> dict:
        return self._t.post(
            "app.bsky.notification.putActivitySubscription",
            {"subject": subject, "postEnabled": post_enabled, "replyEnabled": reply_enabled},
            token=token,
        )
