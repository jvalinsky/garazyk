# Project Tasks

## Context
We are currently focused on implementing the core PDS/PLC functionality. These tasks capture the follow-up work needed for stubbed paths that fall outside of the current scope or are necessary for long term parity.

## Tasks
1. **Track Linux transport client implementation**  
   - Reference: `ATProtoPDS/Sources/Network/PDSNetworkTransportLinux.m:77-100`  
   - Reason: The client path (`_sockfd == -1`) currently fails with `Client connection not implemented`. Implementing this is a prerequisite to shipping a Linux target that can participate as a client PDS.

2. **Track regularization of moderation & labeling APIs**  
   - Reference: `ATProtoPDS/Sources/App/PDSController.m:746-793`  
   - Reason: Admin/moderation/labeling endpoints immediately return `ATProtoErrorCodeNotImplemented`. They should either be implemented or gated before declaring those XRPC endpoints production-ready.

3. **Track CIDv1 base58btc decoding for explorer tooling**  
   - Reference: `ATProtoPDS/Sources/App/Explore/ExploreHandler.m:1965-1995`  
   - Reason: Explore currently aborts base58btc (`z`) decoding, so CIDv1 data cannot be inspected via the UI. Integrating base58 decoding enables better tooling diagnostics.

4. **Track follower count query implementation**  
   - Reference: `ATProtoPDS/Sources/AppView/ActorService.m:150-190`  
   - Reason: `getFollowersCountForDID:` is stubbed to return `0`, which causes downstream UI/analytics to think no accounts have followers. Adding a true count query or derived calculation will improve accuracy.

Only the Linux/PLC work that keeps the PDS/PLC core running is in scope now; treat other tasks as backlog.
