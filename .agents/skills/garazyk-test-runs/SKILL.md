---
name: garazyk-test-runs
description: Choose the right scope for a Garazyk test run and execute it correctly. Use before running any Objective-C test — "run the tests", "verify this change", "did I break anything", "check it still passes", "run AllTests" — and whenever a full-suite run is being considered. Covers filtered/category/sharded runs, the affected-tests helper, gated tests, and when the full suite is actually required.
---

# Choosing a Garazyk Test Run

`AllTests` is one binary holding ~500 classes / ~3400 gated tests. A full
`--gated=run` pass costs **~10 minutes of wall clock**; a filtered run of the
classes a change actually touches costs **under a second to a few seconds**.

Running the full suite to check a three-line change wastes ~10 minutes of an
agentic session. Running only a filter before pushing misses cross-cutting
breakage. The rule is: **iterate filtered, gate full** — filtered runs during
the edit/fix loop, one full run before you hand work back or push.

## Decision procedure

Work top-down and stop at the first row that matches.

| Situation | Run |
| --- | --- |
| Iterating on a change; want the fastest signal | `scripts/test/affected-tests.sh --run` |
| You know the class(es) | `./build/tests/AllTests --gated=run -f ClassA -f ClassB` |
| You know the one method | `./build/tests/AllTests --gated=run -XCTest 'ClassA/testFoo'` |
| Change is confined to one source area | `./build/tests/AllTests --gated=run --category Network` |
| Pre-push / pre-handoff, or you touched shared infra | `ctest --test-dir build --output-on-failure -j4 -E '^AllTests$'` |
| Investigating cross-test pollution / ordering flake | `./build/tests/AllTests --gated=run --shuffle --seed 1234` |

`-f` is a glob on the class name and is repeatable (`-f 'Relay*'` works).
`--category` takes a comma-separated list and maps to the test's source
directory — `--list -v` prints `ClassName (Category)`.

## Start here: the affected-tests helper

```bash
scripts/test/affected-tests.sh --run
```

It diffs the working tree (or `scripts/test/affected-tests.sh origin/main` for a
branch), maps changed sources to the test classes that name them, intersects
that with the runner's registered classes, and runs exactly those. Typical
selection is 4–40 of ~500 classes.

Use `--classes` to see the selection without running it, or `--args` to get the
`-f` flags to paste into your own invocation.

It over-includes by design and is name-based, so it is a fast pre-merge filter,
never a substitute for the pre-push full run.

## The full run — do it right

CI runs the **sharded** path, and so should you:

```bash
ctest --test-dir build --output-on-failure -j4 -E '^AllTests$'
```

`-E '^AllTests$'` is not optional. ctest registers both the monolithic
`AllTests` entry *and* `AllTestsShard{1..4}of4`; a bare
`ctest --test-dir build` runs the whole suite **twice** — once monolithic, once
as four shards — and without `-j` it runs them serially. That is the single
most common way to turn a 10-minute suite into a 30-plus-minute one.

The single-process equivalent (no ctest, no admin-UI asset gate) is:

```bash
./build/tests/AllTests --gated=run
```

## Gated tests: a filtered run can silently run nothing

Classes needing sockets or external services are tagged `integration` or
`socket` and are **skipped unless you pass `--gated=run`**. Without it the
runner prints `Tests run: 0 / Failures: 0` plus a `Skipped gated test classes`
line — which scans as green but proved nothing.

**Put `--gated=run` on every run you intend to believe**, filtered ones
included. `--gated=include` runs them and marks them in the output.

Check what is gated before trusting a narrow run:

```bash
./build/tests/AllTests --list | grep 'gated:'
```

## Before you conclude "the tests pass"

- **A new test file needs two steps.** Test sources are picked up by
  `file(GLOB_RECURSE ...)`, so a new `.m` needs `cmake -S . -B build` re-run —
  an incremental build will not see it — *and* its class name added to the
  `testClasses` array in `Garazyk/Tests/test_main.m`. Miss either and the suite
  runs your test zero times and still reports success. Verify with:
  ```bash
  PDS_TEST_REGISTRATION_AUDIT=1 ./build/tests/AllTests
  ```
- **Check the run count, not just the failure count.** `Tests run: 0` with
  `Failures: 0` is not a pass. Confirm the number of tests you expected
  actually executed.
- **Build with bounded parallelism.** `--parallel 4`; unbounded builds exhaust
  memory on 16 GB machines.
- **Watch free disk.** SQLite-backed tests fail with `SQLITE_FULL` when the
  volume is near capacity, which looks like a code failure and is not one.

## When the full suite is genuinely required

Run it — do not try to be clever — when the change touches:

- `Garazyk/Tests/test_main.m`, the registration array, or gating logic
- `Compat/` (both platforms' XCTest shim and shared primitives)
- `Database/` migrations, `PDSMigrationManager`, or schema
- `ATProtoServiceContainer`, route-pack registration, or `XrpcDispatcher`
- shared crypto (`CryptoUtils`, key managers) or auth base classes
- anything in `Core/` that most modules link

Also run it before pushing, before opening a PR, and whenever you are about to
tell the user the work is done.

## Other suites

These are separate from `AllTests` and are not covered by any of the above:

```bash
deno task check && deno task lint && deno task test
```

Standalone binaries excluded from `AllTests`: `migration_tests`,
`connection_pool_tests`, `record_cache_tests` (plus `SecItemLinuxStoreTests` on
Linux).

Scenario tests need Docker and are slower still — see the
`agent-scenario-testing` skill rather than reaching for `hamownia` directly.

## Related

- `garazyk-testing` — fixtures, mock patterns, env gating, how to *write* tests
- `garazyk-scenario-triage` — triaging failed scenario runs
