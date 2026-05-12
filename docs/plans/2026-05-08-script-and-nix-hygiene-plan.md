# Script and Nix Hygiene Plan

Date: 2026-05-08

Goal: review repository scripts, wrappers, generated script-adjacent files, and Nix files, then decide whether each family should be deleted, moved, revised, or left alone.

## Scope

This plan covers:

- Root automation under `scripts/`.
- Skill and tool runners under `.agents/skills/*/scripts/` and `.opencode/tools/`.
- Documentation automation under `docs/scripts/` and `scripts/docs/`.
- Example deployment scripts under `examples/tutorial-6-deployment/`.
- PLC integration shell scripts under `Garazyk/Tests/plc_e2e/`.
- Repository Nix files: `flake.nix`, `flake.lock`, and nested flakes/derivations.

It does not propose moving normal Objective-C, Go, TypeScript, or notebook source code merely because the file extension is executable in another context. Those files stay with their owning module unless explicitly named below.

## Findings To Fix First

1. `scripts/ops/uninstall.sh` has a syntax error at line 67: an extra `)` after the log message. `bash -n` fails on this file. Revise before any other operations work.
2. Several scripts still point at stale `ATProtoPDS/Sources` paths or hard-code `/Users/jack/Software/garazyk`. These should not survive the cleanup.
3. Some scripts perform destructive actions (`rm -rf`, `pkill`, `killall`, production deploy/update) without enough confirmation, target validation, or PID scoping.
4. `scripts/ops/hash_admin_password.sh` has an unsafe fallback that emits a value tagged as PBKDF2 while not actually deriving PBKDF2. That should be fixed before production use.
5. Multiple "successful no-op" or historical scripts remain executable. They hide real drift because callers can pass while doing nothing.

## Phase Order

1. **Stabilize broken active scripts.** Fix syntax errors and security-sensitive scripts first: `uninstall.sh`, `hash_admin_password.sh`, backup/restore helpers, and config validation.
2. **Delete or quarantine stale duplicates.** Remove retired wrappers, stale lint wrappers, no-op docs scripts, and local agent settings under `scripts/.letta/`.
3. **Move scripts into clearer ownership.** Put fuzzing tools under `scripts/fuzzing/`, and production DNS/account scripts under `scripts/ops/production/`.
4. **Revise remaining active tools.** Bring shell scripts to `set -euo pipefail`, root discovery, `mktemp`, safe cleanup traps, `find -print0`, and structured JSON handling.
5. **Refresh Nix.** Keep flakes, remove or expose unused derivations, and add checks/formatters so script hygiene can be enforced.

## Delete

Delete these after checking references with `rg` and updating any docs or wrappers that still call them.

| Path | Reason |
|---|---|
| `scripts/.letta/.lettaignore` | Tool-local state does not belong under `scripts/`. |
| `scripts/.letta/settings.json` | Historical local agent configuration, not executable project tooling. |
| `scripts/.letta/settings.local.json` | Local session/agent IDs should not be tracked in the repo. |
| `scripts/build/run-clang-tidy.sh` | Hard-coded checkout path and stale `ATProtoPDS/Sources`; superseded by `scripts/build/lint.sh`. |
| `scripts/build/run-format.sh` | Hard-coded checkout path and stale paths; superseded by a revised lint/format entrypoint. |
| `scripts/build/run-scan-build.sh` | Hard-coded checkout path and duplicate scan mode. |
| `scripts/build/build-linux.sh` | Clones stale `NSPds` repo and is not a repo-local build script. Replace with docs/Nix/Linux build instructions. |
| `scripts/build/migrate_errors.sh` | One-off migration scanner with stale source root. Recreate as a current lint only if still needed. |
| `scripts/build/build-pds-docs.sh` | Manual HeaderDoc HTML generation with stale file list; VitePress docs are canonical. |
| `scripts/dev/add_test_files.py` | Manually edits a stale Xcode project; repo guidance says generate projects. |
| `scripts/dev/add_test_files.sh` | Shell duplicate of the stale Xcode project editor. |
| `scripts/dev/generate_activity.py` | Duplicate demo data generator; replace with `seed_demo_via_xrpc.py` or scenario seeding. |
| `scripts/dev/seed_records.py` | Direct database writes with fake CIDs; keep XRPC-based seeders instead. |
| `scripts/dev/seed_via_api.py` | Older partial API seeder with hard-coded build paths; superseded by `seed_demo_via_xrpc.py`. |
| `scripts/dev/setup_test_data.sh` | Incomplete and partially unimplemented; superseded by current seeders. |
| `scripts/dev/simulate_interactions.py` | Duplicate broad demo simulator; fold useful calls into scenario tests or delete. |
| `scripts/docs/archive.js` | Prints TODO and exits successfully. |
| `scripts/docs/validate.js` | Prints TODO and exits successfully. |
| `scripts/docs/html/index.html` | Generated/static sample under a scripts tree; move to docs fixtures only if still used. |
| `scripts/seed_network.py` | Duplicates the maintained full-suite launcher and uses broad process cleanup. |
| `scripts/test/atproto-compliance-review-simple.sh` | Duplicate, brittle compliance scanner; replace with the coverage audit skill scripts. |
| `scripts/test/atproto-compliance-review.sh` | Broken array/temp-file design and brittle grep checks; replace with the coverage audit workflow. |
| `scripts/test/sql_injection_test.sh` | Hard-coded proof script with stale references; replace with real security tests/audit scans. |
| `scripts/wasm/build-clang-wasm.sh` | Executable placeholder that exits 2; track this as roadmap/docs instead of a script. |

