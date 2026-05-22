---
name: garazyk-fuzzing
description: Run, extend, and triage Garazyk fuzzers and crash reproductions. Covers corpus generation, scripts/fuzzing, fuzzing/harness, sanitizer runs, minimization, known-bad signatures, and turning crashes into XCTest regressions.
---

# Garazyk Fuzzing

Use this skill for fuzzing work, sanitizer failures, parser hardening, corpus updates, crash minimization, and converting fuzz findings into durable tests.

## Key files

- Fuzz scripts: `scripts/fuzzing/`, `build/run-fuzzers-limited.sh`, `build/run-fuzzers-extended.sh`
- Harnesses: `fuzzing/harness/*.m`
- Mutators: `fuzzing/mutators/*.mm`
- Corpus generation: `fuzzing/corpus/XrpcCorpusGenerator.m`, `scripts/fuzzing/generate-xrpc-corpus.sh`
- Dictionaries/grammars: `fuzzing/dictionaries/`, `fuzzing/grammars/`
- Standalone driver: `fuzzing/standalone_driver.cpp`
- Known bad: `fuzzing/known-bad/README.md`, `fuzzing/known-bad/signatures.txt`
- Security runner: `scripts/test/security_test_runner.sh`
- Regression tests: `Garazyk/Tests/` and `Garazyk/Tests/test_main.m`

## Safety and context rules

- Fuzzer output can be huge. Summarize logs with filters; do not paste raw output.
- Keep crashing inputs in `fuzzing/known-bad/` or a targeted regression fixture, not in ad-hoc temp paths.
- Never ignore sanitizer findings as flaky until a minimized reproducer proves the failure mode.
- Prefer deterministic repro commands before changing production code.

## Fuzzing workflow

### 1. Pick the target boundary

Map the bug/risk to a harness:

| Boundary | Likely harness/dictionary |
| --- | --- |
| XRPC routing/dispatch | `FuzzXrpcDispatcher`, `xrpc.dict` |
| HTTP parser | `FuzzHttp1Parser`, `http.dict` |
| CBOR/DAG-CBOR | `FuzzCBORDecoder`, `cbor.dict` |
| JWT/DPoP/OAuth | `FuzzJWT`, `FuzzDPoP`, `FuzzOAuth`, `jwt.dict` |
| MST/repository | `FuzzMST` |
| blobs/MIME | `FuzzBlob`, `FuzzMimeTypeValidator` |
| firehose | `FuzzFirehose` |
| database | `FuzzPDSDatabase` |
| lexicon validation | `FuzzATProtoLexiconValidator` |

### 2. Generate or update corpus

Use existing corpus scripts and dictionaries before hand-writing many cases:

```bash
scripts/fuzzing/generate-xrpc-corpus.sh
```

Good corpus entries cover:

- minimal valid request
- missing required field
- wrong type
- boundary sizes
- malformed Unicode/percent encoding
- duplicate keys or conflicting params
- nested/recursive structures
- known protocol examples

### 3. Run bounded fuzzing first

Start with short runs that fit local feedback loops:

```bash
scripts/fuzzing/run-fuzzers-limited.sh
scripts/test/security_test_runner.sh
```

For generated build helpers:

```bash
build/run-fuzzers-limited.sh
build/run-fuzzers-extended.sh
```

If the command may produce large output, save logs to a file and summarize with `rg`/`tail`.

### 4. Use sanitizers deliberately

For memory issues, run the sanitizer-specific test path:

```bash
scripts/test/run-asan-tests.sh
scripts/test/run-leaks.sh
```

Capture:

- exact command
- target harness
- seed/input path
- sanitizer stack top frames
- git revision
- platform (macOS/GNUstep/Linux)

### 5. Minimize crashers

Use existing minimizer support where available (`FuzzMinimizer`) or reduce manually:

1. preserve the original crasher
2. remove unrelated bytes/fields
3. confirm the same stack/signature still reproduces
4. record the minimized input and command
5. update `known-bad/signatures.txt` if appropriate

A minimized crasher should be small enough to inspect and commit if it is not sensitive.

## Turning a crash into a fix

### 1. Reproduce outside the fuzzer

Before editing production code, create a deterministic command or XCTest that fails reliably. If direct harness execution is awkward, write the smallest XCTest around the parser/validator/service boundary.

### 2. Fix at the boundary

Good fixes usually:

- reject invalid input earlier
- add length/depth/count limits
- make parser state transitions explicit
- avoid integer overflow/truncation
- handle nil/empty data without crashing
- avoid unbounded recursion or allocation
- preserve existing valid behavior

Do not paper over with broad `@try/@catch` unless the boundary is intentionally exception-safe and tests prove error mapping.

### 3. Add XCTest regression

Regression test should include:

- minimized input fixture or inline bytes/string
- assertion that parsing fails safely or returns expected error
- no dependency on fuzzer runtime
- class registered in `Garazyk/Tests/test_main.m`

Use `garazyk_find_test_class` to check registration.

### 4. Re-run target and related tests

Minimum:

```bash
garazyk_build_test --filter RelevantTests
scripts/fuzzing/run-fuzzers-limited.sh
```

If parser/security-sensitive, run sanitizer or security runner too.

## Triage report format

```md
## Fuzz triage

- Target:
- Command:
- Input/crasher:
- Failure signature:
- First bad frame:
- Boundary:

Evidence:
- ...

Theory:
...

Fix:
...

Regression:
...
```

## Definition of done

- Crasher is minimized or clearly captured.
- Failure reproduces deterministically.
- Root cause is fixed at the parser/validation boundary.
- XCTest regression added and registered.
- Target fuzzer/sanitizer run no longer reproduces.
- Known-bad/signature docs updated if relevant.
