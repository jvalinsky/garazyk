# Agent Quick Reference

## Build & Test
```bash
xcodegen generate            # Regenerate project
xcodebuild -scheme AllTests build
./build/tests/AllTests      # Run tests
xcodebuild -scheme kaszlak build

## Scenario Testing
```bash
./scripts/run_scenarios.ts --list
./scripts/run_scenarios.ts 01 02
```
```
