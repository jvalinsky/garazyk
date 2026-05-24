# Spec Map

## did:plc v0.3 Requirements

| Requirement | Current Code Area | Intended Fix |
| --- | --- | --- |
| Genesis operations include `prev: null` in JSON and DAG-CBOR signing/hashing input. | `PLCOperation` serialization and parsing | Preserve explicit nulls for regular and legacy genesis operations; keep metadata out of signed operation dictionaries. |
| Maximum DAG-CBOR operation size is 7500 bytes. | Auditor and operation validation | Move to shared PLC constants and enforce through the auditor. |
| `/export` without `after` returns legacy timestamp JSONL. | `PLCServer` export handler | Keep compatibility mode and include `nullified`. |
| `/export?after=<integer>` returns `sequenced_op` JSONL ordered by increasing `seq`. | `PLCServer`, store export queries | Add `seq`, integer cursor parsing, and sequenced export wire shape. |
| `/export?after=<timestamp>` remains legacy compatibility mode. | `PLCServer`, store export queries | Validate ISO timestamps and keep timestamp-ordered rows. |
| `/export/stream` streams sequenced entries over WebSocket. | `PLCServer`, `PLCReplicaServer`, sync engine | Add stream route and notify subscribers after local or replica appends. |
| `/\:did/log/audit` returns complete audit history including nullified operations. | `PLCServer`, store log queries | Add audit route while keeping legacy `/log` and `/log/last`. |
| `verificationMethods` can be any syntactically valid `did:key`. | Operation validation | Validate syntax separately from rotation-key curve support. |

## Mini-Prompts

- Compare `/export`, `/export?after=0`, `/export?after=<timestamp>`, and `/export/stream` against https://web.plc.directory/spec/v0.1/did-plc.
- Review every code path that serializes an operation; confirm signed DAG-CBOR data preserves `prev:null`.