## Move

Move these to clarify ownership. During moves, leave temporary compatibility wrappers only where docs or external workflows need a deprecation window.

| Current Path | Target | Reason |
|---|---|---|
| `scripts/add-account.sh` | `scripts/ops/production/add-account.sh` | Production account/DNS tooling should live with ops. |
| `scripts/cloudflare-dns.sh` | `scripts/ops/production/cloudflare-dns.sh` | Production Cloudflare API mutation should not sit at root script level. |
| `scripts/setup-pds.sh` | `scripts/ops/production/setup-pds.sh` | Production provisioning helper belongs under ops. |
| `scripts/coverage-diff.sh` | `scripts/fuzzing/coverage-diff.sh` | Fuzzing helper; group with crash/corpus tools. |
| `scripts/generate-xrpc-corpus.sh` | `scripts/fuzzing/generate-xrpc-corpus.sh` | Fuzzing corpus generator. |
| `scripts/minimize-corpus.sh` | `scripts/fuzzing/minimize-corpus.sh` | Fuzzing corpus minimizer. |
| `scripts/regression-runner.sh` | `scripts/fuzzing/regression-runner.sh` | Fuzzing crash triage family. |
| `scripts/run-fuzzing.sh` | `scripts/fuzzing/run-fuzzing.sh` | Canonical fuzzer launcher. |
| `scripts/triage-crashes.sh` | `scripts/fuzzing/triage-crashes.sh` | Fuzzing crash triage family. |
| `scripts/test/run-fuzzers-extended.sh` | `scripts/fuzzing/run-fuzzers.sh` | Merge extended/limited/macos modes into one runner. |
| `scripts/test/run-fuzzers-limited.sh` | `scripts/fuzzing/run-fuzzers.sh` | Merge into one parameterized runner. |
| `scripts/test/run-fuzzers-macos.sh` | `scripts/fuzzing/run-fuzzers.sh` | Merge into one parameterized runner. |
| `scripts/test/run-fuzzers-macos-fixed.sh` | `scripts/fuzzing/run-fuzzers.sh` | Use its improvements in the canonical runner, then remove the suffix. |
| `scripts/docs/*` | `tooling/docs-migration/` | This is a migration toolkit, distinct from active `docs/scripts/` validators. |
| `scripts/scenarios/lib/*.py` | Delete after import update, or keep temporarily as `scripts/scenarios/compat/` | These are compatibility re-export shims for `scripts/lib/atproto`. |
| `.claude/hooks/post-commit-reminder.sh` | `.agents/hooks/post-commit-reminder.sh` | Repository guidance says do not edit `.claude/` symlinks/config directly; make `.agents` canonical if hook tooling supports it. |
| `.claude/hooks/require-action-node.sh` | `.agents/hooks/require-action-node.sh` | Same hook ownership issue as above. |

## Revise

### Build And Quality Scripts

