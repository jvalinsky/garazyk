---
phase: 19
title: Core decoder bounds and encoder cost
status: complete
agent: worker
depends_on: []
completed_at: 2026-07-27
commit: cd6530b2
---

# Phase 19: Core decoder bounds and encoder cost

## Progress

Executed in worktree `../garazyk-core` on branch `phase-19-20`, one commit per
slice per the loop protocol:

- Slice 1 (width defects in `ATProtoDagCBOR`): `2f21358e`
- Slice 2 (Base58 UTF-8 indexing + calloc checks): `727370e9`
- Slice 3 (base32/base58 encoder buffer construction): `cd6530b2`

All required rejection cases pass; golden CAR/STAR/MST/Interop fixtures
verified byte-identical (164 tests, 0 failures) confirming slice 3 is
behaviour-neutral. `deno task check`/`test` pass; `deno task lint` has 6
pre-existing failures unrelated to this phase (reproduced on unmodified
`main`). The full `AllTests` binary has 18 pre-existing failures in
`Network/AdminAuthSyncTests.m` that reproduce identically with this phase's
changes reverted (via `git stash`) — confirmed unrelated and outside this
phase's owner boundary. See workstream 01 § S11 gate notes for detail.

## Mission

Close the width defects in workstream 01 § S11 slices 1-3. The DAG-CBOR
decoder is entered from CAR import, PLC operations, STAR, `RepoCommit`, and
XRPC handlers — every one an untrusted path — and two of its length checks can
be defeated with a handful of bytes.

Note what is already correct, so you do not "fix" it: the decoder has a
working depth limit (`kMaxDecodeDepth = 64`, checked at `:454`), and
`Core/CID.m:303 readVarint` is properly bounded with a shift cap and an
overflow return. The gaps are **widths**, not depths or varints.

## Read first

- `docs/plans/workstreams/01-security-and-protocol-correctness.md` § S11
  (authoritative; if this prompt disagrees, the workstream wins)
- `Garazyk/Sources/Core/ATProtoDagCBOR.m` — `:577`, `:585`, `:617`, `:640`
- `Garazyk/Sources/Core/CID.m:303` — the varint reader, as the model for how
  bounded parsing should look in this codebase
- `fuzzing/` — the corpus that should gain the overflow input as a seed

## Scope and order

One coherent slice per commit.

1. **Width defects in `ATProtoDagCBOR`.**
   - `:585` bounds a byte string with `*index + len > length`, which wraps.
     Verified: `index=9`, `len=2^64-5` sums to `4`, the check passes, and
     `[NSData dataWithBytes:bytes + 9 length:2^64-5]` runs. Compare against
     remaining bytes instead (`len > length - *index`, after confirming
     `*index <= length`).
   - `:617` and `:640` hand an unvalidated 64-bit `count` to
     `arrayWithCapacity:`/`dictionaryWithCapacity:`. Every CBOR item needs at
     least one byte, so reject or clamp against the remaining input before
     allocating. This matters most on the Linux build, where GNUstep's
     `initWithCapacity:` allocates a real buffer.
   - `:577` computes `-(int64_t)(value + 1)`, which wraps to `0` at `2^64-1`
     and is undefined above `2^63-1`. DAG-CBOR restricts integers to the
     int64 range: reject out-of-range values rather than producing a wrong
     number in a content-addressed structure.
2. **`Base58` hardening.** `Core/Base58.m:76-83` indexes `string.UTF8String`
   (bytes) using `string.length` (UTF-16 units). It is safe today only because
   the `chars[i] & 0x80` guard rejects multi-byte input first — correct by
   accident. Use the buffer's own byte length. Check the `calloc` results at
   `:35` and `:93`.
3. **Encoder cost.** `Core/CID.m:343` and `Base58.m:61,64` emit one character
   per `appendFormat:@"%c"`, parsing a format string per character.
   `CID.stringValue` runs for every block touched by MST, CAR, and block
   storage. Build into a C buffer and construct the string once. This is a
   pure performance change — the output must be byte-identical.

## Acceptance gate

Decoder rejection cases, each asserting a clean error rather than a crash,
over-read, or large allocation:

- `5B FF FF FF FF FF FF FF FB` — the byte string whose declared length
  overflows the bounds check. This is the headline case; add it to the
  `fuzzing/` corpus as a permanent regression seed.
- A declared array count and a declared map count that each exceed the
  remaining input, asserting rejection **without** a large allocation.
- CBOR integers above `2^63-1` and the negative-integer edge at `2^64-1`.
- Base58 input containing multi-byte UTF-8, asserting rejection that does not
  depend on index coincidence.

Non-regression: existing golden CAR and STAR fixtures must remain
byte-identical. This phase must not change any valid encoding — if a fixture
moves, the change is wrong.

New suites need their header imported and the class registered in
`Garazyk/Tests/test_main.m` plus a cmake reconfigure, or they silently run
zero tests. Then the global gates:

```bash
deno task check
deno task lint
deno task test
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests
```

Bounded parallelism only (`--parallel 4`).

## Rollback

Each slice is a single-commit revert. Slice 1 only rejects inputs that
currently crash or over-allocate, so interop risk is minimal: if a real CAR
fails to import afterwards, that CAR was malformed — capture it as a fixture
rather than loosening the bound. Slice 3 is behaviour-neutral by definition;
if any encoded output changes, revert it.

## On completion

Update S11 slices 1-3 status in workstream 01 with commit hashes, then set
`status: complete` here.
