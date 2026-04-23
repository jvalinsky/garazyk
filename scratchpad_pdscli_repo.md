# PDSCLIRepoCommandTests Analysis

## Problem
8 tests are failing in `PDSCLIRepoCommandTests`, indicating record creation via the CLI is failing.

## Root Cause
When creating a record using the CLI, if the `rkey` is not explicitly provided, it might either be missing where it's required (for non-post collections) or auto-generated incorrectly, leading to rejection by the local repo handler. Additionally, Auth headers might be malformed or missing if the CLI command doesn't inject them correctly based on the session state.

## Solution Choices
1. **Fix `rkey` auto-generation in CLI:** Provide proper fallback or error handling for non-post collections when no `rkey` is provided in the `kaszlak repo create-record` command.
2. **Update tests to provide `rkey`:** If the CLI design intentionally requires `rkey` for non-post collections, update the tests to supply one. 

## Decision
We will review `PDSCLIRepoCommandTests` and the repo creation command to understand if the test is attempting an invalid operation (creating a non-post record without an rkey) or if the CLI itself is failing to auto-generate the `rkey` (e.g. TID) when it should. If the latter, we'll fix the CLI logic; if the former, we'll update the test.
