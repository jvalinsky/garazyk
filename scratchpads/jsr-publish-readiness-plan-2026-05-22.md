# JSR Publish Readiness Plan for Garazyk Deno Packages

Date: 2026-05-22

## Scope

Prepare the Deno workspace packages in `packages/` for publication to JSR:

- `@garazyk/schemat`
- `@garazyk/gruszka`
- `@garazyk/laweta`
- `@garazyk/hamownia`
- `@garazyk/narzedzia`
- `@garazyk/tui`

This plan is based on a code review of the local Deno package configuration,
imports, public APIs, dry-run publishing behavior, and current JSR publishing
requirements.

## Constraints

- Do not run `deno publish` without `--dry-run` until all readiness checks pass
  and the maintainer explicitly approves a real release.
- Use `deno publish --dry-run --allow-dirty` only for local validation while the
  repository has unrelated uncommitted changes.
- Treat published package APIs as stable surface area: exports, docs, dependency
  specifiers, and package metadata need review before release.

## Reference Sources

Primary JSR documentation reviewed:

- https://jsr.io/docs/publishing-packages
- https://jsr.io/docs/troubleshooting
- https://jsr.io/docs/about-slow-types
- https://docs.deno.com/runtime/reference/cli/publish/
- https://docs.deno.com/runtime/fundamentals/workspaces/

Relevant JSR rules and expectations:

- Packages need valid package metadata, including `name`, `version`, `exports`,
  and license metadata.
- Publishable imports must use supported specifiers. JSR rejects arbitrary HTTPS
  imports in package code.
- `deno publish --dry-run` should be used before actual publication; add
  `--check=all` for the stricter pre-release check that includes remote modules.
- Package contents should be constrained with `publish.include` /
  `publish.exclude` where needed.
- Public APIs should be documented and should not expose private types.
- Slow or inferred public types should be avoided by adding explicit exported
  type annotations.
- Publish individual workspace members from their package directories. For
  interdependent workspace packages, publish dependencies first; Deno rewrites
  workspace references to registry references during publishing.

## Current Status Summary

Validation snapshot from 2026-05-22:

- `deno publish --dry-run --allow-dirty --check=all` passes for `schemat`,
  `gruszka`, `laweta`, `narzedzia`, and `tui`.
- `deno publish --dry-run --allow-dirty --check=all` fails for `hamownia`.
- Running `deno publish --dry-run --allow-dirty` from the workspace root fails
  on the same `hamownia` error.
- `deno task check` passes.
- `deno test -A packages/*/public_api_test.ts` passes: 8 tests.
- `deno fmt --check packages/` fails: 672 files need formatting.
- `deno task lint` fails: 1,674 lint issues, 306 auto-fixable.

| Package              | Strict dry-run status | Main blocker(s)                                                                       |
| -------------------- | --------------------- | ------------------------------------------------------------------------------------- |
| `@garazyk/schemat`   | Passes                | Release polish remains: fmt/lint gate, documentation polish, export review            |
| `@garazyk/gruszka`   | Passes                | Release polish remains: fmt/lint gate, documentation polish, export review            |
| `@garazyk/laweta`    | Passes                | Release polish remains: fmt/lint gate, workspace alias re-export review               |
| `@garazyk/hamownia`  | Fails                 | Invalid HTTPS import in two places; dynamic import warning; fmt/lint gate             |
| `@garazyk/narzedzia` | Passes                | Large lint/documentation backlog; export surface review                               |
| `@garazyk/tui`       | Passes                | Missing README; no publish include/exclude; tests included in package; version review |

Non-workspace candidate:

- `scripts/lib/deno/jsr.json` is not currently publishable from its location.
  `deno publish --dry-run --allow-dirty --config jsr.json` fails because that
  config file is not a member of the configured workspace. Decide whether this
  legacy facade should be removed as a publish target, moved into the workspace,
  or replaced by the `packages/*` modules.

## Validation Commands

Use these commands during implementation. Keep using dry-run until final
approval.

Hard publish checks:

```sh
deno fmt --check packages/
deno task check
deno task lint

deno test -A packages/*/public_api_test.ts

for pkg in schemat gruszka laweta hamownia narzedzia tui; do
  (cd "packages/$pkg" && deno publish --dry-run --allow-dirty --check=all)
done

deno publish --dry-run --allow-dirty --check=all
```

