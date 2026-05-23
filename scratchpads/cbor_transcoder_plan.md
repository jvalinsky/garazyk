# AppView CBOR Transcoder Plan

## Structured Info
- **Goal**: Resolve AppView Boot Crash from `NSData` feeding into `NSJSONSerialization`.
- **Target File**: `Garazyk/Sources/AppView/Server/Backfill/AppViewBackfillWorker.m`
- **Related Docs**: [scenario-failure-analysis-and-remediation.md](file:///Users/jack/Software/garazyk/scratchpads/scenario-failure-analysis-and-remediation.md)

## Mini Prompts
- Read the CBOR logic in `AppViewBackfillWorker.m`.
- Identify the exact `NSDictionary` that contains the CID bytes.
- Traverse the dictionary recursively to transcode any `NSData` byte arrays into base64 or `{"$link": "..."}` so that `NSJSONSerialization` succeeds without throwing exceptions.
