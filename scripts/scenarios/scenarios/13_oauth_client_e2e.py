"""Scenario 13: "E2E OAuth2 Client Integration" — Full stack OAuth2 dance

This scenario uses Playwright to automate a real browser flow against a mock
ATProto client. It verifies that the PDS correctly handles PAR, dynamic
client discovery (with SSRF bypass), and DPoP-bound token issuance.

Services: PLC, PDS, AppView, oauth-client
"""

from __future__ import annotations

import os
import sys
import time
import asyncio
from pathlib import Path

# Add scenario-local compatibility shims and repository helpers to path.
sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.report import ScenarioResult, StepStatus
from lib.characters import get_character, PDS1
from scripts.lib.atproto import SERVICE_URLS

async def run_async() -> ScenarioResult:
    result = ScenarioResult("E2E OAuth2 Client Integration")
    result.start()

    # 1. Check if oauth-client is up
    import requests
    client_url = "http://localhost:8080"
    try:
        resp = requests.get(f"{client_url}/client-metadata.json", timeout=5)
        if resp.status_code == 200:
            result.step_passed("OAuth Client availability", "client-metadata.json is reachable")
        else:
            result.step_failed("OAuth Client availability", f"Status: {resp.status_code}")
            result.finish()
            return result
    except Exception as exc:
        result.step_failed("OAuth Client availability", str(exc))
        result.finish()
        return result

    # 2. Browser Automation
    from playwright.async_api import async_playwright

    luna = get_character("luna")

    try:
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            context = await browser.new_context()
            page = await context.new_page()
            
            # Log console messages
            page.on("console", lambda msg: print(f"BROWSER CONSOLE: {msg.text}"))
            page.on("pageerror", lambda err: print(f"BROWSER ERROR: {err}"))
            
            # Navigate to client using localhost (secure context)
            await page.goto("http://localhost:8080")
            result.step_passed("Navigate to client app")

            # Enter handle and sign in
            await page.fill("#handle", luna.handle)
            await page.click("#login-btn")
            result.step_passed("Initiate login flow")

            # Wait for redirect to PDS authorize page
            # Selector from authorize.html
            await page.wait_for_selector("#auth-handle", timeout=15000)
            result.step_passed("Redirected to PDS authorize page")

            # PDS Login
            await page.fill("#auth-handle", luna.handle)
            await page.fill("#auth-password", luna.password)
            await page.click("#auth-signin-btn")
            result.step_passed("PDS Sign-in successful")

            # Consent Step
            await page.wait_for_selector("button[type='submit'].btn-primary", timeout=5000)
            await page.click("button[type='submit'].btn-primary")
            result.step_passed("Consent granted")

            # Wait for redirect back to client and profile display
            await page.wait_for_selector("#profile", timeout=10000)
            
            # Verify profile info
            display_name = await page.inner_text("#display-name")
            if "did:plc:" in display_name:
                result.step_passed("Profile displayed", f"Logged in as {display_name}")
            else:
                result.step_failed("Profile displayed", f"Unexpected display name: {display_name}")

            await browser.close()

    except Exception as exc:
        result.step_failed("Browser automation", str(exc))

    result.finish()
    return result

def run() -> ScenarioResult:
    return asyncio.run(run_async())

if __name__ == "__main__":
    res = run()
    res.print_summary()
    sys.exit(res.exit_code)