Documentation polish checks:

```sh
for pkg in schemat gruszka laweta hamownia narzedzia tui; do
  deno doc --lint "packages/$pkg/mod.ts"
done
```

Before real publishing, repeat without `--allow-dirty` from a clean worktree:

```sh
for pkg in schemat gruszka laweta hamownia narzedzia tui; do
  (cd "packages/$pkg" && deno publish --dry-run --check=all)
done
```

Do not run real publish in automation unless explicitly requested.

## Phase 1: Fix Hard JSR Publish Blockers

### 1.1 Replace the invalid HTTPS SQLite import in `hamownia`

Location:

- `packages/hamownia/run_command.ts:413`
- `packages/hamownia/run_command.ts:598`

Current issue:

```ts
const { Database } = await import(SQLITE_MODULE_SPECIFIER);
```

Dry-run failure:

- `error[invalid-external-import]: invalid import to a non-JSR 'https' specifier`

Why this matters:

- JSR rejects arbitrary HTTPS imports in published packages.
- Supported external specifiers include `jsr:`, `npm:`, `node:`, `data:`, and
  `bun:`.

Implementation options:

1. Prefer a maintained JSR SQLite package if API and native/runtime requirements
   fit.
2. Use an npm package if it works in the intended Deno runtime and permissions
   model.
3. Vendor the minimal dependency if external package compatibility is poor.
4. Make dashboard SQLite registration optional behind an injected adapter so
   core `hamownia` can publish without bundling a direct SQLite runtime
   dependency.

Recommended approach:

- Refactor dashboard run-registration into an adapter boundary.
- Keep `run_command.ts` independent from the concrete SQLite import.
- Provide either:
  - a JSR/npm-compatible SQLite adapter, or
  - a local non-published dashboard adapter outside `packages/hamownia`.

Acceptance criteria:

- `cd packages/hamownia && deno publish --dry-run --allow-dirty --check=all` no
  longer reports `invalid-external-import`.
- Scenario runs still register dashboard run metadata when the dashboard
  database exists.
- Failure to load the optional database adapter remains non-fatal, matching the
  current best-effort behavior.

### 1.2 Triage the dynamic scenario import warning in `hamownia`

Location:

- `packages/hamownia/host_child_runner.ts:56`

Current code:

```ts
// deno-lint-ignore unanalyzable-dynamic-import
const module = await import(
  `${toFileUrl(args.scenarioPath).href}?run=${Date.now()}`
) as ScenarioModule;
```

Dry-run warning:

- `warning[unanalyzable-dynamic-import]: unable to analyze dynamic import`

Why this matters:

- After publishing, imports from local import maps or package manifests are not
  rewritten inside unanalyzable dynamic imports.
- This may be acceptable if the scenario path is always a runtime file URL and
  scenario modules are user-provided runtime inputs.

Decision needed:

- Keep the dynamic import and document the runtime contract, or refactor the
  child runner to accept a resolvable static module entry point.

Recommended approach:

- Keep the dynamic import if this runner is intentionally a scenario loader.
- Add public documentation stating that scenario modules are loaded from runtime
  file paths and must use resolvable imports independent of the package import
  map.
- Keep the lint ignore, but add a concise comment explaining the runtime
  contract.

Acceptance criteria:

- Dry-run has no hard errors.
- The remaining warning is either eliminated or explicitly accepted and
  documented.
- Scenario execution tests still pass.

## Phase 2: Fix Package Content Metadata

### 2.1 Add publish filtering to `@garazyk/tui`

Location:

- `packages/tui/deno.json`

Current issue:

- No `publish.include` / `publish.exclude` block.
- Dry-run includes test files such as `command_test.ts`, `focus_test.ts`, and
  related test modules.

Recommended change:

```json
"publish": {
  "include": [
    "README.md",
    "LICENSE",
    "deno.json",
    "*.ts",
    "testing/**/*.ts"
  ],
  "exclude": [
    "**/*.test.ts",
    "**/*_test.ts"
  ]
}
```

Review before applying:

- Confirm whether `testing/mod.ts` is intended as a published testing API.
- If yes, keep `testing/**/*.ts` in `include`.
- If no, remove `./testing` from exports and exclude `testing/**`.

Acceptance criteria:

