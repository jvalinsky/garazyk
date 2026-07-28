---
phase: 27
title: Chat (syrena-chat) trust-boundary sweep
status: drafted
agent: worker
depends_on: []
---

# Phase 27: Chat trust-boundary sweep

## Mission

Close the 6 findings in workstream 01 § S15: widespread missing isKindOfClass
guards on XRPC handler body extractions (C1), an unconditional convo
availability stub (C2), a legacy token verification bypass (C3), missing
membership checks on conversation state-change handlers (C4),
unvalidated reaction targets (C5), and unguarded per-element validation
in message batches (C6).

This is the S8/S13 defect class reapplied to the Chat trust boundary:
every handler in `XrpcChatBskyConvoPack`, `XrpcChatBskyActorPack`, and
`XrpcChatBskyGroupPack` that reads from `request.jsonBody` without an
`isKindOfClass:` guard can receive a non-string where a string is
expected, storing an NSDictionary or NSNumber in an NSString* variable.
The failure surfaces later as an unrecognized selector — process abort.
Slice 1 (isKindOfClass sweep) is the highest-priority slice and was
executed first (committed at `2e1c6321`).

Scope: `Garazyk/Sources/Network/XrpcChatBskyConvoPack.m` (1,079 lines),
`XrpcChatBskyActorPack.m` (163 lines), `XrpcChatBskyGroupPack.m` (767
lines), `Garazyk/Sources/Chat/Server/ChatAuthManager.m` (auth path),
and `Garazyk/Sources/Chat/Server/Services/ChatService.m` (2,800+ lines
total across Chat module).

## Read first

- `docs/plans/workstreams/01-security-and-protocol-correctness.md` § S15
  (authoritative; if this prompt disagrees, the workstream wins)
- `Garazyk/Sources/Network/XrpcChatBskyConvoPack.m` — all body-extraction
  sites (search for `body[@"`), `getConvoAvailability` handler at :355,
  `sendMessage` at :835, `sendMessageBatch` at :620, membership check at
  :540
- `Garazyk/Sources/Network/XrpcChatBskyActorPack.m` — `updateActorAccess`
  handler (actor extraction)
- `Garazyk/Sources/Network/XrpcChatBskyGroupPack.m` — `deleteGroup`,
  `enableJoinLink` handlers (remaining unguarded sites after slice 1)
- `Garazyk/Sources/Chat/Server/ChatAuthManager.m` — `:388`
  `validateLegacyPDSToken` (the sub-claim trust bypass), `:87,108`
  (unchecked JWT claims before signature verification)
- `Garazyk/Sources/Chat/Server/Services/ChatService.m` —
  `acceptConversation:`, `leaveConversation:`, `muteConversation:`,
  `unmuteConversation:`, `lockConversation:`, `unlockConversation:`
  (state-change methods that currently lack membership verification),
  `addReaction:`/`removeReaction:` (no conversation membership check)