| Path | Revision |
|---|---|
| `scripts/build/build.sh` | Keep out-of-source build behavior; add portable job count helper, explicit `xcodegen generate` path for macOS when using Xcode, and optional `BUILD_DIR`. |
| `scripts/build/build-docs.sh` | Keep; align with `docs/scripts/build-docs.sh` and avoid duplicate docs build entrypoints. |
| `scripts/build/clean.sh` | Add `--dry-run`, `--yes`, target allowlist, and do not remove `docs/node_modules` unless requested. |
| `scripts/build/lint.sh` | Replace `find | xargs` with `find -print0 | xargs -0`, split check vs write modes, cover current `Garazyk` paths, and fail consistently. |
| `scripts/build/process_oclint_report.py` | Keep; add tests/fixtures if quality gate still consumes OCLint output. |
| `scripts/build/quality_gate.sh` | Remove boilerplate author metadata, restore current paths, make disabled clang-tidy explicit, and emit machine-readable summary. |
| `scripts/build/validate-headerdoc.sh` | Update default root to `Garazyk/Sources`, respect `NO_COLOR`, and decide whether HeaderDoc is still a gate. |
| `scripts/build/wipe_and_rebuild.sh` | Keep only if renamed as a destructive local reset tool with strong path validation and explicit `--yes`. |
| `scripts/build/wipe_and_regen.sh` | Fold into `scripts/dev/run_demo.sh` or delete; avoid broad `pkill -f kaszlak` and hand-built JSON. |

### Ops Scripts

| Path | Revision |
|---|---|
| `scripts/ops/backup_pds.sh` | Keep; validate retention as an integer, add backup manifest/checksum, and ensure cleanup cannot escape backup root. |
| `scripts/ops/db_dump.sh` | Validate table names or use a structured sqlite wrapper; do not interpolate arbitrary user input into SQL identifiers. |
| `scripts/ops/hash_admin_password.sh` | Replace fallback with real PBKDF2 via Python `hashlib.pbkdf2_hmac` or `openssl kdf`; never tag raw SHA as PBKDF2. |
| `scripts/ops/install.sh` | Add dry-run, safer UID/GID allocation, explicit config secret handling, and fix the summary typo. |
| `scripts/ops/security_audit.sh` | Keep as a quick local gate only after aligning with `.agents/skills/objc-security-audit/scripts/`; otherwise make it a wrapper around those scanners. |
| `scripts/ops/setup_linux.sh` | Move content into docs or add distro detection and confirmation before package installs. |
| `scripts/ops/start_plc.sh` | Keep; add root discovery and PID/log options consistent with `start_server.sh`. |
| `scripts/ops/start_server.sh` | Keep; minor polish around config validation and log directory creation. |
| `scripts/ops/uninstall.sh` | Fix syntax error, add dry-run, separate uninstall from purge, and validate root-owned paths before removal. |
| `scripts/ops/verify_backup.sh` | Replace `for db in $(find ...)` with null-delimited iteration and validate archive paths before extraction. |
| `scripts/ops/verify_plc.sh` | Move to test/ops verification or add trap cleanup, configurable ports, and no fixed local temp files. |
| `scripts/validate_pds_config.sh` | Use a real JSON parser path, avoid Python string interpolation of the config path, and support profiles rather than one hard-coded production policy. |

### Production Helpers

| Path | Revision |
|---|---|
| `scripts/add-account.sh` | After moving, avoid password on CLI where possible, validate handles/subdomains, and create DNS JSON with `jq -n` or Python JSON. |
| `scripts/cloudflare-dns.sh` | After moving, URL-encode query params, JSON-escape request bodies structurally, and support update/delete/dry-run modes. |
| `scripts/setup-pds.sh` | After moving, remove hard-coded `DEPLOY_DIR/pds-data`, `garazyk.xyz`, and `build-linux/bin`; source config from environment or a profile file. |

### Developer And Demo Scripts

