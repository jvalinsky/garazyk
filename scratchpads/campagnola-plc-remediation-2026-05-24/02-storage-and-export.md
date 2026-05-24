# Storage And Export

## Schema Notes

- Add nullable `seq INTEGER` to `plc_operations`.
- Preserve upstream or locally accepted `created_at` in milliseconds.
- Add unique indexes for `seq` and `(did, cid)`.
- Backfill existing rows with `seq = id`.
- Keep `seq`, `createdAt`, `cid`, and `nullified` as metadata outside authenticated operation data.

## Export Wire Shapes

Legacy JSONL:

```json
{"operation":{},"did":"did:plc:...","cid":"...","createdAt":"YYYY-MM-DDTHH:mm:ss.sssZ","nullified":false}
```

Sequenced JSONL:

```json
{"type":"sequenced_op","operation":{},"did":"did:plc:...","cid":"...","createdAt":"YYYY-MM-DDTHH:mm:ss.sssZ","seq":1}
```

## Cursor Rules

- Missing `after`: legacy export.
- Integer `after`: sequence export, entries where `seq > after`.
- Timestamp `after`: legacy export, entries after timestamp.
- Invalid `after` or `count`: HTTP 400.
- Default count: 10.
- Maximum count: 1000.

## Rollback Notes

The migration is in-place. Operational rollback is database backup restore before migration. Inserts and nullification updates must share one SQL transaction so partial recovery state is not committed.