- ADR 0013 (claim type mismatch decisions from S8 — same rejection
  pattern applies to Chat's JWT claim typing)

## Decisions already taken (do not re-litigate)

- **Slice 1 (isKindOfClass sweep) is already executed.** Committed at
  `2e1c6321` — ~19 sites across ConvoPack (convoId, messageId, emoji,
  message dict, messages array), ActorPack (actor), and GroupPack
  (deleteGroup groupUri, enableJoinLink linkId). This prompt covers
  slices 2-7.
- **Non-string body fields are rejected with 400, not coerced.** Same
  policy as ADR 0013 for auth boundaries: an `isKindOfClass:` mismatch
  on a required field produces a validation error, not a silent coercion.
- **Membership verification follows the existing pattern.** The
  `sendMessage`/`sendMessageBatch` handlers already call
  `XrpcChatConversationIncludesActor` and return 403 on non-members.
  All other state-change handlers should follow this pattern, not
  invent a new one.
- **getConvoAvailability respects chat.bsky.actor.declaration.**
  The `allowIncoming` preference (`all`/`none`/`following`) is already
  read by `getConvoForMembers` via `XrpcChatAllowIncomingForDIDFromRepo`.
  `getConvoAvailability` should use the same helper, not return
  unconditional `YES`.

## Scope and order

Slices 2-7 are ordered so each is independently shippable. Slice 1 is
already committed.

2. **getConvoAvailability hardening (C2).** Replace the unconditional
   `available: @YES` at `XrpcChatBskyConvoPack.m:355` with a lookup of
   the target DID's `chat.bsky.actor.declaration` record via
   `XrpcChatAllowIncomingForDIDFromRepo`. Return `available: @NO` when
   `allowIncoming` is `"none"`. This requires threading `recordService`
   and `authHeader` into the handler (follow the same pattern as
   `getConvoForMembers` at :230-260).

3. **Legacy token hardening (C3).** In
   `ChatAuthManager.m validateLegacyPDSToken`, when `pdsUrl` is nil:
   instead of returning `jwt.payload.sub` unverified, return `nil`.
   Add a log warning so operators know legacy token auth is disabled
   without a configured PDS URL.

4. **Membership verification parity (C4).** Add
   `XrpcChatConversationIncludesActor` checks to six handlers:
   `acceptConvo`, `leaveConvo`, `muteConvo`, `unmuteConvo`,
   `lockConvo`, `unlockConvo`. Each must fetch the conversation,
   verify the authenticated actor is a member, and return 403 if not.
   The `sendMessage` handler at :540 is the reference implementation.

5. **addReaction/removeReaction conversation membership (C5).** These
   handlers accept `messageId` and `emoji` but never verify the actor
   is a member of the conversation the message belongs to. Add a
   lookup: get the message's `convoId`, get the conversation, verify
   membership, return 403 on non-member.

6. **sendMessageBatch per-element validation (C6).** In the
   `sendMessageBatch` handler, each element of the `messages` array
   must be validated: `isKindOfClass:[NSDictionary class]`, the
   `text` field must be `isKindOfClass:[NSString class]` and
   non-empty. Invalid elements should be rejected with a 400, not
   silently skipped.

7. **Acceptance gate tests (C1-C6).** Add tests covering all six
   findings:
   - Non-string `convoId`/`messageId`/`emoji` returns 400
   - Non-member cannot mute/unmute/lock/unlock/accept/leave (403)
   - Non-member cannot add/remove reactions (403)
   - `getConvoAvailability` returns `available: @NO` when
     `allowIncoming: "none"`
   - Legacy token without PDS URL returns 401
   - `sendMessageBatch` with a non-dict or text-free element returns 400
   - All existing Chat tests continue to pass

## Acceptance gate

Per-slice negative tests are the gate — every finding here produces
a rejection path:

**Slice 2:**
- `getConvoAvailability?did=<did>` returns `{available: false}` when
  the target DID's `chat.bsky.actor.declaration` has
  `allowIncoming: "none"`.
- Returns `{available: true}` when `allowIncoming: "all"` or no
  declaration exists (fail-open for availability).

**Slice 3:**
- Legacy token with no `pdsUrl` configured returns 401.
- Legacy token with valid `pdsUrl` still works (no regression).

**Slice 4:**
- Non-member `acceptConvo` returns 403.
- Non-member `leaveConvo` returns 403.
- Non-member `muteConvo` returns 403.
- Non-member `unmuteConvo` returns 403.
- Non-member `lockConvo` returns 403.
- Non-member `unlockConvo` returns 403.
- Member can still perform all six operations (no regression).

**Slice 5:**
- Non-member `addReaction` returns 403.
- Non-member `removeReaction` returns 403.
- Member can still add/remove reactions (no regression).

**Slice 6:**
- `sendMessageBatch` with `messages: [123]` (non-dict) returns 400.
- `sendMessageBatch` with `messages: [{}]` (no text) returns 400.
- `sendMessageBatch` with valid messages still works (no regression).

**Slice 7:**
- All six rejection scenarios above are tested.
- Existing Chat test suites pass.

New suites need their header imported and the class registered in
`Garazyk/Tests/test_main.m` plus a cmake reconfigure, or they silently
run zero tests. Build `AllTests` with bounded parallelism (`-j4`).

```bash
deno task check && deno task lint && deno task test
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests --gated=run
```

## Rollback

Each slice is a single-commit revert. Slice 4 (membership verification
parity) is the highest operational risk — if an existing client relies
on muting/leaving conversations it is not a member of, revert and
capture the client's actual behavior as a test case. Slice 2 changes
`getConvoAvailability` from unconditional YES to a real preference
lookup — any client that relied on the stub returning YES will see
`available: false` for recipients who have set `allowIncoming: "none"`.
Slice 3 could break automation that uses legacy tokens without a
configured `pdsUrl` — operators should set `pdsUrl` in config before
deploying.

## On completion

Update S15 status in workstream 01 with commit hashes, then set
`status: complete` in this prompt's front matter.
