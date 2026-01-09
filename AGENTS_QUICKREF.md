# Agent Quick Reference

## Bead (Issue Tracking)
```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Security Testing
```bash
make clang-tidy              # Static analysis
make scan-build              # Static analyzer
make fuzz-all               # Build all sanitizers
make run-fuzzers            # Run fuzzers (limited)
```

## Build & Test
```bash
make build
make test-unit              # Run unit tests
xcodebuild test -scheme AllTests  # Tests with coverage
xcodegen generate           # Regenerate project
```
