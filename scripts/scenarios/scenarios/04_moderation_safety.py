"""Scenario 4: "Trollface Strikes" — Moderation & Safety

Trollface posts spam and harasses Luna. Luna reports the post.
Admin Sentinel reviews the report. Mod Justice applies a label via Ozone.
Admin takes down Trollface's account. Trollface's content becomes
inaccessible.

Services: PDS, AppView, Ozone
"""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.client import XrpcClient, XrpcError
from lib.characters import get_character, PDS1
from lib.assertions import assert_success, assert_contains, assert_xrpc_raises
from lib.report import ScenarioResult, StepStatus

# Admin password used by setup_local_network.sh when starting the PDS in
# binary mode (see PDS_ADMIN_PASSWORD export there). Tests obtain the admin
# bearer via POST /admin/login.
_DEFAULT_ADMIN_PASSWORD = "test-admin-password"


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def run() -> ScenarioResult:
    result = ScenarioResult("Moderation & Safety")
    result.start()

    client = XrpcClient(PDS1)

    # Wait for server
    try:
        client.wait_for_healthy(timeout=30)
        result.step_passed("Server health check")
    except RuntimeError as exc:
        result.step_failed("Server health check", str(exc))
        result.finish()
        return result

    # ── Create accounts ──────────────────────────────────────────────
    char_names = ["luna", "troll", "admin", "mod"]
    for name in char_names:
        char = get_character(name)
        try:
            session = client.create_account(char.handle, char.email, char.password)
            char.did = session["did"]
            char.access_jwt = session["accessJwt"]
            result.step_passed(f"Create account: {char.name}", f"did={char.did}")
        except XrpcError as exc:
            result.step_failed(f"Create account: {char.name}", str(exc))

    luna = get_character("luna")
    troll = get_character("troll")
    admin = get_character("admin")
    mod = get_character("mod")

    if not all([luna.did, troll.did, admin.did, mod.did]):
        result.step_failed("Account creation", "Not all accounts created")
        result.finish()
        return result

    # ── Obtain admin bearer via /admin/login ─────────────────────────
    admin_password = os.environ.get("PDS_ADMIN_PASSWORD", _DEFAULT_ADMIN_PASSWORD)
    admin_token = None
    try:
        admin_token = client.admin_login(admin_password)
        result.step_passed("Admin login", "obtained admin bearer")
    except XrpcError as exc:
        result.step_failed("Admin login", str(exc))

    # ── Set up profiles ──────────────────────────────────────────────
    for name in char_names:
        char = get_character(name)
        try:
            client.create_record(
                char.did,
                "app.bsky.actor.profile",
                {"$type": "app.bsky.actor.profile", "displayName": char.name, "description": char.persona},
                char.access_jwt,
            )
        except XrpcError:
            pass

    # ── Luna posts something nice ────────────────────────────────────
    luna_post = None
    try:
        luna_post = client.create_record(
            luna.did,
            "app.bsky.feed.post",
            {
                "$type": "app.bsky.feed.post",
                "text": "Beautiful night for stargazing! The Milky Way is visible tonight. ✨",
                "createdAt": _now(),
            },
            luna.access_jwt,
        )
        result.step_passed("Luna posts stargazing content")
    except XrpcError as exc:
        result.step_failed("Luna posts stargazing content", str(exc))

    # ── Trollface posts spam ─────────────────────────────────────────
    troll_spam = None
    try:
        troll_spam = client.create_record(
            troll.did,
            "app.bsky.feed.post",
            {
                "$type": "app.bsky.feed.post",
                "text": "BUY CRYPTO NOW!!! FREE MONEY!!! CLICK HERE!!! 🚨🚨🚨",
                "createdAt": _now(),
            },
            troll.access_jwt,
        )
        result.step_passed("Trollface posts spam")
    except XrpcError as exc:
        result.step_failed("Trollface posts spam", str(exc))

    # ── Trollface posts harassment targeting Luna ────────────────────
    troll_harass = None
    if luna_post:
        try:
            troll_harass = client.create_record(
                troll.did,
                "app.bsky.feed.post",
                {
                    "$type": "app.bsky.feed.post",
                    "text": "Your stargazing is stupid and nobody cares. Get a life, loser!",
                    "createdAt": _now(),
                    "reply": {
                        "root": {"uri": luna_post["uri"], "cid": luna_post["cid"]},
                        "parent": {"uri": luna_post["uri"], "cid": luna_post["cid"]},
                    },
                },
                troll.access_jwt,
            )
            result.step_passed("Trollface harasses Luna")
        except XrpcError as exc:
            result.step_failed("Trollface harasses Luna", str(exc))

    # ── Luna reports the harassment ──────────────────────────────────
    report_id = None
    if troll_harass:
        try:
            report = client.create_report(
                reason_type="com.atproto.moderation.defs#reasonRude",
                subject={
                    "$type": "com.atproto.repo.strongRef",
                    "uri": troll_harass["uri"],
                    "cid": troll_harass["cid"],
                },
                reason="Targeted harassment and personal attacks",
                token=luna.access_jwt,
            )
            report_id = report.get("id")
            result.step_passed("Luna reports harassment", f"report_id={report_id}")
        except XrpcError as exc:
            result.step_failed("Luna reports harassment", str(exc))
    else:
        result.step_failed("Luna reports harassment", "No harassment post to report")

    # ── Luna also reports the spam ───────────────────────────────────
    if troll_spam:
        try:
            spam_report = client.create_report(
                reason_type="com.atproto.moderation.defs#reasonSpam",
                subject={
                    "$type": "com.atproto.repo.strongRef",
                    "uri": troll_spam["uri"],
                    "cid": troll_spam["cid"],
                },
                reason="Spam content — crypto scam",
                token=luna.access_jwt,
            )
            result.step_passed("Luna reports spam", f"report_id={spam_report.get('id')}")
        except XrpcError as exc:
            result.step_failed("Luna reports spam", str(exc))

    # ── Admin checks subject status ─────────────────────────────────
    if admin_token:
        try:
            status = client.get_subject_status(troll.did, admin_token)
            result.step_passed("Admin checks Trollface status", f"status={status}")
        except XrpcError as exc:
            result.step_failed("Admin checks Trollface status", str(exc))
    else:
        result.step_failed("Admin checks Trollface status", "No admin token")

    # ── Mod reviews reports via Ozone ────────────────────────────────
    # Upstream Ozone replaced queryReports with queryEvents filtered by the
    # modEventReport type — use that.
    if admin_token:
        try:
            events = client.xrpc_get(
                "tools.ozone.moderation.queryEvents",
                {
                    "types": "tools.ozone.moderation.defs#modEventReport",
                    "subject": troll.did,
                },
                token=admin_token,
            )
            event_list = events.get("events", [])
            result.step_passed("Mod queries reports via Ozone", f"count={len(event_list)}")
        except XrpcError as exc:
            result.step_failed("Mod queries reports via Ozone", str(exc))
    else:
        result.step_failed("Mod queries reports via Ozone", "No admin token")

    # ── Mod applies takedown via Ozone ───────────────────────────────
    if troll_harass and admin_token:
        try:
            client.xrpc_post(
                "tools.ozone.moderation.emitEvent",
                {
                    "event": {
                        "$type": "tools.ozone.moderation.defs#modEventTakedown",
                        "comment": "Harassment and spam — takedown applied by Mod Justice",
                    },
                    "subject": {
                        "$type": "com.atproto.admin.defs#repoRef",
                        "did": troll.did,
                    },
                    "createdBy": mod.did,
                },
                token=admin_token,
            )
            result.step_passed("Mod applies takedown via Ozone")
        except XrpcError as exc:
            result.step_failed("Mod applies takedown via Ozone", str(exc))

    # ── Admin applies takedown on the account ───────────────────────
    if admin_token:
        try:
            client.update_subject_status(
                subject={"$type": "com.atproto.admin.defs#repoRef", "did": troll.did},
                takedown={"applied": True, "ref": "takedown-harassment-spam"},
                token=admin_token,
            )
            result.step_passed("Admin applies takedown on Trollface")
        except XrpcError as exc:
            result.step_failed("Admin applies takedown on Trollface", str(exc))
    else:
        result.step_failed("Admin applies takedown on Trollface", "No admin token")

    # ── Verify labels ────────────────────────────────────────────────
    if admin_token:
        try:
            labels = client.get_labels(
                [troll_harass["uri"]] if troll_harass else [],
                token=admin_token,
            )
            result.step_passed("Labels query", f"labels={labels}")
        except XrpcError as exc:
            result.step_failed("Labels query", str(exc))
    else:
        result.step_failed("Labels query", "No admin token")

    # ── Verify taken-down content is inaccessible ────────────────────
    if troll_harass:
        try:
            client.get_record(
                troll.did,
                "app.bsky.feed.post",
                troll_harass["uri"].split("/")[-1],
            )
            result.step_failed(
                "Taken-down content is inaccessible",
                "getRecord returned 200 for taken-down account",
            )
        except XrpcError as exc:
            if exc.status == 410 and isinstance(exc.body, dict) and \
                    exc.body.get("error") == "AccountTakedown":
                result.step_passed(
                    "Taken-down content is inaccessible",
                    "410 AccountTakedown",
                )
            else:
                result.step_failed(
                    "Taken-down content is inaccessible",
                    f"unexpected error: status={exc.status} body={exc.body!r}",
                )
    else:
        result.step_failed("Taken-down content check", "No harassment post to verify")

    # ── Admin posts community notice ──────────────────────────────────
    try:
        client.create_record(
            admin.did,
            "app.bsky.feed.post",
            {
                "$type": "app.bsky.feed.post",
                "text": "We've taken action against a spam/harassment account. Stay safe, everyone! 🛡️",
                "createdAt": _now(),
            },
            admin.access_jwt,
        )
        result.step_passed("Admin posts community notice")
    except XrpcError as exc:
        result.step_failed("Admin posts community notice", str(exc))

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
