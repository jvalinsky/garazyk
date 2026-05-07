# Detailed Documentation Overhaul Scratchpad

## Phase 1: Foundation & Infrastructure (Node 889)
- [ ] Update `docs/03-application-layer/` for microservice split (Chat, Admin UI).
- [ ] Update `docs/09-platform-compatibility/` for VitePress migration details.
- [ ] Document `PDSCloudStorageBlobProvider` (S3/CDN).
- [ ] Verify microservice boundaries.

## Phase 2: Network & API (Node 890)
- [ ] Document moderation migration (`com.atproto.admin` -> `tools.ozone`).
- [ ] Cleanup legacy endpoints in `docs/04-network-layer/` and `docs/11-reference/api-reference.md`.
- [ ] Add OAuth2/DPoP endpoint details.
- [ ] Run `atproto-coverage-audit`.

## Phase 3: Data & Storage (Node 891)
- [ ] Document migrations V5-V8 in `docs/05-database-layer/`.
- [ ] Document FTS5 search schema and `OzoneSubjectsSchema`.
- [ ] Run `sqlite-sql-best-practices` audit.

## Phase 4: Tutorials & User Guides (Node 892)
- [ ] Cross-reference Tutorial 10 in `tutorial-2-accounts.md` and `tutorial-4-auth.md`.
- [ ] Review all tutorials for pattern consistency.
- [ ] Dry-run tutorials.

## Phase 5: Quality Assurance (Node 893)
- [ ] Run `python3 scripts/test-doc-links.py`.
- [ ] Update `GLOSSARY.md` and `index.md`.
- [ ] Final copy audit (Skills: `clarify`, `polish`).
- [ ] Build docs: `./scripts/build/build-docs.sh`.
