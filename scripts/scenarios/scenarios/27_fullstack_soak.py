"""Scenario 27: full-stack soak test.

Runs a 120-second mixed workload across PDS, Relay, and AppView while
tracking Prometheus metrics, process health, storage growth, operation
latency, and CPU usage.
"""

from __future__ import annotations

import os
import random
import sys
import threading
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

import psutil

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, PDS1, ScenarioResult, get_character, timed_call
from scripts.lib.atproto.characters import Character
from scripts.lib.atproto.config import APPVIEW_ADMIN_SECRET, SERVICE_URLS
from scripts.lib.atproto.diagnostics import create_run_context
from scripts.lib.atproto.instrumentation import (
    CpuProfiler,
    InstrumentationReport,
    OperationStats,
    OperationTimer,
    PhaseTimer,
    ProcessMonitor,
    PrometheusScraper,
    StorageMonitor,
)


WORKLOAD_SECONDS = 120.0
WORKER_COUNT = 10
POSTS_PER_ACCOUNT = 5
FOLLOWS_PER_ACCOUNT = 3

WRITE_LATENCY_THRESHOLD_NS = 1_000_000_000  # 1s
READ_LATENCY_THRESHOLD_NS = 500_000_000  # 500ms
RSS_GROWTH_THRESHOLD_PCT = 20.0

COLLECTIONS = [
    "app.bsky.actor.profile",
    "app.bsky.feed.post",
    "app.bsky.feed.like",
    "app.bsky.graph.follow",
]

WORKLOAD_WRITE_OPS = ["create_post", "create_like", "follow", "unfollow", "update_profile"]
WORKLOAD_READ_OPS = ["get_timeline", "list_notifications"]


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _make_soak_character(index: int) -> Character:
    return Character(
        name=f"Soak {index}",
        handle=f"soak-{index}.test",
        email=f"soak-{index}@test.local",
        password=f"soak_pass_{index}",
        persona=f"High-volume soak test account {index}",
        role="user",
        pds_url=PDS1,
    )


def _measure_call(timer: OperationTimer, op_name: str, fn):
    with timer.measure(op_name):
        return fn()


def _merge_operation_stats(target: dict[str, OperationStats], source: dict[str, OperationStats]) -> None:
    for name, stat in source.items():
        if name not in target:
            target[name] = OperationStats(name=name)
        target[name].count += stat.count
        target[name]._durations_ns.extend(stat._durations_ns)


