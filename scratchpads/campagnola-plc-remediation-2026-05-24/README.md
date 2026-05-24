# Campagnola PLC v0.3 Remediation

## Goal

Remediate Campagnola's PLC directory and replica behavior to match the did:plc v0.3 export and replica semantics while preserving authenticated operation bytes, hardening public defaults, and recording every phase in deciduous.

## Spec Links

- did:plc method spec v0.3.0: https://web.plc.directory/spec/v0.1/did-plc
- Review trail: deciduous nodes 958, 959, 960

## Deciduous Nodes

| Node | Purpose |
| --- | --- |
| 958 | Source review node |
| 959 | Source review node |
| 960 | Source outcome node |
| 961 | Remediation goal |
| 962 | Chosen sequence export option |
| 963 | Rejected legacy-only option |
| 964 | Rejected reference replacement option |
| 965 | Preserve legacy clients while making sequence mode canonical |
| 966 | Fix operation serialization and storage invariants |
| 967 | Implement export, audit log, and stream endpoints |
| 968 | Rework replica backfill and live sync |
| 969 | Harden validation, CORS, config, constants, and docs |
| 970 | Add conformance and regression tests |
| 971 | Verification outcome |

## Phase Status

| Phase | Status | Evidence |
| --- | --- | --- |
| Scratchpads and graph | Complete | Nodes 961-971, docs 262-267 |
| Spec map | Complete | `01-spec-map.md` |
| Storage and export | Complete | `02-storage-and-export.md`, `PLCStoreTests` |
| Replica sync | Complete | `03-replica-sync.md`, build coverage |
| Security, config, docs | Partial | `04-security-config-docs.md`; CORS/config/constants/parity covered, HeaderDoc cleanup remains broader debt |
| Tests and verification | Partial | `05-test-matrix.md`; focused PLC slices pass, module boundary check has unrelated existing failures |

## Final Acceptance Checklist

- [x] `/export?after=0` returns `sequenced_op` entries with increasing `seq`.
- [x] `/export/stream?cursor=<seq>` emits catch-up entries and then live entries.
- [x] Replica restart uses persisted sequence cursor.
- [x] Recovery appends and nullification are transactional in persistent storage.
- [x] Shared PLC operational constants are named and documented.
- [x] Deciduous graph links major phases to evidence and follow-up prompts.
