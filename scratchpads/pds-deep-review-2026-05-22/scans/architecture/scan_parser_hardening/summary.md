# Objective-C Parser Hardening Scan

- Root: .
- Scan paths: ./Garazyk/Sources/Repository ./Garazyk/Sources/Core
- Generated: 2026-05-22T18:10:10Z

## Counts
- Parse/decoder signals: 97
- Risky memory/range signals: 280
- Bounds/length signals: 548
- Integer/conversion signals: 517

## Prioritize first (parse + risky without bounds signal)
- ./Garazyk/Sources/Core/Base58.h
- ./Garazyk/Sources/Repository/STAR.h

## Notes
- File-level signal only; confirm exact operation-level guards.
