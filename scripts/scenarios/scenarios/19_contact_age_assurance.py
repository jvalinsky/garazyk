"""Scenario 19: "Trust & Verify" — Contact Management & Age Assurance

Luna verifies her phone number, imports contacts, and discovers matches.
Marcus begins the age assurance flow to verify his age.

Services: PDS, AppView (optional — some endpoints skip if no AppView)
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, ScenarioResult, timed_call



def run() -> ScenarioResult:
    result = ScenarioResult("Contact Management & Age Assurance")
    result.start()

    client = XrpcClient(PDS1)

    timed_call(result, "Server health check",
               lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    # ── Create accounts ──────────────────────────────────────────────
    char_names = ["luna", "marcus"]
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

    active = [n for n in char_names if get_character(n).did]
    if len(active) < 1:
        result.step_failed("Account creation", "No accounts created")
        result.finish()
        return result

    luna = get_character("luna")
    marcus = get_character("marcus")

    # ═══════════════════════════════════════════════════════════════════
    # PART 1: Contact Service
    # ═══════════════════════════════════════════════════════════════════

    if luna.access_jwt:
        # ── Start phone verification ────────────────────────────────
        timed_call(
            result, "Luna starts phone verification",
            lambda: client.contact.start_phone_verification("+15551234567", luna.access_jwt),
            detail_fn=lambda r: f"verificationId={r.get('verificationId', '')}",
            skip_on_status={404},
        )

        # ── Verify phone ────────────────────────────────────────────
        timed_call(
            result, "Luna verifies phone code",
            lambda: client.contact.verify_phone("+15551234567", "123456", luna.access_jwt),
            detail_fn=lambda r: f"got_token={bool(r.get('token', ''))}",
            skip_on_status={404},
        )

        # ── Import contacts ─────────────────────────────────────────
        timed_call(
            result, "Luna imports contacts",
            lambda: client.contact.import_contacts(
                ["+15551111111", "+15552222222", "+15553333333"],
                "test-import-token", luna.access_jwt,
            ),
            detail_fn=lambda r: f"matches={len(r.get('matches', []))}",
            skip_on_status={404},
        )

        # ── Get contact matches ─────────────────────────────────────
        timed_call(
            result, "Luna gets contact matches",
            lambda: client.contact.get_contact_matches(luna.access_jwt),
            detail_fn=lambda r: f"matches={len(r if isinstance(r, list) else r.get('matches', []))}",
            skip_on_status={404},
        )

        # ── Get sync status ─────────────────────────────────────────
        timed_call(
            result, "Luna gets sync status",
            lambda: client.contact.get_contact_sync_status(luna.access_jwt),
            detail_fn=lambda r: f"keys={list(r.keys())}",
            skip_on_status={404},
        )

        # ── Remove contact data ─────────────────────────────────────
        timed_call(
            result, "Luna removes contact data",
            lambda: client.contact.remove_contact_data(luna.access_jwt),
            skip_on_status={404},
        )
    else:
        for step in ["phone verification", "verify phone code", "import contacts",
                     "get contact matches", "get sync status", "remove contact data"]:
            result.step_skipped(f"Luna {step}", "Luna not created")

    # ═══════════════════════════════════════════════════════════════════
    # PART 2: Age Assurance
    # ═══════════════════════════════════════════════════════════════════

    # ── Get age assurance config ────────────────────────────────────
    timed_call(
        result, "Get age assurance config",
        lambda: client.age_assurance.get_age_assurance_config(),
        detail_fn=lambda r: f"keys={list(r.keys())}",
        skip_on_status={404},
    )

    # ── Begin age assurance ─────────────────────────────────────────
    if marcus.access_jwt:
        timed_call(
            result, "Marcus begins age assurance",
            lambda: client.age_assurance.begin_age_assurance(
                email=marcus.email, language="en",
                country_code="US", region_code="CA",
                token=marcus.access_jwt,
            ),
            detail_fn=lambda r: f"keys={list(r.keys())}",
            skip_on_status={404},
        )
    else:
        result.step_skipped("Marcus begins age assurance", "Marcus not created")

    # ── Get age assurance state ────────────────────────────────────
    if marcus.access_jwt:
        timed_call(
            result, "Marcus age assurance state",
            lambda: client.age_assurance.get_age_assurance_state(
                country_code="US", region_code="CA",
                token=marcus.access_jwt,
            ),
            detail_fn=lambda r: f"keys={list(r.keys())}",
            skip_on_status={404},
        )
    else:
        result.step_skipped("Marcus age assurance state", "Marcus not created")

    # ── Record artifacts ─────────────────────────────────────────────
    result.record_artifact("accounts", {
        n: {"did": get_character(n).did}
        for n in char_names if get_character(n).did
    })
    result.record_artifact("contact_steps", [
        "start_phone_verification", "verify_phone", "import_contacts",
        "get_contact_matches", "get_sync_status", "remove_contact_data",
    ])
    result.record_artifact("age_assurance_steps", [
        "get_config", "begin_age_assurance", "get_state",
    ])

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