| Path | Revision |
|---|---|
| `scripts/dev/check_module_boundaries.sh` | Keep; replace fixed `/tmp` hit file with `mktemp`, add null-safe scanning where useful, and wire into quality gate. |
| `scripts/dev/demo_seed.py` | Keep; move account definitions to shared defaults or a config file if it remains a public entrypoint. |
| `scripts/dev/generate_characterization_tests.py` | Either revise into a supported generator using current project layout or delete; regex parsing Objective-C headers is fragile. |
| `scripts/dev/generate_characterization_tests.sh` | Revise only if the Python generator survives; otherwise delete with it. |
| `scripts/dev/pds_cli.py` | Keep if it still adds value over `kaszlak`; add argparse help, timeouts everywhere, and no hard-coded missing config path under `/tmp`. |
| `scripts/dev/run_demo.sh` | Keep; it is the small current local demo launcher. Ensure data deletion stays under disposable roots. |
| `scripts/dev/run_demo_live_plc_directory.sh` | Keep with caution; keep explicit remote confirmation, add dry-run, and make public-write warning impossible to bypass accidentally. |
| `scripts/dev/run_demo_with_build.sh` | Keep; support out-of-source build directory override and avoid unconditional build cache deletion. |
| `scripts/dev/seed_demo_via_xrpc.py` | Keep; this is the canonical small seeder. Add structured logging and optional scenario fixture output. |

### Full-Stack And Scenario Scripts

| Path | Revision |
|---|---|
| `scripts/full_suite_demo.sh` | Keep; this is the canonical full local stack launcher. Continue to centralize service lifecycle here. |
| `scripts/reseed_local_network.sh` | Keep; align service/data paths with `scripts/lib/common.sh` and scenario config. |
| `scripts/run_full_stack_demo.sh` | Keep as a compatibility wrapper only if it delegates to `full_suite_demo.sh`; otherwise delete after docs update. |
| `scripts/run-local-atproto-stack.sh` | Keep; ensure it delegates to `scripts/scenarios/setup_local_network.sh` and does not duplicate lifecycle logic. |
| `scripts/services-control.sh` | Keep; update docs because it controls the PLC/PDS pair, not the entire full suite. |
| `scripts/start-all-services.sh` | Keep; rename or revise description to avoid claiming every service when it manages PLC/PDS. |
| `scripts/stage-docker-binaries.sh` | Keep; add Docker availability checks, output manifest, and clearer failure if Linux ELF staging fails. |
| `scripts/lib/common.sh` | Keep; reduce `eval`, make diagnostics labels precise, and centralize service-port cleanup policy. |
| `scripts/lib/atproto/*.py` | Keep; shared scenario/seeding library. Add redaction rules and keep test credentials obviously local-only. |
| `scripts/scenarios/setup_local_network.sh` | Keep; make it the canonical Docker/scenario setup path. |
| `scripts/scenarios/run_scenario.py` | Keep; keep scenario discovery/config validation close to this runner. |
| `scripts/scenarios/teardown_local_network.sh` | Keep; ensure teardown matches setup and does not remove unrelated containers/volumes. |
| `scripts/scenarios/scenarios/*.py` | Keep; scenario tests belong here. Improve only as scenario coverage changes. |
| `scripts/scenarios/config/*.json` | Leave in place; revise only if service ports/secrets change. |
| `scripts/scenarios/requirements.txt` | Keep; pin or document if scenario runs need reproducibility. |
| `scripts/scenarios/reports/` | Leave ignored/generated; do not track reports. |

### Seeders

| Path | Revision |
|---|---|
| `scripts/seed_full_suite.py` | Keep; remove no-op placeholder loops or implement the intended records. |
| `scripts/seed_chat.py` | Keep; add clearer mismatch handling when account/password counts differ. |

### Fuzzing And Crash Scripts

| Path | Revision |
|---|---|
| `scripts/coverage-diff.sh` | After moving, add strict mode, validate numeric coverage parsing, and avoid divide-by-zero. |
| `scripts/generate-xrpc-corpus.sh` | After moving, generate JSON through a structured writer or checked-in corpus fixtures. |
| `scripts/minimize-corpus.sh` | After moving, quote temp cleanup trap and avoid parsing file lists through command substitution. |
| `scripts/regression-runner.sh` | After moving, use null-delimited file loops and do not write into known-bad input directories by default. |
| `scripts/run-fuzzing.sh` | After moving, validate fuzzer names against an allowlist and centralize corpus/output roots. |
| `scripts/triage-crashes.sh` | After moving, remove `eval` counters and handle file names safely. |

### Test Scripts

