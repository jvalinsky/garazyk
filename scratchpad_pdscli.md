# PDSCLIAccountCommandTests Analysis

## Problem
Account creation via the CLI test harness returns `rc=1` and fails. 13 tests are failing in `PDSCLIAccountCommandTests`.

## Root Cause
The `PDSCLIAccountCommandTests` run the CLI with a mocked environment. The PDS tests usually set `PLC_URL="mock"` to use the local mock PLC directory instead of the real one. However, the CLI's account creation logic might not be parsing or honoring this environment variable correctly when executing the `kaszlak account create` command, causing it to attempt reaching a non-existent or remote PLC server which fails and returns a non-zero exit code (`rc=1`).

## Solution Choices
1. **Fix CLI environment variable handling:** Ensure that `PLC_URL` (or the equivalent variable read by the CLI) is properly injected and respected when the CLI commands are executed.
2. **Mock the `PDSAccountService` at the CLI layer:** Alternatively, intercept the account service directly in the CLI tests, although injecting the correct environment variable is closer to the real execution path.

## Decision
We will inspect how the environment variables are passed to the `kaszlak` CLI runner in the tests and ensure `PLC_URL="mock"` is correctly propagated so the CLI uses the mocked directory, resolving the `rc=1` errors during account creation.
