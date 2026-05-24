# Replica Sync

## Backfill And Streaming Flow

1. Fetch `/export?after=<seq>&count=<n>` for initial backfill and catch-up.
2. Parse each line as `type:"sequenced_op"` with `seq`, `did`, `operation`, `cid`, and `createdAt`.
3. Use upstream `createdAt` as the auditor proposed date.
4. Persist upstream `seq` only after validation and durable append.
5. Advance cursor after the whole batch succeeds.
6. Tail `/export/stream?cursor=<lastSeq>` for live updates.
7. On `ConsumerTooSlow`, reconnect through paginated catch-up before streaming again.
8. On `FutureCursor`, stop and surface an operator error.

## Failure Handling

- Malformed JSONL fails the full batch.
- Non-monotonic sequence regression is rejected.
- Duplicate `(did,cid)` follows the store policy and must not advance cursor unless already durably present with compatible metadata.
- Replica append notifies the export stream hub after success.

## Mini-Prompts

- Trace one recovery operation through auditor, store, export, replica ingest, and DID resolution; confirm nullified CIDs are inactive but auditable.