- `cd packages/tui && deno publish --dry-run --allow-dirty --check=all` no
  longer lists test files.
- Export target `./testing` is either intentionally published or intentionally
  removed.

### 2.2 Add `packages/tui/README.md`

Current issue:

- `@garazyk/tui` has no README.

Recommended README sections:

- Package name and purpose.
- Install/import examples from JSR.
- Public exports:
  - `@garazyk/tui`
  - `@garazyk/tui/runtime`
  - `@garazyk/tui/testing`, if retained.
- Minimal example showing a command/dashboard render flow.
- Runtime and permission notes.
- Stability note for `1.0.0` or adjust package version if API is not actually
  stable.

Acceptance criteria:

- README exists and is included by dry-run.
- README examples use JSR imports, not local workspace aliases.

### 2.3 Review package versions before first publish

Current versions:

- `@garazyk/schemat`: `0.1.0-alpha.1`
- `@garazyk/gruszka`: `0.1.0-alpha.1`
- `@garazyk/laweta`: `0.1.0-alpha.1`
- `@garazyk/hamownia`: `0.1.0-alpha.1`
- `@garazyk/narzedzia`: `0.1.0-alpha.1`
- `@garazyk/tui`: `1.0.0`

Concern:

- `@garazyk/tui` is already `1.0.0`, unlike the other alpha packages.

Decision needed:

- Keep `@garazyk/tui@1.0.0` only if the API is ready for stable semver
  expectations.
- Otherwise lower it before first publish, for example to `0.1.0-alpha.1`.

Acceptance criteria:

- Version numbers match the intended stability and release order.
- Interdependent packages reference compatible published versions after release.

### 2.4 Decide the fate of `scripts/lib/deno`

Location:

- `scripts/lib/deno/jsr.json`

Current issue:

- The directory has a JSR config file but is not a Deno workspace member.
- Local dry-run validation fails before package checks start because Deno
  rejects the config as outside the workspace.
- Most files in this directory are compatibility re-exports of the package
  modules now living under `packages/`.

Recommended approach:

- Do not publish this facade as a seventh package unless there is a concrete
  compatibility need.
- Prefer publishing the six package roots in `packages/`.
- If a compatibility package is still needed, move it into the root workspace,
  add README/LICENSE metadata, and dry-run it like the other package roots.

Acceptance criteria:

- The release plan explicitly says whether `scripts/lib/deno` is retired, moved
  into the workspace, or kept as non-published repo glue.

## Phase 3: Clean Public API Documentation

### 3.1 Fix documentation lint package by package

Current documentation lint counts from the scratchpad baseline:

| Package     | Error count | Main categories                     |
| ----------- | ----------: | ----------------------------------- |
| `schemat`   |          20 | `missing-jsdoc`, `private-type-ref` |
| `gruszka`   |          25 | `private-type-ref`, `missing-jsdoc` |
| `laweta`    |           3 | `missing-jsdoc`                     |
| `hamownia`  |          22 | `private-type-ref`, `missing-jsdoc` |
| `narzedzia` |         177 | mostly `missing-jsdoc`              |
| `tui`       |          19 | `missing-jsdoc`, `private-type-ref` |

Recommended order:

1. `laweta`, because it has only 3 errors.
2. `schemat`, because other packages depend on its types.
3. `gruszka`, because it is a primary client package and has private generated
   client type exposure.
4. `hamownia`, because it currently has the hard publish blocker too.
5. `tui`, after deciding its published testing API.
6. `narzedzia`, because it has the largest backlog and may be better split into
   public and internal modules first.

TSDoc house standards:

- Module-level comment on public entry files.
- Public exports should have concise documentation.
- Functions need `@param` and `@returns` where useful.
- Generic types need `@typeParam`.
- Error-throwing APIs need `@throws`.
- Public symbols should use release tags such as `@public`, `@beta`, `@alpha`,
  or `@internal` where applicable.

Private type reference strategy:

- If a private type appears in a public API, either:
  - export and document the type, or
  - hide it behind an exported interface/type alias, or
  - change the public API to return a narrower documented type.

Acceptance criteria:

```sh
deno doc --lint packages/schemat/mod.ts
deno doc --lint packages/gruszka/mod.ts
deno doc --lint packages/laweta/mod.ts
deno doc --lint packages/hamownia/mod.ts
deno doc --lint packages/narzedzia/mod.ts
deno doc --lint packages/tui/mod.ts
```