| Path | Revision |
|---|---|
| `scripts/test/check_ui_design_system.sh` | Keep; ensure it matches current Admin UI/Cappuccino UI paths. |
| `scripts/test/e2e-docker-test.sh` | Keep; route through scenario setup/teardown and make cleanup PID/container scoped. |
| `scripts/test/run-asan-tests.sh` | Keep; validate build dir and make sanitizer output path explicit. |
| `scripts/test/run-leaks.sh` | Keep; macOS-only checks should fail clearly on Linux. |
| `scripts/test/run-tests.sh` | Keep as the canonical test wrapper; fold retired wrappers into this or delete them. |
| `scripts/test/run_conformance.sh` | Revise or delete; it references `generate_xrpc_coverage_report.js` but the tracked file is `.cjs`. |
| `scripts/test/run_data_model_test.sh` | Revise as a small wrapper with strict mode/root discovery, or fold into `run-tests.sh`. |
| `scripts/test/run_e2e.sh` | Keep; use `full_suite_demo.sh` and diagnostics consistently. |
| `scripts/test/security_test_runner.sh` | Revise heavily or replace; report variables are inconsistent and it overlaps security audit scripts. |
| `scripts/test/test-doc-links.py` | Keep; consider moving under `docs/scripts/` if docs owns it. |
| `scripts/test/test-pds-guide-links.py` | Keep; consider moving under `docs/scripts/` if docs owns it. |
| `scripts/test/test_cli_contract.sh` | Keep; current CLI contract smoke test is useful. |
| `scripts/test/test_page_load.sh` | Revise or delete if current browser/Admin UI smoke tests supersede it. |
| `scripts/test/test_static_files.sh` | Revise or delete if current docs/UI asset checks supersede it. |

Retired wrappers to delete after docs references are updated:

- `scripts/test/test_apply_writes.sh`
- `scripts/test/test_blob_storage.sh`
- `scripts/test/test_endpoints.sh`
- `scripts/test/test_moderation.sh`
- `scripts/test/test_oauth2.sh`
- `scripts/test/test_pds.sh`
- `scripts/test/test_performance.sh`
- `scripts/test/test_server.sh`
- `scripts/test/test_social_features.sh`
- `scripts/test/test-pds-integration.sh`
- `scripts/test/test-pds-oauth-endpoints.sh`

### Documentation Scripts

| Path | Revision |
|---|---|
| `docs/scripts/build-docs.sh` | Fix path to diagram validation or call `npm run validate:diagrams`; currently points at the wrong location. |
| `docs/scripts/deploy-docs.sh` | Move host/path to config and add dry-run; hard-coded production deploy settings should not be the default. |
| `docs/scripts/test-redirects.sh` | Keep; ensure base URL and route list are configurable. |
| `docs/scripts/verify-deployment.sh` | Keep; add timeout/retry controls and avoid hard-coded production assumptions. |
| `docs/scripts/*.ts` | Keep; revise shebangs to match package tooling, especially `validate-content-quality.ts`, and move generated reports under `docs/reports/`. |
| `scripts/docs/check-doc-patterns.sh` | Keep if migration toolkit remains; otherwise move with `scripts/docs/`. |
| `scripts/docs/doc-coverage.py` | Keep with migration toolkit or merge into active docs validation. |
| `scripts/docs/doc-coverage.sh` | Keep with migration toolkit or merge into active docs validation. |
| `scripts/docs/generate_xrpc_coverage_report.cjs` | Keep; coverage reporting is still useful. |
| `scripts/docs/generate_xrpc_next_steps.cjs` | Keep if paired with the coverage report; document its output path. |
| `scripts/docs/index.js` | Keep only if this package remains the docs migration CLI. |
| `scripts/docs/migrate-to-vitepress.ts` | Move to `tooling/docs-migration/`; likely historical but useful for archaeology. |
| `scripts/docs/migrate.js` | Move with migration toolkit; delete if no docs call it. |
| `scripts/docs/repo_docs.py` | Move with migration toolkit or promote to active docs tooling if still used. |
| `scripts/docs/test-redirects.sh` | Leave as temporary wrapper to `docs/scripts/test-redirects.sh`; delete after references update. |
| `scripts/docs/validate-config.js` | Keep with migration toolkit. |
| `scripts/docs/validate-doc-code-examples.sh` | Consolidate with `docs/scripts/validate-code-examples.ts` or keep as shell-specific checker. |
| `scripts/docs/validate-doc-diagrams.sh` | Keep if it remains the canonical Mermaid/render checker; fix callers. |
| `scripts/docs/validate-doc-links.sh` | Consolidate with `docs/scripts/comprehensive-link-validation.ts`. |
| `scripts/docs/lib/*.js` and `scripts/docs/lib/*.test.js` | Move as one package to `tooling/docs-migration/`; do not scatter the library files. |
| `scripts/docs/test/property-tests/*.js` | Move with migration toolkit if still valuable. |
| `scripts/docs/package.json` and `package-lock.json` | Move with migration toolkit or delete if the package is retired. |
| `scripts/docs/configs/*.json` | Move with migration toolkit. |
| `scripts/docs/examples/*.js` | Move with migration toolkit or delete if docs no longer need examples. |
| `scripts/docs/xrpc_coverage_scope*.txt` | Keep near the coverage report generator or move to `docs/reports/docs/inputs/`. |

