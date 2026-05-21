# Sub-plan: 39 — List Management XRPC Handlers

## Problem
Two AppView XRPC endpoints return 404:
- `app.bsky.graph.getLists` — No handler
- `app.bsky.graph.getList` — No handler

## Background
GraphService already has list indexing methods (`indexList`, `indexListitem`, `unindexListWithURI`, `unindexListitemWithURI`) and a `bsky_graph_lists` table, but **no query methods** for reading lists.

## Work

### 1. Add service methods to GraphService
Add `getListsForActor:limit:cursor:error:` and `getList:limit:cursor:error:` following the existing pattern in `GraphService.m`:

- `getListsForActor:` — Query `bsky_graph_lists` WHERE did = actorDID
- `getList:` — Query `bsky_graph_listitems` WHERE list_uri = listURI, JOIN with actor profiles

Follow existing patterns from `getFollowsForActor:` or `getStarterPacksForActor:`.

### 2. Register XRPC handlers in AppViewXRpcRoutePack
Add GET route registrations in `AppViewXRpcRoutePack.m` → `registerRoutesWithServer:`
- `GET /xrpc/app.bsky.graph.getLists` → `GraphService.getListsForActor:`
- `GET /xrpc/app.bsky.graph.getList` → `GraphService.getList:`

Follow the pattern of existing route registrations (e.g., `getFollows`, `getStarterPacks`).

### 3. Check lexicon output shapes
Verify the response format matches:
- `lexicons/app/bsky/graph/getLists.json`
- `lexicons/app/bsky/graph/getList.json`

## Files
- `Garazyk/Sources/AppView/Services/GraphService.m`
- `Garazyk/Sources/AppView/Services/GraphService.h`
- `Garazyk/Sources/Network/AppViewXRpcRoutePack.m`
- `lexicons/app/bsky/graph/getLists.json`
- `lexicons/app/bsky/graph/getList.json`

## Verification
```bash
nix develop -c bash -c "cd scripts/scenarios && deno run -A e2e_runner.ts --scenario 39"
```
