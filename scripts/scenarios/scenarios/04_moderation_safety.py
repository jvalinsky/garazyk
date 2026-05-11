"""Scenario 4: "Trollface Strikes" — Moderation & Safety

Trollface posts spam and harasses Luna. Luna reports the post.
Admin Sentinel reviews the report. Mod Justice applies a takedown via Ozone.
Admin takes down Trollface's account. Trollface's content becomes
inaccessible.

Services: PDS, AppView, Ozone
"""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, ScenarioResult, timed_call


_DEFAULT_ADMIN_PASSWORD = "test-admin-password"


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def run() -> ScenarioResult:
    result = ScenarioResult("Moderation & Safety")
    result.start()

    client = XrpcClient(PDS1)

    timed_call(result, "Server health check",
               lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    char_names = ["luna", "troll", "admin", "mod"]
    for name in char_names:
        char = get_character(name)
        session = timed_call(
            result, f"Create account: {char.name}",
            lambda c=char: client.accounts.create_account(c.handle, c.email, c.password),
            detail_fn=lambda s, n=name: f"did={s['did']}",
        )
        if session:
            char.did = session["did"]
            char.access_jwt = session["accessJwt"]

    luna = get_character("luna")
    troll = get_character("troll")
    admin = get_character("admin")
    mod = get_character("mod")

    if not all([luna.did, troll.did, admin.did, mod.did]):
        result.step_failed("Account creation", "Not all accounts created")
        result.finish()
        return result

    admin_password = os.environ.get("PDS_ADMIN_PASSWORD", _DEFAULT_ADMIN_PASSWORD)
    admin_token = timed_call(
        result, "Admin login",
        lambda: client.accounts.admin_login(admin_password),
        detail_fn=lambda t: "obtained admin bearer",
    )

    for name in char_names:
        char = get_character(name)
        timed_call(
            result, f"Set profile: {char.name}",
            lambda c=char: client.records.create_record(
                c.did, "app.bsky.actor.profile",
                {"$type": "app.bsky.actor.profile", "displayName": c.name, "description": c.persona},
                c.access_jwt),
        )

    luna_post = timed_call(
        result, "Luna posts stargazing content",
        lambda: client.records.create_record(
            luna.did, "app.bsky.feed.post",
            {"$type": "app.bsky.feed.post", "text": "Beautiful night for stargazing! The Milky Way is visible tonight.",
             "createdAt": _now()},
            luna.access_jwt),
    )

    troll_spam = timed_call(
        result, "Trollface posts spam",
        lambda: client.records.create_record(
            troll.did, "app.bsky.feed.post",
            {"$type": "app.bsky.feed.post", "text": "BUY CRYPTO NOW!!! FREE MONEY!!! CLICK HERE!!!",
             "createdAt": _now()},
            troll.access_jwt),
    )

    troll_harass = None
    if luna_post:
        troll_harass = timed_call(
            result, "Trollface harasses Luna",
            lambda: client.records.create_record(
                troll.did, "app.bsky.feed.post",
                {"$type": "app.bsky.feed.post",
                 "text": "Your stargazing is stupid and nobody cares. Get a life, loser!",
                 "createdAt": _now(),
                 "reply": {"root": {"uri": luna_post["uri"], "cid": luna_post["cid"]},
                           "parent": {"uri": luna_post["uri"], "cid": luna_post["cid"]}}},
                troll.access_jwt),
        )

    if troll_harass:
        timed_call(
            result, "Luna reports harassment",
            lambda: client.admin.create_report(
                reason_type="com.atproto.moderation.defs#reasonRude",
                subject={"$type": "com.atproto.repo.strongRef",
                         "uri": troll_harass["uri"], "cid": troll_harass["cid"]},
                reason="Targeted harassment and personal attacks",
                token=luna.access_jwt),
            detail_fn=lambda r: f"report_id={r.get('id')}",
        )
    else:
        result.step_failed("Luna reports harassment", "No harassment post to report")

    if troll_spam:
        timed_call(
            result, "Luna reports spam",
            lambda: client.admin.create_report(
                reason_type="com.atproto.moderation.defs#reasonSpam",
                subject={"$type": "com.atproto.repo.strongRef",
                         "uri": troll_spam["uri"], "cid": troll_spam["cid"]},
                reason="Spam content — crypto scam",
                token=luna.access_jwt),
            detail_fn=lambda r: f"report_id={r.get('id')}",
        )

    if admin_token:
        timed_call(
            result, "Admin checks Trollface status",
            lambda: client.admin.get_subject_status(troll.did, admin_token),
            detail_fn=lambda s: f"status={s}",
        )
    else:
        result.step_failed("Admin checks Trollface status", "No admin token")

    if admin_token:
        timed_call(
            result, "Mod queries reports via Ozone",
            lambda: client.raw.xrpc_get(
                "tools.ozone.moderation.queryEvents",
                {"types": "tools.ozone.moderation.defs#modEventReport", "subject": troll.did},
                token=admin_token),
            detail_fn=lambda e: f"count={len(e.get('events', []))}",
        )
    else:
        result.step_failed("Mod queries reports via Ozone", "No admin token")

    if troll_harass and admin_token:
        timed_call(
            result, "Mod applies takedown via Ozone",
            lambda: client.raw.xrpc_post(
                "tools.ozone.moderation.emitEvent",
                {"event": {"$type": "tools.ozone.moderation.defs#modEventTakedown",
                           "comment": "Harassment and spam — takedown applied by Mod Justice"},
                 "subject": {"$type": "com.atproto.admin.defs#repoRef", "did": troll.did},
                 "createdBy": mod.did},
                token=admin_token),
        )

    if admin_token:
        timed_call(
            result, "Admin applies takedown on Trollface",
            lambda: client.admin.update_subject_status(
                subject={"$type": "com.atproto.admin.defs#repoRef", "did": troll.did},
                takedown={"applied": True, "ref": "takedown-harassment-spam"},
                token=admin_token),
        )
    else:
        result.step_failed("Admin applies takedown on Trollface", "No admin token")

    if admin_token:
        timed_call(
            result, "Labels query",
            lambda: client.admin.get_labels(
                [troll_harass["uri"]] if troll_harass else [],
                token=admin_token),
            detail_fn=lambda l: f"labels={l}",
        )
    else:
        result.step_failed("Labels query", "No admin token")

    if troll_harass:
        err = timed_call(
            result, "Taken-down content is inaccessible",
            lambda: client.records.get_record(
                troll.did, "app.bsky.feed.post", troll_harass["uri"].split("/")[-1]),
            expect_failure="AccountTakedown",
        )
    else:
        result.step_failed("Taken-down content check", "No harassment post to verify")

    timed_call(
        result, "Admin posts community notice",
        lambda: client.records.create_record(
            admin.did, "app.bsky.feed.post",
            {"$type": "app.bsky.feed.post",
             "text": "We've taken action against a spam/harassment account. Stay safe, everyone!",
             "createdAt": _now()},
            admin.access_jwt),
    )

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
