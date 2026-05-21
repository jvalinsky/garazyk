# Sub-plan: 43 — Multi-Device Session Management

## Problem
Deleting one session revokes all sessions. The scenario:
1. Creates two sessions for same account (device 1, device 2)
2. Deletes device 1 session
3. Expects device 2 session to still be valid
4. Gets `ExpiredToken` — device 2 session was also revoked

## Root Cause
`com.atproto.server.deleteSession` likely revokes all sessions for the DID instead of targeting a specific session token/ID.

## Work

### 1. Audit current session management
- Find how sessions are stored (DB table: `sessions`? `auth_sessions`?)
- Find how `deleteSession` is implemented
- Check if sessions are identified by a unique token/ID per device

### 2. Identify scope of revocation
- Current behavior likely: `DELETE FROM sessions WHERE did = ?`
- Desired behavior: `DELETE FROM sessions WHERE id = ?` (one specific session)

### 3. Implement per-device session ID
- If sessions don't have unique IDs, add a `device_id` or `session_id` column
- The deleteSession request needs to identify which session to revoke (by token or device ID)
- Store device info during token creation (`createSession` or `refreshSession`)

### 4. Update deleteSession handler
- Change `deleteSession` to accept a session identifier
- Only revoke the matching session, not all sessions for the DID

## Files
- `scripts/scenarios/scenarios/43_multi_device_sessions.ts` (scenario)
- `Garazyk/Sources/Auth/` (session management)
- `Garazyk/Sources/Network/XrpcServerPack.m` (deleteSession handler)
- Database schema (sessions table)
- `Garazyk/Sources/Database/` (session queries)

## Verification
```bash
nix develop -c bash -c "cd scripts/scenarios && deno run -A e2e_runner.ts --scenario 43"
```
