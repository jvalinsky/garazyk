# ADR 0027: `emitModerationEvent` Validates `$type` Against a Known Lexicon Set

**Status:** Accepted
**Date:** 2026-07-27

## Context

Workstream 01 S14 (phase-24 slice 5) identified an unvalidated `$type` field
in `ModerationService.m:38`. The `emitModerationEvent:` method extracts
`$type` from the event body and uses it as the `action` column in the
`moderation_events` table:

```objc
NSString *action = event[@"$type"] ?: @"tools.ozone.moderation.defs#modEventComment";
```

If `$type` is present, its value is used without any validation against the
known moderation event types defined in the lexicon. An attacker (or a buggy
client) can inject an arbitrary `$type` string, which:

1. **Pollutes the audit log.** The `action` column feeds into
   `admin_audit_log`, making it impossible to distinguish legitimate
   moderation actions from injected ones.

2. **Bypasses review-state transitions.** The review state is computed from
   `$type` — a fabricated type bypasses the expected state machine.

3. **Breaks downstream consumers.** Relay consumers and moderation dashboards
   that filter by `$type` are confused by unknown values.

The AT Protocol lexicon for `tools.ozone.moderation.emitEvent` defines a
closed set of event types. Accepting arbitrary strings violates the contract
and is the same class of bug as the XRPC method whitelist added in S8.

No alternative was considered — the fix is to validate `$type` against the
lexicon-defined set.

## Decision

1. **`emitModerationEvent:` validates `$type` against a known set.**
   If `$type` is present and is not one of the lexicon-defined event types,
   the method returns `nil` with an error `@"UnknownEventType"`. The known
   set is:

   - `tools.ozone.moderation.defs#modEventTakedown`
   - `tools.ozone.moderation.defs#modEventAcknowledge`
   - `tools.ozone.moderation.defs#modEventEscalate`
   - `tools.ozone.moderation.defs#modEventComment`
   - `tools.ozone.moderation.defs#modEventLabel`
   - `tools.ozone.moderation.defs#modEventReport`
   - `tools.ozone.moderation.defs#modEventMute`
   - `tools.ozone.moderation.defs#modEventUnmute`
   - `tools.ozone.moderation.defs#modEventMuteReporter`
   - `tools.ozone.moderation.defs#modEventUnmuteReporter`
   - `tools.ozone.moderation.defs#modEventReverseTakedown`
   - `tools.ozone.moderation.defs#modEventResolveAppeal`
   - `tools.ozone.moderation.defs#modEventTag`
   - `tools.ozone.moderation.defs#modEventUntag`

2. **The default `$type` is still `modEventComment` when absent.** The
   existing fallback — `?: @"tools.ozone.moderation.defs#modEventComment"` —
   is unchanged. Absent `$type` is valid; present-but-unknown `$type` is
   rejected.

3. **The known set is defined as a static `NSSet` for O(1) lookup.**
   The set is initialized once at class load time, avoiding per-request
   allocation.

4. **A test asserts unknown `$type` is rejected.**
   `testEmitModerationEventRejectsUnknownEventType` sends an event with
   `$type: "tools.ozone.moderation.defs#modEventFabricated"` and asserts
   a 400 response with `"UnknownEventType"`.

## Consequences

- **Audit log integrity.** Only lexicon-defined event types appear in the
  `action` column of `admin_audit_log`.

- **No valid event types are rejected.** The known set is derived from the
  published lexicon and includes all currently defined types.

- **Lexicon additions require a code change.** When the AT Protocol adds a
  new moderation event type, the static set must be updated. This is
  intentional — accepting unknown types silently is the defect this ADR
  fixes.

- **Rollback.** Revert the slice-5 commit to restore unvalidated `$type`
  acceptance. The unknown-type rejection test is removed with the revert.
