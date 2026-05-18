# Subagent Coordination

## Assignments

- Worker 1: Phase 1 Gruszka generated exact types and binary XRPC routing.
- Worker 2: Phase 2 firehose subscribeRepos frame decoding and scenarios.
- Worker 3: Phase 3 dashboard report import validation.

## Status

- Main created Deciduous nodes and scratchpads.
- Workers may run in parallel because their write sets are disjoint, except generated Gruszka files are owned only by Worker 1.

## Merge Notes

- Main will review worker diffs before final integration.
- Main will run package-wide checks after all workers return.
- If a worker needs files outside its write set, it must stop and report the required edit.
