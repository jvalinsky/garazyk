# Stubbed Behaviors to Track

1. `ATProtoPDS/Sources/Network/PDSNetworkTransportLinux.m:85`
   - The Linux transport will always short-circuit with `Client connection not implemented` when `_sockfd` is `-1`, so client/outbound Socket connections never become ready.
   - Impact: The Linux target cannot establish any client connections and therefore cannot act as a PDS peer.
   - Next step: implement the client-side connect/read loop (or defer the Linux target until the full transport is ready).

2. `ATProtoPDS/Sources/App/PDSController.m:746`, `:764`, `:782`, `:790`
   - Admin (`takeDownAccount`, `reinstateAccount`), moderation (`moderateAccount`, `moderateRecord`), and labeling (`createLabel`, `getLabels`) methods immediately return `ATProtoErrorCodeNotImplemented`.
   - Impact: These XRPC endpoints are surface-complete but effectively fail, so API consumers cannot perform moderation workflows.
   - Next step: implement the actual moderation/labeling workflows or gate these endpoints until they are ready.

3. `ATProtoPDS/Sources/App/Explore/ExploreHandler.m:1983`
   - CIDv1 entries with base58btc (`"z"`) multibase prefixes stop early with a `decodingStatus` of `"partial - base58 decoding not implemented"`.
   - Impact: Exploring or validating CIDv1 resources that use base58btc cannot be decoded.
   - Next step: plug in a base58btc decoder or reuse a shared CID library so `ExploreHandler` can emit proper CID metadata.

4. `ATProtoPDS/Sources/AppView/ActorService.m:185`
   - `getFollowersCountForDID:` always returns `0` as a stub because the necessary schema/index is missing.
   - Impact: Actor views report zero followers even when accounts have followers, skewing usage statistics.
   - Next step: add a follower-count query/index (or derive counts from `graph.follow` records) so the method returns accurate values.

Please file follow-up work items if you want these tracked in an issue tracker, and reopen this file if the list grows.