### Tool And Skill Scripts

| Path | Revision |
|---|---|
| `.opencode/tools/deciduous.ts` | Leave; TypeScript tool wrapper is active WAT tooling. |
| `.opencode/tools/quality_gate_summarized.sh` | Leave; verify it delegates to current `scripts/build/quality_gate.sh` after revisions. |
| `.opencode/tools/run_tests_summarized.sh` | Leave; verify it delegates to current `scripts/test/run-tests.sh`. |
| `.opencode/tools/stub_find_summarized.sh` | Leave; `scripts/stub_find.sh` exists. Improve JSON parsing only if runner output changes. |
| `.opencode/tools/validate_pds_config_summarized.sh` | Leave; update only with `validate_pds_config.sh` changes. |
| `.agents/skills/atproto-coverage-audit/scripts/*` | Leave; skill-owned scripts are coherent and should remain under the skill. |
| `.agents/skills/objc-architecture-audit/scripts/*` | Leave; skill-owned scripts are coherent and should remain under the skill. |
| `.agents/skills/objc-concurrency-audit/scripts/*` | Leave; skill-owned scripts are coherent and should remain under the skill. |
| `.agents/skills/objc-security-audit/scripts/*` | Leave; skill-owned scripts are coherent and should remain under the skill. |

### PLC E2E Scripts

| Path | Revision |
|---|---|
| `Garazyk/Tests/plc_e2e/dual-pds-transfer-test.sh` | Keep; replace broad process cleanup with PID/container-specific cleanup. |
| `Garazyk/Tests/plc_e2e/run-integration-tests.sh` | Keep; use strict mode and repo-root discovery. |
| `Garazyk/Tests/plc_e2e/run-plc-tests.sh` | Keep; use strict mode and repo-root discovery. |

### Tutorial Deployment Scripts

| Path | Revision |
|---|---|
| `examples/tutorial-6-deployment/scripts/backup.sh` | Keep with tutorial; validate relative paths and document production assumptions. |
| `examples/tutorial-6-deployment/scripts/deploy.sh` | Keep with tutorial but add dry-run, safer `.env` loading, cross-platform `sed`, and explicit `sudo` prompts. |
| `examples/tutorial-6-deployment/scripts/health-check.sh` | Keep with tutorial; make docker volume and service names configurable. |
| `examples/tutorial-6-deployment/scripts/update.sh` | Keep with tutorial only after removing automatic `git stash`/`git pull origin main` behavior or gating it behind confirmation. |

### Objective-Jupyter WASM Scripts And Tests

| Path | Revision |
|---|---|
| `objc-jupyter-wasm/scripts/build-jupyterlite-site.sh` | Keep; ensure it fails on missing build artifacts and uses package-local paths only. |
| `objc-jupyter-wasm/scripts/build-smoke-site.mjs` | Keep; align output paths with `build-jupyterlite-site.sh`. |
| `objc-jupyter-wasm/scripts/copy-static-assets.mjs` | Keep; validate inputs and preserve deterministic output. |
| `objc-jupyter-wasm/scripts/serve-demo.sh` | Keep; avoid `jupyter lite build || true` unless explicitly documented, and simplify Python discovery. |
| `objc-jupyter-wasm/tests/*.mjs` and `*.cjs` | Leave with module tests; revise only through the Objective-Jupyter test plan. |
| `objc-jupyter-wasm/test-jl.mjs` | Leave short-term; move under `tests/` if it is still an active test. |

