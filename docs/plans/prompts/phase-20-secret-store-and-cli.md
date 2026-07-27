---
phase: 20
title: Linux secret store encryption and destructive CLI correctness
status: complete
agent: worker
depends_on: []
---

# Phase 20: Linux secret store encryption and destructive CLI correctness

## Progress

2026-07-27: Completed slices 4-7 in independent commits: `194a2580` (encrypted
secret-store migration), `0572e133` (honest recursive `nuke-data`),
`84cb8ce3` (environment password input and argv warning), and `52cda6ea`
(signal-safe password prompt hygiene). The Linux secret-store model is
recorded in ADR 0013 and the deployment guide.

## Mission

Execute workstream 01 § S11 slices 4-7: encrypt the Linux secret store,
make `nuke-data` delete what it says it deletes, and stop documenting
passwords on the command line.

Two of these are trust problems rather than crashes. `SecItemLinuxStore`
emulates an API that is hardware-backed and encrypted on Apple, but stores
plaintext on Linux — callers cannot tell which guarantee they got.
`nuke-data` prints `✅ All data has been nuked` while every per-account
database survives. In both cases the code is confidently wrong, which is worse
than visibly broken.

## Read first

- `docs/plans/workstreams/01-security-and-protocol-correctness.md` § S11
  (authoritative)
- `Garazyk/Sources/Compat/PlatformShims/Security/SecItemLinuxStore.m` in full
- `Garazyk/Sources/CLI/PDSCLINukeCommand.m:92-143`
- `Garazyk/Sources/App/PDSApplication.m:333` and
  `Garazyk/Sources/Database/Pool/DatabasePool.m:93-134` — together these
  define the actual on-disk layout that `nuke-data` fails to match
- `Garazyk/Sources/CLI/PDSCLIInputHelper.m:48-73` — the correct password
  prompt that already exists

## Decisions already taken (do not re-litigate)

- Linux secrets are encrypted at rest with an **operator-supplied key**, from
  an environment variable or key file read at startup. OS-keyring integration
  was considered and rejected for its runtime dependency in minimal
  containers. The key's location is an explicit, documented operator
  responsibility.

## Scope and order

One coherent slice per commit. Slice 4 first, since it is the one with a
migration.

4. **Encrypt the Linux secret store.** Encrypt the property-list blobs
   currently written in plaintext (`:136-169`, `:281-307`). Requirements:
   a reader that still consumes the old plaintext format for at least one
   release; a migration that rewrites existing stores; and a **startup failure
   when a store exists but no key is supplied** — never a silent fall back to
   plaintext. Keep the existing `0700`/`0600` permissions (`:64`, `:74`);
   encryption is in addition to them, not instead.
5. **Make `nuke-data` honest.** The hardcoded list at `:92-98` contains `di`,
   which matches no directory. Actor stores live at
   `{dataDir}/{method}/{prefix}/{did}` — under `plc/`, `web/`, or `key/`, in
   extension-less files named `did:plc:...`, two levels down — so neither that
   list nor the non-recursive suffix loop at `:121-143` touches them. Derive
   the deletion set from the same layout the pool writes rather than a
   hardcoded guess, delete recursively, and make the summary reflect reality:
   it must not print success while items remain. Note that `blobs`, `service`,
   `sequencer`, and `did_cache` are currently deleted correctly — the failure
   mode is a half-wiped instance, so verify the end state, not just the exit
   code.
6. **Stop documenting argv passwords.** `PDSCLIAccountCommand.m:225` and
   `PDSCLIAdminCommand.m:150` accept `--password`, and the help text at
   `PDSCLIAccountCommand.m:55` and `PDSCLIAdminCommand.m:42` demonstrates it.
   Arguments appear in `ps`, shell history, and process accounting. Provide an
   automation-safe input (stdin, environment variable, or file), remove the
   argv form from the examples, and warn if it is used.
7. **Password prompt hygiene.** `PDSCLIInputHelper.m:56-65` restores terminal
   echo on the success and EOF paths but not on signal, so `Ctrl-C` mid-prompt
   leaves the terminal unusable. Install a handler that restores it, and clear
   the buffer at `:62` after use.

## Acceptance gate

- **Secret store:** a secret written in the old plaintext format is readable
  after migration; a fresh store round-trips write→read; startup fails loudly
  when a store exists and no key is supplied; the on-disk file contains no
  recognisable plaintext secret material afterwards.
- **`nuke-data`:** against a scratch data directory populated with at least
  two account databases plus blobs and the service database, the command
  leaves **zero** account databases behind. A deliberately undeletable item
  (read-only parent) must produce an accurate failure summary, not a success
  message.
- **Passwords:** no documented path places a password in argv; the interactive
  prompt still works; `Ctrl-C` during the prompt leaves the terminal with echo
  restored.

New suites need registration in `Garazyk/Tests/test_main.m` plus a cmake
reconfigure. Then the global gates:

```bash
deno task check
deno task lint
deno task test
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests
```

Bounded parallelism only (`--parallel 4`). Run the Linux Docker gate —
`SecItemLinuxStore` compiles only on the non-Apple branch, so slice 4 is
untested by a macOS-only run.

## Rollback

Slice 4 changes the on-disk secret format and is the risky one: ship the
migration and a verified round-trip before removing any plaintext-reading
path, and keep the old-format reader for at least one release. If the key is
lost, the secrets are unrecoverable — say so in the ADR and the operator docs.

Slice 5 makes a destructive command genuinely destructive. Test only against a
scratch data directory, never a real one, and keep it behind the existing
`--confirm` gate.

Slices 6-7 are independent single-commit reverts.

## On completion

Write the ADR recording the Linux secret-storage model: what the key is, where
it comes from, what happens when it is missing or lost, the migration path,
and the explicit statement that Linux protection is operator-key-based rather
than hardware-backed. Update S11 slices 4-7 status in workstream 01 with
commit hashes, then set `status: complete` here.
