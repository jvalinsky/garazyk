# Scripts-to-Packages Refactor: Execution Log

## Goal
Move all TypeScript library logic from `scripts/` into proper JSR packages in `packages/`.
After refactor, `scripts/` contains only thin CLI wrappers, test fixtures, and one-offs.

## Phases
- [x] Phase 0: Create `@garazyk/narzedzia` package
- [x] Phase 1: Expand `@garazyk/gruszka` (chat-viewer, account-ops)
- [x] Phase 2: Expand `@garazyk/hamownia` (mock-twilio server, account-discovery, invite-code, pds-cli)
- [x] Phase 3: Rewrite chat scripts to use packages
- [x] Phase 4: Move scenario-dashboard to packages/
- [x] Phase 5: Expand `@garazyk/schemat` (web-client-compose)
- [x] Phase 6: Rewrite remaining scripts
- [x] Phase 7: Update workspace, boundary checks, CI

## Detailed plan
See: docs/refactor/scripts-to-packages-plan.md

## Completion
Refactor completed on 2026-05-17. All library logic moved to packages.
Scripts are now thin wrappers. Boundary and type checks pass.
