"""Scenario 11: "Lab OAuth2 Login" — UI server OAuth2 login flow

This scenario exercises the Garazyk UI server's public Lab OAuth2 login
surface and admin authentication boundary. It verifies the lab landing page,
client metadata document, callback handling, and the admin login/logout
session flow exposed by the UI server.

Services: garazyk-ui
"""

from __future__ import annotations

import json
import os
import sys
from http.cookies import SimpleCookie
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.report import ScenarioResult, StepStatus


def _extract_cookie_value(set_cookie_header: str, cookie_name: str) -> str | None:
    """Extract a cookie value from a Set-Cookie header string."""
    cookie = SimpleCookie()
    cookie.load(set_cookie_header)
    morsel = cookie.get(cookie_name)
    if morsel is not None:
        return morsel.value
    return None


def _has_all_keys(payload: dict, keys: list[str]) -> tuple[bool, list[str]]:
    missing = [key for key in keys if key not in payload]
    return not missing, missing


def run() -> ScenarioResult:
    result = ScenarioResult("Lab OAuth2 Login")
    result.start()

    ui_url = os.environ.get("GARAZYK_UI_URL", "http://localhost:2590").rstrip("/")
    admin_password = os.environ.get("GARAZYK_UI_ADMIN_PASSWORD", "changeme")

    # 1. UI Server health check
    try:
        health_resp = requests.get(f"{ui_url}/lab", allow_redirects=False, timeout=10)
        if health_resp.status_code == 200:
            result.step_passed("UI Server health check", "GET /lab returned 200")
        else:
            result.step_failed(
                "UI Server health check",
                f"GET /lab returned status={health_resp.status_code}",
            )
    except Exception as exc:
        result.step_failed("UI Server health check", str(exc))
        result.finish()
        return result

    # 2. Lab page loads
    try:
        lab_resp = requests.get(f"{ui_url}/lab", allow_redirects=False, timeout=10)
        content_type = lab_resp.headers.get("Content-Type", "")
        body = lab_resp.text
        if (
            lab_resp.status_code == 200
            and content_type.lower().startswith("text/html")
            and "lab-login-section" in body
        ):
            result.step_passed(
                "Lab page loads",
                f"content_type={content_type!r}",
            )
        else:
            result.step_failed(
                "Lab page loads",
                f"status={lab_resp.status_code} content_type={content_type!r}",
            )
    except Exception as exc:
        result.step_failed("Lab page loads", str(exc))

    # 3. Lab client metadata valid
    try:
        meta_resp = requests.get(
            f"{ui_url}/lab/client-metadata.json",
            allow_redirects=False,
            timeout=10,
        )
        content_type = meta_resp.headers.get("Content-Type", "")
        metadata = meta_resp.json()
        required_keys = [
            "client_id",
            "client_name",
            "redirect_uris",
            "scope",
            "grant_types",
            "response_types",
            "token_endpoint_auth_method",
            "application_type",
            "dpop_bound_access_tokens",
        ]
        has_keys, missing_keys = _has_all_keys(metadata, required_keys)
        redirect_uris = metadata.get("redirect_uris", [])
        if not isinstance(redirect_uris, list):
            redirect_uris = []

        checks = [
            meta_resp.status_code == 200,
            content_type.lower().startswith("application/json"),
            has_keys,
            bool(metadata.get("client_id")),
            bool(metadata.get("client_name")),
            bool(metadata.get("scope")),
            isinstance(metadata.get("grant_types"), list)
            and "authorization_code" in metadata.get("grant_types", []),
            isinstance(metadata.get("response_types"), list)
            and "code" in metadata.get("response_types", []),
            metadata.get("token_endpoint_auth_method") == "none",
            bool(metadata.get("application_type")),
            metadata.get("dpop_bound_access_tokens") is True,
            any("/lab/callback" in uri for uri in redirect_uris),
        ]

        if all(checks):
            result.step_passed(
                "Lab client metadata valid",
                f"client_id={metadata.get('client_id')!r}",
            )
        else:
            result.step_failed(
                "Lab client metadata valid",
                json.dumps(
                    {
                        "status": meta_resp.status_code,
                        "content_type": content_type,
                        "missing_keys": missing_keys,
                        "client_id": metadata.get("client_id"),
                        "client_name": metadata.get("client_name"),
                        "redirect_uris": metadata.get("redirect_uris"),
                        "scope": metadata.get("scope"),
                        "grant_types": metadata.get("grant_types"),
                        "response_types": metadata.get("response_types"),
                        "token_endpoint_auth_method": metadata.get(
                            "token_endpoint_auth_method"
                        ),
                        "application_type": metadata.get("application_type"),
                        "dpop_bound_access_tokens": metadata.get(
                            "dpop_bound_access_tokens"
                        ),
                    },
                    sort_keys=True,
                ),
            )
    except Exception as exc:
        result.step_failed("Lab client metadata valid", str(exc))

    # 4. Lab callback accepts code param
    try:
        callback_resp = requests.get(
            f"{ui_url}/lab/callback",
            params={"code": "test-code", "state": "test-state"},
            allow_redirects=False,
            timeout=10,
        )
        if callback_resp.status_code == 200:
            result.step_passed("Lab callback accepts code param", "GET /lab/callback returned 200")
        else:
            result.step_failed(
                "Lab callback accepts code param",
                f"status={callback_resp.status_code}",
            )
    except Exception as exc:
        result.step_failed("Lab callback accepts code param", str(exc))

    # 5. Admin auth boundary
    try:
        admin_boundary_resp = requests.get(
            f"{ui_url}/admin",
            allow_redirects=False,
            timeout=10,
        )
        if admin_boundary_resp.status_code == 302:
            result.step_passed("Admin auth boundary", "GET /admin returned 302")
        else:
            result.step_failed(
                "Admin auth boundary",
                f"status={admin_boundary_resp.status_code}",
            )
    except Exception as exc:
        result.step_failed("Admin auth boundary", str(exc))

    # 6. Admin login flow
    admin_token = None
    admin_cookie_header = None
    try:
        login_resp = requests.post(
            f"{ui_url}/admin/login",
            json={"password": admin_password},
            headers={"Content-Type": "application/json"},
            timeout=10,
        )
        if login_resp.status_code != 200:
            result.step_failed(
                "Admin login flow",
                f"status={login_resp.status_code}",
            )
        else:
            set_cookie_header = login_resp.headers.get("Set-Cookie", "")
            admin_token = _extract_cookie_value(set_cookie_header, "ui_admin_token")
            if not admin_token:
                admin_token = login_resp.cookies.get("ui_admin_token")
            if not admin_token:
                try:
                    body = login_resp.json()
                except ValueError:
                    body = {}
                admin_token = body.get("token") or body.get("ui_admin_token")
            if admin_token:
                admin_cookie_header = f"ui_admin_token={admin_token}"
                result.step_passed("Admin login flow", "obtained ui_admin_token cookie")
            else:
                result.step_failed(
                    "Admin login flow",
                    "ui_admin_token cookie not present in Set-Cookie header",
                )
    except Exception as exc:
        result.step_failed("Admin login flow", str(exc))

    # 7. Admin authenticated access
    if admin_cookie_header:
        try:
            auth_admin_resp = requests.get(
                f"{ui_url}/admin",
                headers={"Cookie": admin_cookie_header},
                allow_redirects=False,
                timeout=10,
            )
            if auth_admin_resp.status_code == 200:
                result.step_passed("Admin authenticated access", "GET /admin returned 200 with cookie")
            else:
                result.step_failed(
                    "Admin authenticated access",
                    f"status={auth_admin_resp.status_code}",
                )
        except Exception as exc:
            result.step_failed("Admin authenticated access", str(exc))
    else:
        result.step_failed("Admin authenticated access", "No ui_admin_token cookie available")

    # 8. Admin HTMX auth
    try:
        htmx_unauth_resp = requests.get(
            f"{ui_url}/admin/partials/overview",
            headers={"HX-Request": "true"},
            allow_redirects=False,
            timeout=10,
        )
        if htmx_unauth_resp.status_code == 401:
            result.step_passed("Admin HTMX auth", "HTMX request without cookie returned 401")
        else:
            result.step_failed(
                "Admin HTMX auth",
                f"status={htmx_unauth_resp.status_code}",
            )
    except Exception as exc:
        result.step_failed("Admin HTMX auth", str(exc))

    # 9. Admin HTMX with auth
    if admin_cookie_header:
        try:
            htmx_auth_resp = requests.get(
                f"{ui_url}/admin/partials/overview",
                headers={
                    "HX-Request": "true",
                    "Cookie": admin_cookie_header,
                },
                allow_redirects=False,
                timeout=10,
            )
            if htmx_auth_resp.status_code == 200:
                result.step_passed("Admin HTMX with auth", "HTMX request with cookie returned 200")
            else:
                result.step_failed(
                    "Admin HTMX with auth",
                    f"status={htmx_auth_resp.status_code}",
                )
        except Exception as exc:
            result.step_failed("Admin HTMX with auth", str(exc))
    else:
        result.step_failed("Admin HTMX with auth", "No ui_admin_token cookie available")

    # 10. Admin logout
    if admin_cookie_header:
        try:
            logout_resp = requests.post(
                f"{ui_url}/admin/logout",
                headers={"Cookie": admin_cookie_header},
                timeout=10,
            )
            if logout_resp.status_code != 200:
                result.step_failed(
                    "Admin logout",
                    f"POST /admin/logout returned status={logout_resp.status_code}",
                )
            else:
                post_logout_resp = requests.get(
                    f"{ui_url}/admin",
                    headers={"Cookie": admin_cookie_header},
                    allow_redirects=False,
                    timeout=10,
                )
                if post_logout_resp.status_code == 302:
                    result.step_passed(
                        "Admin logout",
                        "POST /admin/logout returned 200; GET /admin returned 302 after logout",
                    )
                else:
                    result.step_failed(
                        "Admin logout",
                        f"POST /admin/logout returned 200 but GET /admin returned status={post_logout_resp.status_code}",
                    )
        except Exception as exc:
            result.step_failed("Admin logout", str(exc))
    else:
        result.step_failed("Admin logout", "No ui_admin_token cookie available")

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
