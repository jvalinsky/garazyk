# Verification Log

Date: 2026-05-17

## Baseline

- `deno check packages/*/mod.ts`: passed before API changes.
- `deno task boundaries`: passed with 17 known baseline violations.
- `deno doc --lint packages/laweta/mod.ts packages/gruszka/mod.ts packages/schemat/mod.ts packages/hamownia/mod.ts`: failed with 1036 documentation lint errors.

## Phase Results

### Final Verification

- `deno check packages/*/mod.ts`: passed.
- `deno task boundaries`: passed with 2 known baseline violations, both from `packages/schemat/topology_compiler_test.ts -> @garazyk/hamownia`.
- `deno doc --lint packages/laweta/mod.ts packages/gruszka/mod.ts packages/schemat/mod.ts packages/hamownia/mod.ts`: passed.
- `deno test -A packages/hamownia packages/schemat packages/gruszka packages/laweta`: passed, 192 tests.
- `deno check scripts/*.ts`: passed.
- `deno task dashboard:check`: passed.

### Notes

- No commit SHA recorded because no commit was requested or created in this turn.
- Full generated Gruszka Lexicon types remain available on `@garazyk/gruszka/lexicons`; root docs intentionally expose compact proxy aliases to keep the root doc-lint gate usable.
