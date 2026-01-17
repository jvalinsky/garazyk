# Issue: Followers count API returns zero for everyone

## Summary
`ATProtoPDS/Sources/AppView/ActorService.m` stubbed `getFollowersCountForDID:` to always return `0` because the records table lacks the necessary column/index.

## Impact
- All actor profiles appear to have zero followers, which breaks UI metrics and any business logic that consumes follower counts.

## Proposed fix
- Extend the database schema (add a column or derive the count from `app.bsky.graph.follow` records) and add the corresponding query so the method returns the actual follower count.