def run() -> ScenarioResult:
    result = ScenarioResult("Full-Stack Soak")
    result.start()

    client = XrpcClient(PDS1)
    relay_client = XrpcClient(SERVICE_URLS["relay"])
    appview_client = XrpcClient(SERVICE_URLS["appview"])
    admin_token = APPVIEW_ADMIN_SECRET

    pds_data_dir = os.environ.get("PDS_DATA_DIR", "/tmp/garazyk-atproto-e2e/pds-data")
    appview_data_dir = os.environ.get("APPVIEW_DATA_DIR", "/tmp/garazyk-atproto-e2e/appview")

    prometheus_scraper = PrometheusScraper(
        endpoints={
            "pds": f"{SERVICE_URLS['pds']}/metrics",
            "relay": f"{SERVICE_URLS['relay']}/api/relay/metrics",
            "appview": f"{SERVICE_URLS['appview']}/admin/appview/metrics/stats",
        },
        headers={"Authorization": f"Bearer {admin_token}"} if admin_token else None,
    )
    process_monitor = ProcessMonitor(
        service_names=["pds", "relay", "appview"],
        binary_names=["kaszlak", "zuk", "syrena"],
    )
    storage_monitor = StorageMonitor(
        paths={
            "pds": [
                os.path.join(pds_data_dir, "pds.db"),
                os.path.join(pds_data_dir, "pds.db-wal"),
            ],
            "appview": [
                os.path.join(appview_data_dir, "appview.db"),
                os.path.join(appview_data_dir, "appview.db-wal"),
            ],
        }
    )
    phase_timer = PhaseTimer()
    setup_timer = OperationTimer()
    verification_timer = OperationTimer()
    worker_timers = [OperationTimer() for _ in range(WORKER_COUNT)]

    prometheus_scraper.start()
    process_monitor.start()
    cpu_profiler = CpuProfiler(
        service_names=["pds", "relay", "appview"],
        processes=process_monitor._processes,
    )
    cpu_profiler.start()
    storage_monitor.start()

    expected_services = {"pds", "relay", "appview"}
    discovered_services = set(process_monitor._processes.keys())
    if discovered_services != expected_services:
        result.step_failed(
            "Process discovery",
            f"found={sorted(discovered_services)}, missing={sorted(expected_services - discovered_services)}",
        )
        return result

    accounts: list[Character] = []
    existing_names = ["luna", "marcus", "rosa", "volt", "quiet", "admin", "mod", "troll"]
    for name in existing_names:
        try:
            accounts.append(get_character(name))
        except KeyError:
            continue
    for index in range(1, 13):
        accounts.append(_make_soak_character(index))

    active_accounts: list[Character] = []
    display_names: dict[str, str] = {}
    profile_versions: dict[str, int] = defaultdict(int)
    following_by_did: dict[str, set[str]] = defaultdict(set)
    baseline_following_by_did: dict[str, set[str]] = defaultdict(set)
    liked_subjects_by_did: dict[str, set[tuple[int, int]]] = defaultdict(set)
    posts_created_by_did: dict[str, int] = defaultdict(int)
    post_pool: list[dict[str, Any]] = []
    scheduled_posts: list[dict[str, Any]] = []
    scheduled_post_index = 0
    pending_post_events: list[dict[str, Any]] = []
    setup_error_counts: dict[str, int] = defaultdict(int)
    workload_error_counts: dict[str, int] = defaultdict(int)
    state_lock = threading.Lock()
    phase_lock = threading.Lock()
    workload_started = False
    fatal_error: Exception | None = None

    def increment_error(counter: dict[str, int], op_name: str) -> None:
        with phase_lock:
            counter[op_name] += 1

    def measure_setup(op_name: str, fn, count_error: bool = True):
        try:
            return _measure_call(setup_timer, op_name, fn)
        except Exception:
            if count_error:
                increment_error(setup_error_counts, op_name)
            raise

    def measure_workload(timer: OperationTimer, op_name: str, fn, count_error: bool = True):
        try:
            return _measure_call(timer, op_name, fn)
        except Exception:
            if count_error:
                increment_error(workload_error_counts, op_name)
            raise

    def fetch_record(repo: str, collection: str, rkey: str, token: str) -> dict[str, Any] | None:
        try:
            return measure_setup(
                "verify_record_lookup",
                lambda: client.raw.xrpc_get(
                    "com.atproto.repo.getRecord",
                    {"repo": repo, "collection": collection, "rkey": rkey},
                    token=token,
                ),
                count_error=False,
            )
        except Exception:
            return None

    def list_records_page_pds(repo: str, collection: str, token: str, cursor: str | None = None) -> dict[str, Any]:
        params: dict[str, Any] = {"repo": repo, "collection": collection, "limit": 100}
        if cursor:
            params["cursor"] = cursor
        return measure_setup(
            "verify_pds_count",
            lambda: client.raw.xrpc_get("com.atproto.repo.listRecords", params, token=token),
        )

    def list_records_page_appview(collection: str, cursor: str | None = None, did: str | None = None) -> dict[str, Any]:
        params: dict[str, Any] = {"collection": collection, "limit": 100}
        if cursor:
            params["cursor"] = cursor
        if did:
            params["did"] = did
        return measure_setup(
            "verify_appview_count",
            lambda: appview_client.http_get("/admin/records", params=params, token=admin_token),
        )

    def count_records_pds(repo: str, collection: str, token: str) -> int:
        total = 0
        cursor: str | None = None
        while True:
            page = list_records_page_pds(repo, collection, token, cursor=cursor)
            records = page.get("records", [])
            total += len(records)
            cursor = page.get("cursor")
            if not cursor or not records:
                break
        return total

    def count_records_appview(collection: str) -> int:
        total = 0
        cursor: str | None = None
        while True:
            page = list_records_page_appview(collection, cursor=cursor)
            records = page.get("records", [])
            total += len(records)
            cursor = page.get("cursor")
            if not cursor or not records:
                break
        return total

    def count_records_appview_for_did(collection: str, did: str) -> int:
        total = 0
        cursor: str | None = None
        while True:
            page = list_records_page_appview(collection, cursor=cursor, did=did)
            records = page.get("records", [])
            total += len(records)
            cursor = page.get("cursor")
            if not cursor or not records:
                break
        return total

    def account_index(account: Character) -> int:
        return active_accounts.index(account)

    def build_profile_record(account: Character, version: int) -> dict[str, Any]:
        return {
            "$type": "app.bsky.actor.profile",
            "displayName": f"{account.name} (soak {version})",
            "description": account.persona,
        }

    def build_follow_rkey(follower_idx: int, target_idx: int) -> str:
        return f"follow-{follower_idx}-{target_idx}"

    def build_like_rkey(actor_idx: int, subject_author_idx: int, subject_slot_idx: int) -> str:
        return f"like-{actor_idx}-{subject_author_idx}-{subject_slot_idx}"

    def build_post_rkey(slot_idx: int) -> str:
        return f"soak-post-{slot_idx + 1}"

    def claim_due_post_event(now_ts: float) -> dict[str, Any] | None:
        nonlocal scheduled_post_index
        with state_lock:
            if pending_post_events:
                return pending_post_events.pop(0)
            if scheduled_post_index < len(scheduled_posts) and scheduled_posts[scheduled_post_index]["due_at"] <= now_ts:
                event = scheduled_posts[scheduled_post_index]
                scheduled_post_index += 1
                return event
        return None

    def create_post(event: dict[str, Any], timer: OperationTimer, worker_client: XrpcClient) -> bool:
        author = active_accounts[event["author_index"]]
        record = {
            "$type": "app.bsky.feed.post",
            "text": event["text"],
            "createdAt": _now(),
        }
        rkey = event["rkey"]
        try:
            response = measure_workload(
                timer,
                "create_post",
                lambda: worker_client.records.create_record(
                    author.did,
                    "app.bsky.feed.post",
                    record,
                    author.access_jwt,
                    rkey=rkey,
                ),
                count_error=False,
            )
        except Exception:
            recovered = fetch_record(author.did, "app.bsky.feed.post", rkey, author.access_jwt)
            if not recovered:
                increment_error(workload_error_counts, "create_post")
                return False
            response = recovered
        with state_lock:
            post_pool.append(
                {
                    "uri": response.get("uri", f"at://{author.did}/app.bsky.feed.post/{rkey}"),
                    "cid": response.get("cid", ""),
                    "author_index": event["author_index"],
                    "slot_index": event["slot_index"],
                    "author_did": author.did,
                    "rkey": rkey,
                }
            )
            posts_created_by_did[author.did] += 1
        return True

    def create_like(timer: OperationTimer, worker_client: XrpcClient, rng: random.Random) -> bool:
        for _ in range(12):
            with state_lock:
                if not post_pool:
                    return False
                actor = rng.choice(active_accounts)
                eligible_posts = [
                    post for post in post_pool
                    if post["author_did"] != actor.did
                    and (post["author_index"], post["slot_index"]) not in liked_subjects_by_did[actor.did]
                ]
                if not eligible_posts:
                    continue
                subject = rng.choice(eligible_posts)
                actor_idx = account_index(actor)
                subject_author_idx = subject["author_index"]
                subject_slot_idx = subject["slot_index"]
                rkey = build_like_rkey(actor_idx, subject_author_idx, subject_slot_idx)
                subject_uri = subject["uri"]
                subject_cid = subject["cid"]
            record = {
                "$type": "app.bsky.feed.like",
                "subject": {"uri": subject_uri, "cid": subject_cid},
                "createdAt": _now(),
            }
            try:
                measure_workload(
                    timer,
                    "create_like",
                    lambda: worker_client.records.create_record(
                        actor.did,
                        "app.bsky.feed.like",
                        record,
                        actor.access_jwt,
                        rkey=rkey,
                    ),
                    count_error=False,
                )
            except Exception:
                recovered = fetch_record(actor.did, "app.bsky.feed.like", rkey, actor.access_jwt)
                if not recovered:
                    increment_error(workload_error_counts, "create_like")
                    return False
            with state_lock:
                liked_subjects_by_did[actor.did].add((subject_author_idx, subject_slot_idx))
            return True
        return False

    def follow_random(timer: OperationTimer, worker_client: XrpcClient, rng: random.Random) -> bool:
        for _ in range(12):
            follower = rng.choice(active_accounts)
            follower_idx = account_index(follower)
            with state_lock:
                following = following_by_did[follower.did]
                candidates = [
                    candidate for candidate in active_accounts
                    if candidate.did != follower.did and candidate.did not in following
                ]
                if not candidates:
                    return False
                target = rng.choice(candidates)
                target_idx = account_index(target)
                rkey = build_follow_rkey(follower_idx, target_idx)
                record = {
                    "$type": "app.bsky.graph.follow",
                    "subject": target.did,
                    "createdAt": _now(),
                }
            try:
                measure_workload(
                    timer,
                    "follow",
                    lambda: worker_client.records.create_record(
                        follower.did,
                        "app.bsky.graph.follow",
                        record,
                        follower.access_jwt,
                        rkey=rkey,
                    ),
                    count_error=False,
                )
            except Exception:
                recovered = fetch_record(follower.did, "app.bsky.graph.follow", rkey, follower.access_jwt)
                if not recovered:
                    increment_error(workload_error_counts, "follow")
                    return False
            with state_lock:
                following_by_did[follower.did].add(target.did)
            return True
        return False

    def unfollow_random(timer: OperationTimer, worker_client: XrpcClient, rng: random.Random) -> bool:
        for _ in range(12):
            follower = rng.choice(active_accounts)
            follower_idx = account_index(follower)
            with state_lock:
                following = following_by_did[follower.did]
                baseline = baseline_following_by_did[follower.did]
                removable = [did for did in following if did not in baseline]
                if not removable:
                    continue
                target_did = rng.choice(removable)
                target_idx = next(i for i, account in enumerate(active_accounts) if account.did == target_did)
                rkey = build_follow_rkey(follower_idx, target_idx)
            try:
                measure_workload(
                    timer,
                    "unfollow",
                    lambda: worker_client.records.delete_record(
                        follower.did,
                        "app.bsky.graph.follow",
                        rkey,
                        follower.access_jwt,
                    ),
                    count_error=False,
                )
            except Exception:
                recovered = fetch_record(follower.did, "app.bsky.graph.follow", rkey, follower.access_jwt)
                if recovered:
                    increment_error(workload_error_counts, "unfollow")
                    return False
            with state_lock:
                following_by_did[follower.did].discard(target_did)
            return True
        return False

    def update_profile(timer: OperationTimer, worker_client: XrpcClient, rng: random.Random) -> bool:
        account = rng.choice(active_accounts)
        with state_lock:
            next_version = profile_versions[account.did] + 1
            new_display_name = f"{account.name} soak {next_version}"
        record = {
            "$type": "app.bsky.actor.profile",
            "displayName": new_display_name,
            "description": account.persona,
        }
        try:
            measure_workload(
                timer,
                "update_profile",
                lambda: worker_client.records.put_record(
                    account.did,
                    "app.bsky.actor.profile",
                    "self",
                    record,
                    account.access_jwt,
                ),
                count_error=False,
            )
        except Exception:
            recovered = fetch_record(account.did, "app.bsky.actor.profile", "self", account.access_jwt)
            if not recovered:
                increment_error(workload_error_counts, "update_profile")
                return False
        with state_lock:
            profile_versions[account.did] = next_version
            display_names[account.did] = new_display_name
        return True

    def get_timeline(timer: OperationTimer, worker_client: XrpcClient, rng: random.Random) -> bool:
        account = rng.choice(active_accounts)
        try:
            measure_workload(
                timer,
                "get_timeline",
                lambda: worker_client.feed.get_timeline(account.access_jwt, limit=50),
                count_error=False,
            )
        except Exception:
            increment_error(workload_error_counts, "get_timeline")
            return False
        return True

    def list_notifications(timer: OperationTimer, worker_client: XrpcClient, rng: random.Random) -> bool:
        account = rng.choice(active_accounts)
        try:
            measure_workload(
                timer,
                "list_notifications",
                lambda: worker_client.notifications.list_notifications(account.access_jwt, limit=50),
                count_error=False,
            )
        except Exception:
            increment_error(workload_error_counts, "list_notifications")
            return False
        return True

    def worker_loop(worker_id: int) -> dict[str, int]:
        worker_timer = worker_timers[worker_id]
        worker_client = XrpcClient(PDS1)
        rng = random.Random(0xC0FFEE + worker_id * 9973)
        local_counts: dict[str, int] = defaultdict(int)
        deadline = workload_start + WORKLOAD_SECONDS
        while time.time() < deadline:
            event = claim_due_post_event(time.time())
            if event is not None:
                if create_post(event, worker_timer, worker_client):
                    local_counts["create_post"] += 1
                time.sleep(0.1)
                continue

            with state_lock:
                has_like_candidate = bool(post_pool)
                has_follow_candidate = any(
                    any(candidate.did not in following_by_did[account.did] for candidate in active_accounts if candidate.did != account.did)
                    for account in active_accounts
                )
                has_unfollow_candidate = any(
                    len(following_by_did[account.did] - baseline_following_by_did[account.did]) > 0
                    for account in active_accounts
                )
            available_ops: list[tuple[str, int]] = [
                ("create_like", 4 if has_like_candidate else 0),
                ("follow", 3 if has_follow_candidate else 0),
                ("unfollow", 2 if has_unfollow_candidate else 0),
                ("update_profile", 2),
                ("get_timeline", 4),
                ("list_notifications", 3),
            ]
            choices = [name for name, weight in available_ops for _ in range(weight)]
            if not choices:
                time.sleep(0.1)
                continue
            op_name = rng.choice(choices)
            succeeded = False
            if op_name == "create_like":
                succeeded = create_like(worker_timer, worker_client, rng)
            elif op_name == "follow":
                succeeded = follow_random(worker_timer, worker_client, rng)
            elif op_name == "unfollow":
                succeeded = unfollow_random(worker_timer, worker_client, rng)
            elif op_name == "update_profile":
                succeeded = update_profile(worker_timer, worker_client, rng)
            elif op_name == "get_timeline":
                succeeded = get_timeline(worker_timer, worker_client, rng)
            elif op_name == "list_notifications":
                succeeded = list_notifications(worker_timer, worker_client, rng)
            if succeeded:
                local_counts[op_name] += 1
            time.sleep(0.1)
        return dict(local_counts)

    try:
        phase_timer.start_phase("Setup")

        timed_call(
            result,
            "PDS health check",
            lambda: measure_setup("health_check_pds", lambda: client.wait_for_healthy(timeout=30)),
        )
        if result.failed > 0:
            return result

        for account in accounts:
            session = timed_call(
                result,
                f"Create account: {account.name}",
                lambda c=account: measure_setup(
                    "setup_create_account",
                    lambda: client.accounts.create_account(c.handle, c.email, c.password),
                ),
                detail_fn=lambda s: f"did={s['did']}",
            )
            if session:
                account.did = session["did"]
                account.access_jwt = session["accessJwt"]
                active_accounts.append(account)
                display_names[account.did] = account.name

        if len(active_accounts) != len(accounts):
            result.step_failed("Account setup", f"created={len(active_accounts)}/{len(accounts)}")
            return result

        profile_created = 0
        for account in active_accounts:
            version = profile_versions[account.did] + 1
            profile_versions[account.did] = version
            record = build_profile_record(account, version)
            try:
                measure_setup(
                    "setup_create_profile",
                    lambda a=account, rec=record: client.records.put_record(
                        a.did,
                        "app.bsky.actor.profile",
                        "self",
                        rec,
                        a.access_jwt,
                    ),
                )
            except Exception as exc:
                result.step_failed("Profile setup", f"account={account.handle}: {exc}")
                return result
            profile_created += 1
        result.step_passed("Profile setup", f"created={profile_created}")

        total_follows = 0
        for idx, follower in enumerate(active_accounts):
            for offset in range(1, FOLLOWS_PER_ACCOUNT + 1):
                target = active_accounts[(idx + offset) % len(active_accounts)]
                record = {
                    "$type": "app.bsky.graph.follow",
                    "subject": target.did,
                    "createdAt": _now(),
                }
                rkey = build_follow_rkey(idx, (idx + offset) % len(active_accounts))
                try:
                    measure_setup(
                        "setup_follow",
                        lambda f=follower, rec=record, rk=rkey: client.records.create_record(
                            f.did,
                            "app.bsky.graph.follow",
                            rec,
                            f.access_jwt,
                            rkey=rk,
                        ),
                    )
                except Exception as exc:
                    result.step_failed(
                        "Social graph setup",
                        f"follower={follower.handle}, target={target.handle}: {exc}",
                    )
                    return result
                with state_lock:
                    following_by_did[follower.did].add(target.did)
                    baseline_following_by_did[follower.did].add(target.did)
                total_follows += 1
        result.step_passed(
            "Social graph setup",
            f"accounts={len(active_accounts)}, follows_per_account={FOLLOWS_PER_ACCOUNT}, total_follows={total_follows}",
        )

        workload_start = time.time() + 0.5
        slot_length = WORKLOAD_SECONDS / POSTS_PER_ACCOUNT
        for slot_idx in range(POSTS_PER_ACCOUNT):
            slot_start = workload_start + slot_idx * slot_length
            slot_end = slot_start + slot_length
            for account_idx, account in enumerate(active_accounts):
                due_at = random.uniform(slot_start + 2.0, slot_end - 4.0)
                scheduled_posts.append(
                    {
                        "due_at": due_at,
                        "author_index": account_idx,
                        "slot_index": slot_idx,
                        "rkey": build_post_rkey(slot_idx),
                        "text": f"Soak post {slot_idx + 1}/{POSTS_PER_ACCOUNT} from {account.name}",
                    }
                )
        scheduled_posts.sort(key=lambda item: item["due_at"])

        phase_timer.end_phase()

        phase_timer.start_phase("Sustained mixed workload")
        try:
            with ThreadPoolExecutor(max_workers=WORKER_COUNT) as executor:
                futures = [executor.submit(worker_loop, worker_id) for worker_id in range(WORKER_COUNT)]
                for future in as_completed(futures):
                    future.result()
        finally:
            phase_timer.end_phase()
        workload_started = True

        workload_summary = {
            "scheduled_post_events": len(scheduled_posts),
            "posts_created_by_account": dict(posts_created_by_did),
            "workload_errors": dict(workload_error_counts),
            "setup_errors": dict(setup_error_counts),
        }
        result.record_artifact("workload_summary", workload_summary)
        result.step_passed(
            "Sustained mixed workload",
            f"scheduled_posts={len(scheduled_posts)}, workers={WORKER_COUNT}, errors={sum(workload_error_counts.values())}",
        )

        phase_timer.start_phase("Consistency verification")
        expected_counts: dict[str, int] = {collection: 0 for collection in COLLECTIONS}
        observed_counts: dict[str, int] = {collection: 0 for collection in COLLECTIONS}
        deadline = time.time() + 30.0
        last_pds_counts: dict[str, int] = expected_counts.copy()
        last_appview_counts: dict[str, int] = observed_counts.copy()
        while time.time() < deadline:
            pds_counts = {
                "app.bsky.actor.profile": sum(
                    count_records_pds(account.did, "app.bsky.actor.profile", account.access_jwt)
                    for account in active_accounts
                ),
                "app.bsky.feed.post": sum(
                    count_records_pds(account.did, "app.bsky.feed.post", account.access_jwt)
                    for account in active_accounts
                ),
                "app.bsky.feed.like": sum(
                    count_records_pds(account.did, "app.bsky.feed.like", account.access_jwt)
                    for account in active_accounts
                ),
                "app.bsky.graph.follow": sum(
                    count_records_pds(account.did, "app.bsky.graph.follow", account.access_jwt)
                    for account in active_accounts
                ),
            }
            appview_counts = {
                collection: count_records_appview(collection)
                for collection in COLLECTIONS
            }
            last_pds_counts = pds_counts
            last_appview_counts = appview_counts
            if pds_counts == appview_counts:
                expected_counts = pds_counts
                observed_counts = appview_counts
                break
            time.sleep(1.0)
        else:
            result.step_failed(
                "Consistency verification",
                f"pds={last_pds_counts}, appview={last_appview_counts}",
            )
            phase_timer.end_phase()
            return result
        phase_timer.end_phase()
        result.step_passed("Consistency verification", f"counts={expected_counts}")

        quota_deadline = time.time() + 20.0
        last_quota_mismatches: list[str] = []
        while time.time() < quota_deadline:
            quota_mismatches: list[str] = []
            for account in active_accounts:
                pds_posts = count_records_pds(account.did, "app.bsky.feed.post", account.access_jwt)
                appview_posts = count_records_appview_for_did("app.bsky.feed.post", account.did)
                if pds_posts != POSTS_PER_ACCOUNT or appview_posts != POSTS_PER_ACCOUNT:
                    quota_mismatches.append(
                        f"{account.handle}: pds={pds_posts}, appview={appview_posts}, expected={POSTS_PER_ACCOUNT}"
                    )
            last_quota_mismatches = quota_mismatches
            if not quota_mismatches:
                break
            time.sleep(1.0)
        else:
            result.step_failed("Post quota verification", "; ".join(last_quota_mismatches[:5]))
            phase_timer.end_phase()
            return result
        result.step_passed(
            "Post quota verification",
            f"{len(active_accounts)} accounts x {POSTS_PER_ACCOUNT} posts",
        )

        phase_timer.start_phase("Resource cleanup")
        try:
            timed_call(
                result,
                "PDS final health check",
                lambda: measure_setup("health_check_pds", lambda: client.wait_for_healthy(timeout=10)),
            )
        except Exception:
            pass
        try:
            timed_call(
                result,
                "Relay health check",
                lambda: measure_setup(
                    "health_check_relay",
                    lambda: relay_client.http_get("/api/relay/health"),
                ),
                detail_fn=lambda r: f"keys={','.join(sorted(r.keys()))}",
            )
        except Exception:
            pass
        try:
            timed_call(
                result,
                "AppView health check",
                lambda: measure_setup(
                    "health_check_appview",
                    lambda: appview_client.http_get("/admin/ingest/health", token=admin_token),
                ),
                detail_fn=lambda r: f"keys={','.join(sorted(r.keys()))}",
            )
        except Exception:
            pass

        phase_timer.end_phase()
    except Exception as exc:
        fatal_error = exc
        result.step_failed("Unexpected scenario error", str(exc))
    finally:
        try:
            if phase_timer._current_phase:
                phase_timer.end_phase()
        except Exception:
            pass

        prometheus_stats = prometheus_scraper.stop()
        process_stats = process_monitor.stop()
        storage_stats = storage_monitor.stop()
        cpu_stats = cpu_profiler.stop()

        combined_operation_stats: dict[str, OperationStats] = {}
        _merge_operation_stats(combined_operation_stats, setup_timer.get_all_stats())
        _merge_operation_stats(combined_operation_stats, verification_timer.get_all_stats())
        for timer in worker_timers:
            _merge_operation_stats(combined_operation_stats, timer.get_all_stats())

        report = InstrumentationReport(
            operation_stats=combined_operation_stats,
            metrics_time_series=prometheus_stats,
            process_stats=process_stats,
            storage_stats=storage_stats,
            cpu_stats=cpu_stats,
            phase_timings=phase_timer.to_dict(),
        )

        result.record_artifact("instrumentation", report.to_dict())
        result.record_artifact(
            "final_counts",
            {
                "pds": last_pds_counts,
                "appview": last_appview_counts,
                "expected_posts_per_account": POSTS_PER_ACCOUNT,
                "accounts": [
                    {"name": account.name, "did": account.did, "handle": account.handle}
                    for account in active_accounts
                ],
            },
        )

        ctx = create_run_context()
        json_path = ctx.reports_dir / "27_fullstack_soak.json"
        html_path = ctx.reports_dir / "27_fullstack_soak.html"
        report.write_json(str(json_path))
        report.write_html(str(html_path), title="Scenario 27: Full-Stack Soak")
        result.step_passed("Resource cleanup", f"reports_written={json_path.name}, {html_path.name}")

        if workload_started and fatal_error is None:
            total_attempts = sum(stat.count for stat in combined_operation_stats.values())
            total_errors = sum(setup_error_counts.values()) + sum(workload_error_counts.values())
            error_rate = (total_errors / total_attempts * 100.0) if total_attempts else 0.0
            if total_attempts == 0:
                result.step_failed("Error rate", "No timed operations were recorded")
            elif error_rate < 1.0:
                result.step_passed("Error rate", f"{error_rate:.2f}% across {total_attempts} timed operations")
            else:
                result.step_failed("Error rate", f"{error_rate:.2f}% across {total_attempts} timed operations")

            write_ops = [combined_operation_stats.get(name) for name in WORKLOAD_WRITE_OPS]
            read_ops = [combined_operation_stats.get(name) for name in WORKLOAD_READ_OPS]
            if all(stat and stat.count > 0 for stat in write_ops):
                write_ok = all(stat.p95_ns < WRITE_LATENCY_THRESHOLD_NS for stat in write_ops if stat)
                if write_ok:
                    result.step_passed(
                        "Write latency",
                        ", ".join(f"{stat.name} p95={stat.p95_ns / 1e6:.1f}ms" for stat in write_ops if stat),
                    )
                else:
                    result.step_failed(
                        "Write latency",
                        ", ".join(f"{stat.name} p95={stat.p95_ns / 1e6:.1f}ms" for stat in write_ops if stat),
                    )
            else:
                result.step_failed("Write latency", "Not all workload write operations were observed")

            if all(stat and stat.count > 0 for stat in read_ops):
                read_ok = all(stat.p95_ns < READ_LATENCY_THRESHOLD_NS for stat in read_ops if stat)
                if read_ok:
                    result.step_passed(
                        "Read latency",
                        ", ".join(f"{stat.name} p95={stat.p95_ns / 1e6:.1f}ms" for stat in read_ops if stat),
                    )
                else:
                    result.step_failed(
                        "Read latency",
                        ", ".join(f"{stat.name} p95={stat.p95_ns / 1e6:.1f}ms" for stat in read_ops if stat),
                    )
            else:
                result.step_failed("Read latency", "Not all workload read operations were observed")

            for service_name, proc_stat in process_stats.items():
                if proc_stat.initial_rss == 0:
                    result.step_failed("RSS growth", f"{service_name}: no samples collected")
                    continue
                if proc_stat.rss_growth_pct <= RSS_GROWTH_THRESHOLD_PCT:
                    result.step_passed(
                        f"RSS growth: {service_name}",
                        f"{proc_stat.initial_rss} -> {proc_stat.final_rss} bytes ({proc_stat.rss_growth_pct:.1f}%)",
                    )
                else:
                    result.step_failed(
                        f"RSS growth: {service_name}",
                        f"{proc_stat.initial_rss} -> {proc_stat.final_rss} bytes ({proc_stat.rss_growth_pct:.1f}%)",
                    )

            for service_name, stat in storage_stats.items():
                if stat.final_db <= 0:
                    result.step_failed("Storage growth", f"{service_name}: database file missing")
                    continue
                if stat.final_wal <= stat.final_db * 2:
                    result.step_passed(
                        f"Storage growth: {service_name}",
                        f"db={stat.final_db} wal={stat.final_wal}",
                    )
                else:
                    result.step_failed(
                        f"Storage growth: {service_name}",
                        f"db={stat.final_db} wal={stat.final_wal}",
                    )
        else:
            result.step_skipped("Pass criteria", "Workload did not complete; skipping final thresholds")

        try:
            phase_timer.end_phase()
        except Exception:
            pass

        result.finish()

    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
