"""Scenario 28: "Repo Format Benchmarks" — CAR vs STAR Performance Comparison

Benchmarks the com.atproto.sync.getRepo XRPC endpoint across three
serialization formats: CAR, STAR-L0, and STAR-Lite.
Measures latency and archive size for each format after seeding a
significant number of records.

Services: PDS
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, ScenarioResult, timed_call


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def run() -> ScenarioResult:
    result = ScenarioResult("Repo Format Benchmarks")
    result.start()

    client = XrpcClient(PDS1)

    timed_call(result, "Server health check",
               lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    # 1. Setup bench user
    bench_user = get_character("luna") # Reuse luna for simplicity or define new
    session = timed_call(
        result, f"Login/Create bench user: {bench_user.handle}",
        lambda: client.accounts.create_account(bench_user.handle, bench_user.email, bench_user.password),
        skip_on_status={400}, # Assume already exists if 400 (handle taken)
    )
    
    if not session:
        # Try login if create failed
        session = timed_call(
            result, "Login bench user",
            lambda: client.accounts.create_session(bench_user.handle, bench_user.password)
        )

    if not session:
        result.step_failed("Setup", "Failed to obtain session for bench user")
        result.finish()
        return result

    bench_user.did = session["did"]
    bench_user.access_jwt = session["accessJwt"]

    # 2. Seed records (approx 500 posts for meaningful comparison)
    POST_COUNT = 500
    existing = client.records.list_records(bench_user.did, "app.bsky.feed.post", limit=1, token=bench_user.access_jwt)
    current_count = len(existing.get("records", []))
    
    if current_count < 100: # Seed if repo is relatively small
        print(f"Seeding {POST_COUNT} posts...")
        for i in range(POST_COUNT):
            client.records.create_record(
                bench_user.did, "app.bsky.feed.post",
                {"$type": "app.bsky.feed.post",
                 "text": f"Benchmark seeding post #{i}. Testing CAR vs STAR efficiency at scale.",
                 "createdAt": _now()},
                bench_user.access_jwt,
            )
        result.step_passed("Seeding", f"Created {POST_COUNT} posts")
    else:
        result.step_skipped("Seeding", f"Repo already has records (approx {current_count}+)")

    # 3. Benchmark Loop
    formats = [
        ("CAR", "application/vnd.ipld.car"),
        ("STAR-L0", "application/vnd.atproto.star"),
        ("STAR-Lite", "application/vnd.atproto.star-lite"),
    ]
    
    benchmark_results = {}

    for label, mime in formats:
        print(f"Benchmarking {label} ({mime})...")
        
        # Warmup
        client.raw.xrpc_get_binary(
            "com.atproto.sync.getRepo", 
            {"did": bench_user.did}, 
            token=bench_user.access_jwt,
            headers={"Accept": mime}
        )
        
        iterations = 5
        total_ms = 0
        sizes = []
        
        for i in range(iterations):
            step_name = f"Fetch {label} (Iter {i+1})"
            resp = timed_call(
                result, step_name,
                lambda m=mime: client.raw.xrpc_get_binary(
                    "com.atproto.sync.getRepo", 
                    {"did": bench_user.did}, 
                    token=bench_user.access_jwt,
                    headers={"Accept": m}
                ),
                detail_fn=lambda r: f"bytes={len(r[2])} ct={r[1]}"
            )
            if resp:
                status, ct, body = resp
                
                # Format Verification
                if mime not in ct and label != "CAR":
                     result.step_failed(f"Format Verification ({label})", f"Requested {mime}, got {ct}")
                
                # Integrity Check (Magic Byte 0x2A for STAR)
                if label != "CAR" and len(body) > 0:
                    if body[0] != 0x2A:
                        result.step_failed(f"Integrity Check ({label})", f"Invalid magic byte: 0x{body[0]:02X}")
                
                # Record duration from result
                for step in result.steps:
                    if step.name == step_name:
                        total_ms += step.duration_ms
                        break
                sizes.append(len(body))
        
        avg_ms = total_ms / iterations
        avg_size = sum(sizes) / iterations
        benchmark_results[label] = {"avg_ms": avg_ms, "avg_size": avg_size}

    # 4. Reporting
    print("\n" + "="*40)
    print(f"{'Format':<10} | {'Avg Latency':<12} | {'Avg Size':<12}")
    print("-" * 40)
    for label, data in benchmark_results.items():
        print(f"{label:<10} | {data['avg_ms']:>10.2f}ms | {data['avg_size']/1024:>10.2f}KB")
    print("="*40 + "\n")

    result.record_artifact("benchmark_summary", benchmark_results)
    result.finish()
    return result


if __name__ == "__main__":
    res = run()
    res.print_summary()
    sys.exit(res.exit_code)
