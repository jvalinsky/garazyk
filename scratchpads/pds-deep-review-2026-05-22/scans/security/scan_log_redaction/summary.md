# Objective-C Log Redaction Scan

- Root: .
- Scan path: ./Garazyk/Sources
- Generated: 2026-05-22T18:10:03Z

## Counts
- Logging signals: 259
- Sensitive identifier signals: 1884
- Header/token literal signals: 62

## Prioritize first (logging + sensitive identifiers)
- ./Garazyk/Sources/App/PDSApplication.m
- ./Garazyk/Sources/CLI/PDSCLIAccountCommand.m
- ./Garazyk/Sources/CLI/PDSCLIAdminCommand.m
- ./Garazyk/Sources/CLI/PDSCLIInitCommand.m
- ./Garazyk/Sources/CLI/PDSCLIInputHelper.m
- ./Garazyk/Sources/CLI/PDSCLIOAuthCommand.m
- ./Garazyk/Sources/CLI/PDSCLIServeCommand.m
- ./Garazyk/Sources/Debug/GZLogger.m

## Secondary priority (logging + auth header literals)
- ./Garazyk/Sources/Admin/AdminMiddleware.m

## Notes
- False positives are expected; inspect exact logged payloads.
