"""Scenario 13: "E2E OAuth2 Client Integration" — Full stack OAuth2 dance

This scenario uses Playwright to automate a real browser flow against a mock
ATProto client. It verifies that the PDS correctly handles PAR, dynamic
client discovery (with SSRF bypass), and DPoP-bound token issuance.

Services: PLC, PDS, AppView, oauth-client
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
import time
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import ScenarioResult, timed_call, get_character, PDS1, XrpcClient


PDS_URL = "http://127.0.0.1:2583"
PLC_URL = "http://127.0.0.1:2582"


async def run_async() -> ScenarioResult:
    result = ScenarioResult("E2E OAuth2 Client Integration")
    result.start()

    pds = XrpcClient(PDS1)
    luna = get_character("luna")

    session = timed_call(
        result, "Create account",
        lambda: pds.accounts.create_account(luna.handle, luna.email, luna.password),
        detail_fn=lambda s: f"did={s['did']}",
    )
    if not session:
        result.finish()
        return result
    luna.did = session["did"]

    resolved = timed_call(
        result, "Verify account resolution",
        lambda: pds.identity.resolve_handle(luna.handle),
        detail_fn=lambda r: f"handle {luna.handle} -> {r.get('did')}",
    )
    if resolved and resolved.get("did") != luna.did:
        result.step_failed("Verify account resolution", f"Got wrong DID: {resolved.get('did')}")
        result.finish()
        return result

    import requests

    try:
        did_resp = requests.get(f"{PLC_URL}/{luna.did}", timeout=5)
        did_doc = did_resp.json()
        services = did_doc.get("service", [])
        pds_endpoint = None
        for svc in services:
            if svc.get("id") == "#atproto_pds" or "atproto_pds" in svc.get("id", ""):
                pds_endpoint = svc.get("serviceEndpoint")
        print(f"[DIAG-D1] PDS serviceEndpoint: {pds_endpoint}")
        result.step_passed("D1: DID document inspection", f"serviceEndpoint={pds_endpoint}")
    except Exception as exc:
        result.step_failed("D1: DID document inspection", str(exc))

    try:
        prm_resp = requests.get(
            f"{PDS_URL}/.well-known/oauth-protected-resource",
            headers={"Accept": "application/json", "Origin": "http://127.0.0.1:8080"},
            timeout=5,
        )
        prm_body = prm_resp.json() if prm_resp.status_code == 200 else {}
        resource_val = prm_body.get("resource") if isinstance(prm_body, dict) else None
        expected_origin = "http://127.0.0.1:2583"
        if resource_val == expected_origin:
            result.step_passed("D2: Protected resource metadata",
                               f"resource={resource_val} (matches expected origin)")
        else:
            result.step_failed("D2: Protected resource metadata",
                               f"resource={resource_val!r} != expected origin {expected_origin!r}")
    except Exception as exc:
        result.step_failed("D2: Protected resource metadata", str(exc))

    try:
        asm_resp = requests.get(
            f"{PDS_URL}/.well-known/oauth-authorization-server",
            headers={"Accept": "application/json", "Origin": "http://127.0.0.1:8080"},
            timeout=5,
        )
        asm_body = asm_resp.json() if asm_resp.status_code == 200 else {}
        issuer_val = asm_body.get("issuer") if isinstance(asm_body, dict) else None
        expected_origin = "http://127.0.0.1:2583"
        if issuer_val == expected_origin:
            result.step_passed("D3: Authorization server metadata",
                               f"issuer={issuer_val} (matches expected origin)")
        else:
            result.step_failed("D3: Authorization server metadata",
                               f"issuer={issuer_val!r} != expected origin {expected_origin!r}")
    except Exception as exc:
        result.step_failed("D3: Authorization server metadata", str(exc))

    try:
        cors_resp = requests.options(
            f"{PDS_URL}/.well-known/oauth-protected-resource",
            headers={"Origin": "http://127.0.0.1:8080",
                     "Access-Control-Request-Method": "GET",
                     "Access-Control-Request-Headers": "Accept"},
            timeout=5,
        )
        acao = cors_resp.headers.get("Access-Control-Allow-Origin")
        if acao and (acao == "*" or acao == "http://127.0.0.1:8080"):
            result.step_passed("D4: CORS preflight", f"Allow-Origin={acao}")
        else:
            result.step_failed("D4: CORS preflight",
                               f"Allow-Origin={acao!r} (expected '*' or 'http://127.0.0.1:8080')")
    except Exception as exc:
        result.step_failed("D4: CORS preflight", str(exc))

    try:
        cors_resp2 = requests.options(
            f"{PDS_URL}/.well-known/oauth-authorization-server",
            headers={"Origin": "http://127.0.0.1:8080",
                     "Access-Control-Request-Method": "GET",
                     "Access-Control-Request-Headers": "Accept"},
            timeout=5,
        )
        acao2 = cors_resp2.headers.get("Access-Control-Allow-Origin")
        if acao2 and (acao2 == "*" or acao2 == "http://127.0.0.1:8080"):
            result.step_passed("D5: CORS preflight (auth-server)", f"Allow-Origin={acao2}")
        else:
            result.step_failed("D5: CORS preflight (auth-server)", f"Allow-Origin={acao2!r}")
    except Exception as exc:
        result.step_failed("D5: CORS preflight (auth-server)", str(exc))

    client_url = "http://localhost:8080"
    try:
        resp = requests.get(f"{client_url}/client-metadata.json", timeout=5)
        if resp.status_code == 200:
            result.step_passed("OAuth Client availability", "client-metadata.json is reachable")
        else:
            result.step_skipped("OAuth Client availability", f"OAuth client at {client_url} returned status {resp.status_code}; skipping browser automation")
            result.finish()
            return result
    except Exception as exc:
        result.step_skipped("OAuth Client availability", f"OAuth client not running at {client_url}: {exc}; skipping browser automation")
        result.finish()
        return result

    from playwright.async_api import async_playwright

    luna = get_character("luna")

    try:
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            run_id = os.environ.get("ATPROTO_SCENARIO_RUN_ID", "default")
            har_path = f"/tmp/garazyk-atproto-e2e/{run_id}/diagnostics/oauth_flow.har"
            os.makedirs(os.path.dirname(har_path), exist_ok=True)
            context = await browser.new_context(record_har_path=har_path)
            page = await context.new_page()

            page.on("pageerror", lambda err: print(f"BROWSER PAGE ERROR: {err}"))
            page.on("console", lambda msg: print(f"BROWSER CONSOLE [{msg.type}]: {msg.text}") if msg.type in ["error", "warning", "log", "info"] else None)

            all_requests = []
            def log_request(request):
                entry = {"method": request.method, "url": request.url, "headers": dict(request.headers)}
                all_requests.append(entry)
                print(f"[NET REQ] {request.method} {request.url}")
            page.on("request", log_request)

            def log_response(res):
                print(f"[NET RES] {res.status} {res.url} CT={res.headers.get('content-type', 'N/A')}")
            page.on("response", log_response)

            def log_request_failed(request):
                print(f"[NET FAIL] {request.method} {request.url} failure={request.failure}")
            page.on("requestfailed", log_request_failed)

            import urllib.parse
            async def on_navigate(frame):
                url = frame.url
                if "/oauth/authorize" in url or "/callback" in url:
                    parsed = urllib.parse.urlparse(url)
                    params = urllib.parse.parse_qs(parsed.query)
                    print(f"[OAUTH REDIRECT] To: {parsed.path} | Params: {params}")
            page.on("framenavigated", on_navigate)

            await page.goto("http://127.0.0.1:8080")
            result.step_passed("Step 1: Navigate to client app")

            await page.fill("#handle", luna.handle)
            await page.click("#login-btn")
            result.step_passed("Step 2: Initiate login flow & Resolve Handle")

            try:
                await page.wait_for_selector("#auth-handle", timeout=30000)
                result.step_passed("Step 3: Redirected to PDS authorize page (PAR completed)")
            except Exception as exc:
                screenshot_path = f"/tmp/oauth_failure_{int(time.time())}.png"
                await page.screenshot(path=screenshot_path)
                content_path = f"/tmp/oauth_failure_{int(time.time())}.html"
                with open(content_path, "w") as f:
                    f.write(await page.content())

                print(f"[DIAG] All network requests ({len(all_requests)}):")
                for req in all_requests:
                    print(f"  {req['method']} {req['url']}")

                import subprocess
                print("[DIAG] PDS Docker Logs (tail):")
                try:
                    proj = os.environ.get("ATPROTO_E2E_COMPOSE_PROJECT", "garazyk-e2e")
                    pds_logs = subprocess.run(
                        ["docker", "compose", "-p", proj, "logs", "local-pds", "--tail", "50"],
                        capture_output=True, text=True, timeout=5)
                    if pds_logs.stdout:
                        print(pds_logs.stdout)
                    else:
                        print(f"(No logs found for project {proj})")
                        fallback = subprocess.run(["docker", "ps", "--filter", "name=local-pds", "--format", "{{.Names}}"],
                                                  capture_output=True, text=True)
                        if fallback.stdout:
                            cname = fallback.stdout.strip().split('\n')[0]
                            print(f"Trying fallback logs for container: {cname}")
                            flogs = subprocess.run(["docker", "logs", "--tail", "50", cname],
                                                   capture_output=True, text=True)
                            print(flogs.stdout)
                except Exception as log_exc:
                    print(f"Could not fetch PDS logs: {log_exc}")

                result.step_failed("Redirected to PDS authorize page",
                                   f"Timeout waiting for #auth-handle. Screenshot: {screenshot_path}, HTML: {content_path}. Error: {str(exc)}")
                await browser.close()
                result.finish()
                return result

            await page.fill("#auth-handle", luna.handle)
            await page.fill("#auth-password", luna.password)
            await page.click("#auth-signin-btn")
            result.step_passed("PDS Sign-in successful")

            await page.wait_for_selector("button[type='submit'].btn-primary", timeout=5000)
            await page.click("button[type='submit'].btn-primary")
            result.step_passed("Consent granted")

            await page.wait_for_selector("#profile", timeout=10000)

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