All commands should exit with status 0 before a polished public release, or the
team should explicitly decide which package can publish with known documentation
debt. The JSR dry-run currently proves that documentation generation succeeds
for packages whose strict dry-run passes; these documentation lint counts are
release-quality and package-score work, not the hard blocker for those packages.

## Phase 4: Clean Lint and Type Safety

### 4.1 Keep `deno task check` green

Current status:

- `deno task check` passes for `packages/*/mod.ts`.

Acceptance criteria:

- It remains green after all dependency and API refactors.

### 4.2 Fix or intentionally suppress `deno task lint` failures

Current status:

- `deno task lint` fails with a large number of package lint errors.

Observed categories include:

- `no-explicit-any`
- `no-unused-vars`
- `require-await`
- `verbatim-module-syntax`
- `no-import-prefix`
- `no-unversioned-import`
- `no-this-alias`

Recommended strategy:

1. Fix package-source errors that affect published modules first.
2. Exclude generated code only when regeneration cannot reasonably satisfy lint.
3. Prefer explicit `unknown` and type guards over `any`.
4. Use `import type` for type-only imports.
5. Remove unused variables or prefix intentionally unused callback parameters
   with `_` only if accepted by the lint config.
6. Move inline dependencies into package/root import maps where Deno lint
   requires it.

Acceptance criteria:

- `deno task lint` exits with status 0, or a documented lint baseline exists
  with intentional excludes.
- If a baseline is accepted for first publish, it must still leave
  package-source publish blockers fixed. In particular, the invalid HTTPS import
  in `hamownia` must not be hidden by a lint exclude.

## Phase 5: Review Inter-Package Dependencies and Exports

### 5.1 Verify workspace alias rewriting behavior

Observed workspace imports:

- `laweta/format.ts` re-exports from `@garazyk/gruszka/format.ts`.
- `hamownia` imports `@garazyk/gruszka`, `@garazyk/laweta`, and
  `@garazyk/schemat` in many files.
- `narzedzia` imports `@garazyk/schemat`.

Dry-run currently rewrites or accepts these for packages that pass, but release
ordering matters.

Recommended publish order:

1. `@garazyk/schemat`
2. `@garazyk/gruszka`
3. `@garazyk/laweta`
4. `@garazyk/narzedzia`
5. `@garazyk/tui`
6. `@garazyk/hamownia`

Rationale:

- `schemat` is used by `hamownia` and `narzedzia`.
- `gruszka` is used by `laweta` and `hamownia`.
- `laweta` is used by `hamownia`.
- `hamownia` has the most runtime orchestration dependencies and should publish
  last.

Acceptance criteria:

- Each package dry-run succeeds after its dependencies are publishable.
- Published import examples use final JSR package names and versions.

### 5.2 Review public exports for accidental internal APIs

Current export counts:

- `gruszka`: 8 export entries
- `hamownia`: 26 export entries
- `laweta`: 2 export entries
- `narzedzia`: 8 export entries
- `schemat`: 4 export entries
- `tui`: 3 export entries

Concern:

- `hamownia` and `narzedzia` expose many operational modules. Some may be better
  kept internal for first release.

Recommended review questions:

- Is each export intended for external consumers?
- Does each export have stable semantics?
- Can internal CLIs remain unexported while still being runnable from the
  repository?
- Should generated or low-level files be exposed directly, or only through
  `mod.ts`?

Acceptance criteria:

- Every `exports` entry has a README mention or a documented reason to exist.
- Internal-only modules are removed from `exports` before first publish.

## Phase 6: Package Score and Release Polish

### 6.1 Add consistent package READMEs

Already present:

- `gruszka`
- `hamownia`
- `laweta`
- `narzedzia`
- `schemat`

Missing:

- `tui`

Recommended README checklist for all packages:

- What the package does.
- Import examples using `jsr:@garazyk/<name>@<version>`.
- Main exported modules.
- Minimal usage example.
- Required permissions, if any.
- Stability status.
- Link back to the Garazyk repository.

### 6.2 Verify license files and SPDX metadata

Current status:

- Packages report `license: "Unlicense OR CC0-1.0"`.
- Packages have license files available.

Acceptance criteria:

- Each package includes the intended license file in dry-run output.
- License expression matches project policy.