## Leave Alone

These are already in the right ownership location and should not be moved during this cleanup:

- `scripts/completions/kaszlak.bash`
- `scripts/completions/kaszlak.zsh`
- `scripts/lib/__init__.py`
- `scripts/lib/atproto/__init__.py`
- `scripts/lib/atproto/assertions.py`
- `scripts/lib/atproto/characters.py`
- `scripts/lib/atproto/client.py`
- `scripts/lib/atproto/config.py`
- `scripts/lib/atproto/diagnostics.py`
- `scripts/lib/atproto/docker.py`
- `scripts/lib/atproto/firehose.py`
- `scripts/lib/atproto/report.py`
- `scripts/lib/atproto/seed.py`
- `scripts/scenarios/README.md`
- `scripts/scenarios/config/appview-config.json`
- `scripts/scenarios/config/pds-config.json`
- `scripts/scenarios/config/pds2-config.json`
- `scripts/scenarios/scenarios/01_account_lifecycle.py`
- `scripts/scenarios/scenarios/02_social_graph.py`
- `scripts/scenarios/scenarios/03_content_creation.py`
- `scripts/scenarios/scenarios/04_moderation_safety.py`
- `scripts/scenarios/scenarios/05_federation.py`
- `scripts/scenarios/scenarios/06_chat_dms.py`
- `scripts/scenarios/scenarios/07_blobs_uploads.py`
- `scripts/scenarios/scenarios/08_oauth_sessions.py`
- `scripts/scenarios/scenarios/09_firehose_streaming.py`
- `scripts/scenarios/scenarios/10_performance_resilience.py`
- `scripts/scenarios/scenarios/11_lab_oauth_login.py`
- `scripts/scenarios/scenarios/12_account_migration.py`
- `scripts/scenarios/scenarios/__init__.py`
- `tooling/test-audit-validator/scripts/audit_gate.py`
- `tooling/test-audit-validator/scripts/audit_summary.py`

## Nix Files

| Path | Decision | Notes |
|---|---|---|
| `flake.nix` | Revise | Keep root dev shells; add formatter, script hygiene tools (`shellcheck`, `shfmt`, `jq`), and optionally a `checks` target for shell syntax. |
| `flake.lock` | Leave | Keep lockfile paired with root flake. |
| `tooling/test-audit-validator/flake.nix` | Revise | Keep; add checks for Go tests and clarify ignored `.cache/` behavior. |
| `tooling/test-audit-validator/flake.lock` | Leave | Keep lockfile paired with tool flake. |
| `examples/tutorial-6-deployment/flake.nix` | Revise | Keep with tutorial; move to a production NixOS module later only if it becomes supported deployment surface. |

Ignored/generated Nix files under `tooling/test-audit-validator/.cache/` should remain ignored and untracked.

## Validation Plan

After each cleanup batch:

1. Run shell syntax over tracked shell scripts:

   ```bash
   git ls-files '*.sh' | xargs -n1 bash -n
   ```

2. Run JavaScript checks for script packages:

   ```bash
   node --check scripts/docs/generate_xrpc_coverage_report.cjs
   node --check scripts/docs/generate_xrpc_next_steps.cjs
   ```

3. Run repo quality wrappers that remain active:

   ```bash
   scripts/test/run-tests.sh
   scripts/build/quality_gate.sh
   ```

4. Run Nix checks where available:

   ```bash
   nix flake check
   nix flake check tooling/test-audit-validator
   ```

5. Re-scan for stale absolute paths and old source roots:

   ```bash
   rg -n '/Users/jack/Software/garazyk|ATProtoPDS/Sources|NSPds|build-linux/bin' scripts docs/scripts .opencode/tools examples
   ```

## Tracking

Record implementation as a sequence of deciduous actions under goal `1086`, one action per batch:

- Batch 1: syntax/security fixes.
- Batch 2: deletions and doc reference updates.
- Batch 3: moves with temporary compatibility wrappers.
- Batch 4: Nix revisions and checks.
- Batch 5: final validation outcome.
