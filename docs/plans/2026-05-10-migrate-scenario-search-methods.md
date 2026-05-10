# Migrate Scenario Search Methods Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update scenarios to use `SearchClient` for actor preferences, suggestions, and typeahead search, reflecting the reorganization of client methods.

**Architecture:** Methods that interact with `app.bsky.actor.*` (except `getProfile` and `searchActors`) have been moved from `FeedClient` to `SearchClient`. Scenarios must be updated to call these via `client.search` instead of `client.feed`.

**Tech Stack:** Python, ATProto XRPC Client.

### Task 1: Update Scenario 17

**Files:**
- Modify: `scripts/scenarios/scenarios/17_actor_preferences_discovery.py`

**Step 1: Replace `client.feed.get_preferences`**
- Line 97: Replace `client.feed.get_preferences` with `client.search.get_preferences`.

**Step 2: Replace `client.feed.search_actors_typeahead`**
- Line 212: Replace `client.feed.search_actors_typeahead` with `client.search.search_actors_typeahead`.

**Step 3: Replace `client.feed.get_suggestions`**
- Line 266: Replace `client.feed.get_suggestions` with `client.search.get_suggestions`.

**Step 4: Verify changes**
- Run: `python3 scripts/scenarios/scenarios/17_actor_preferences_discovery.py` (Note: This might require a running local stack if health checks are enabled, but the code change is straightforward).
- Expected: No syntax errors; calls use the correct client object.

**Step 5: Commit**

```bash
git add scripts/scenarios/scenarios/17_actor_preferences_discovery.py
git commit -m "refactor: update scenario 17 to use SearchClient for actor methods"
```

### Task 2: Final Grep Verification

**Step 1: Search for any remaining incorrect usages**
- Run: `grep -rE "client\.feed\.(get_preferences|put_preferences|get_suggestions|search_actors_typeahead)" scripts/scenarios/scenarios/`
- Expected: No results.
