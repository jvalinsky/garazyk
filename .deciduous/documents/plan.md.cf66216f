# JSR Monorepo Migration Plan

## Objective
Convert the repository into a Deno JSR-ready monorepo that uses standard Deno
workspace resolution for local packages while keeping non-publishable local tools
out of the publish path.

## Key Files & Context
- `deno.json`
- `.github/workflows/publish.yml`
- `packages/laweta/deno.json`
- `packages/gruszka/deno.json`
- `packages/schemat/deno.json`
- `packages/hamownia/deno.json`
- `packages/narzedzia/deno.json`
- `packages/dashboard/deno.json`
- `README.md`
- `MIGRATING.md`
- `AGENTS.md`
- `scripts/deno.lock`

## Implementation Steps

1. **Fix Current Baseline Breakage**
   - Fix the parse/typecheck failure in `packages/hamownia/binary_services.ts`.
   - Treat `deno check packages/*/mod.ts scripts/*.ts` as the acceptance gate before config migration work is considered valid.

2. **Clean Root Workspace Config And Tasks**
   - Remove only the manual root `@garazyk/*` imports that duplicate package workspace names.
   - Keep third-party root imports used by scripts and packages.
   - Resolve the duplicate root `"test"` task by choosing `deno run -A scripts/test_runner.ts` as the canonical `test` task.
   - Add or keep a separate package-only test task if package-only test execution remains useful.
   - Keep dashboard checks explicit enough to load `packages/dashboard/deno.json`, because dashboard has JSX/Fresh imports that differ from the library packages.

3. **Standardize Publishable Package Configs**
   - Apply publish config only to `packages/laweta`, `packages/gruszka`, `packages/schemat`, `packages/hamownia`, and `packages/narzedzia`.
   - Keep those five library package versions aligned at `0.1.0-alpha.1`.
   - Add explicit `publish.include` and `publish.exclude` rules for those five libraries.
   - Audit exported public APIs in those packages for explicit return types, with the existing `schemat` exported Zod schema exception from `AGENTS.md`.

4. **Keep Scripts Local, Do Not Make All Scripts A Workspace Package**
   - Do not add `./scripts` to the root workspace.
   - Do not create a top-level `scripts/deno.json` unless a later focused task proves it is needed.
   - Keep scripts resolving workspace packages through root config after the root aliases are removed.
   - Preserve nested tooling such as `scripts/docs/deno.json`, Node package files, and scenario report artifacts.

5. **Make Dashboard Explicitly Local-Only**
   - Treat `packages/dashboard` as a local workspace member for development and checks, not as a JSR-published package.
   - Remove dashboard `publish` metadata and JSR-oriented README instructions.
   - Do not rely on removing `version` as the mechanism that prevents publishing.
   - Ensure CI avoids publishing dashboard by explicitly publishing only the five library packages.

6. **Update Publishing CI**
   - Replace the existing loop over `laweta gruszka schemat hamownia` with explicit publish commands for all five libraries, including `narzedzia`.
   - Use `--allow-slow-types` where needed, or consistently across the five-library publish command if that is simpler.
   - Do not use root `deno publish` while dashboard remains a workspace member.

7. **Consolidate Lockfiles And Docs**
   - Delete `scripts/deno.lock` only after confirming no nested script config still points at it.
   - Regenerate or update root `deno.lock`.
   - Update `README.md`, `MIGRATING.md`, and `AGENTS.md` to describe native workspace resolution, local dashboard usage, and the explicit five-package publish flow.

## Verification & Testing
- Run `deno task boundaries`.
- Run `deno check packages/*/mod.ts scripts/*.ts`.
- Run `deno task dashboard:check`.
- Run `deno task test`.
- Run `deno test -A packages/`.
- Run `deno publish --dry-run --allow-dirty --allow-slow-types` from each of the five publishable package directories, or verify an equivalent explicit five-package CI command locally.

## Assumptions
- Preserve graph history rather than editing deciduous internals directly.
- Dashboard remains a local development workspace member but is excluded from publishing.
- `scripts/` remains operational code, not a publishable package or workspace package, unless a later focused migration scopes its nested tooling.
