# Quality Gates Workflow

This workflow defines the mandatory checks that must pass before any code is pushed to the remote repository.

## Steps

1. **Generate Project**: Run `xcodegen generate` and ensure it succeeds.
2. **Build All Tests**: Run `xcodebuild -scheme AllTests build` and ensure it succeeds.
3. **Run All Tests**: Execute `./build/tests/AllTests` and verify 0 failures.
4. **Build Production Binary**: Run `xcodebuild -scheme kaszlak build` and ensure it succeeds.
5. **Verify Fuzzers**: If any fuzzing-related code or libraries were modified, ensure fuzzers build successfully.

## Exit Criteria
- All build commands return exit code 0.
- All tests pass with 0 failures.