### 6.3 Verify package contents

For each package dry-run, inspect included files for:

- No test files unless intentionally published as fixtures.
- No local-only scripts unless intentionally part of the API.
- No generated files that are stale.
- No secrets, keys, local config, reports, or diagnostics.

Acceptance criteria:

- Dry-run file list is reviewed and approved per package.

## Phase 7: Final Pre-Publish Gate

Run from a clean worktree.

```sh
git status --short

deno fmt --check packages/
deno task check
deno task lint
deno test -A packages/*/public_api_test.ts

deno doc --lint packages/schemat/mod.ts
deno doc --lint packages/gruszka/mod.ts
deno doc --lint packages/laweta/mod.ts
deno doc --lint packages/hamownia/mod.ts
deno doc --lint packages/narzedzia/mod.ts
deno doc --lint packages/tui/mod.ts

for pkg in schemat gruszka laweta hamownia narzedzia tui; do
  (cd "packages/$pkg" && deno publish --dry-run --check=all)
done

deno publish --dry-run --check=all
```

Release manager approval checklist:

- [ ] All dry-runs pass without hard errors.
- [ ] Any remaining warnings are documented and accepted.
- [ ] Published file lists are reviewed.
- [ ] Package versions are final.
- [ ] README examples use final package versions.
- [ ] Export surfaces are approved.
- [ ] Release order is confirmed.
- [ ] Maintainer has JSR scope/package permissions.

## Phase 8: Manual Publish Procedure

Only after explicit maintainer approval.

Recommended publish order:

```sh
cd packages/schemat && deno publish
cd ../gruszka && deno publish
cd ../laweta && deno publish
cd ../narzedzia && deno publish
cd ../tui && deno publish
cd ../hamownia && deno publish
```

Important:

- Do not run these commands from an automated agent unless explicitly requested.
- If any publish step fails, stop and do not continue to dependent packages
  until the failure is understood.
- After publishing, verify package pages on JSR and test importing each package
  in a temporary Deno project.

## Post-Publish Verification

Create a temporary project outside the repository and verify imports:

```sh
mkdir /tmp/garazyk-jsr-smoke
cd /tmp/garazyk-jsr-smoke
cat > smoke.ts <<'TS'
import * as schemat from "jsr:@garazyk/schemat";
import * as gruszka from "jsr:@garazyk/gruszka";
import * as laweta from "jsr:@garazyk/laweta";
import * as narzedzia from "jsr:@garazyk/narzedzia";
import * as tui from "jsr:@garazyk/tui";
import * as hamownia from "jsr:@garazyk/hamownia";

console.log(Boolean(schemat), Boolean(gruszka), Boolean(laweta), Boolean(narzedzia), Boolean(tui), Boolean(hamownia));
TS

deno run smoke.ts
```

If `hamownia` requires permissions or runtime dependencies, add a second smoke
test focused on import-only behavior and a separate runtime test with documented
permissions.

## Open Decisions

1. Should `@garazyk/tui` remain `1.0.0`, or should it be reset to an alpha
   version before first publish?
2. Is `@garazyk/tui/testing` intended as a public API?
3. Should `hamownia` publish its full operational module surface, or should some
   exports remain internal until stabilized?
4. What SQLite dependency/adaptation strategy should replace the current HTTPS
   import?
5. Should `scripts/lib/deno` be retired as a publish target, moved into the
   workspace, or retained only as non-published compatibility glue?
6. Are documentation lint failures hard blockers for first publish, or can
   selected packages publish with documented debt?

## Definition of Done

The Deno package set is ready to publish when:

- `deno task check` passes.
- `deno task lint` passes or has an approved baseline.
- `deno fmt --check packages/` passes or has an approved formatting-only
  follow-up before release.
- `deno test -A packages/*/public_api_test.ts` passes.
- All package `deno publish --dry-run --check=all` commands pass from a clean
  worktree.
- Root workspace `deno publish --dry-run --check=all` passes or the release
  manager intentionally publishes only selected package directories.
- `hamownia` has no invalid external imports.
- `tui` no longer publishes test files accidentally.
- `scripts/lib/deno` has an explicit publish/no-publish decision.
- Every package has a README and license in the dry-run file list.
- Public API documentation is either clean or explicitly accepted for first
  release.
- Package versions and release order are approved by the maintainer.
