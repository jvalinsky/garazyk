# TCP Socket Exhaustion Plan

## Structured Info
- **Goal**: Enable `nw_parameters_set_reuse_local_address` to prevent `TIME_WAIT` locks.
- **Target File**: `Garazyk/Sources/Network/ATProtoNetworkTransportMac.m`
- **Related Docs**: [scenario-failure-analysis-and-remediation.md](file:///Users/jack/Software/garazyk/scratchpads/scenario-failure-analysis-and-remediation.md)

## Mini Prompts
- Edit `Garazyk/Sources/Network/ATProtoNetworkTransportMac.m`.
- Add `nw_parameters_set_reuse_local_address(parameters, true);` directly after creating the parameters object in both the listener setup routines.
- This ensures the listener ignores `TIME_WAIT` states from rapidly killed services on the same port.
