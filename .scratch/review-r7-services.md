# R7: AppView, Chat, Services & Bootstrap Review

## Summary
Systemic schema mismatch between AppViewRuntime wiring and AppViewDatabase schema — many services issue SQL against PDS-style tables that don't exist in the AppView DB. Several concrete logic bugs and one security issue (admin endpoints unauthenticated when secret is unset).

## Findings

### CRITICAL — AppView services reference PDS tables that don't exist in AppViewDatabase
- **File**: Garazyk/Sources/AppView/Server/AppViewRuntime.m, AppViewDatabase.m
- **Description**: `AppViewRuntime` wires several services to `AppViewDatabase`, but many of those services still issue SQL against PDS-style tables that do not exist in the AppView DB. `DraftService`, `ContactService`, `NotificationService`, `ActorService` preferences, `GraphService` mutes/starter packs, and `BookmarkService` all rely on tables/columns that are not present in `AppViewDatabase`.
- **Impact**: Large chunk of the AppView read/write surface will fail at runtime with `no such table` errors.
- **Recommendation**: Align the service layer with the actual AppView schema, or split AppView/PDS data access cleanly.

### HIGH — Admin endpoints are effectively unauthenticated when APPVIEW_ADMIN_SECRET is unset
- **File**: Garazyk/Sources/AppView/Server/Admin/AppViewAdminRoutePack.m
- **Description**: When `APPVIEW_ADMIN_SECRET` environment variable is not set, admin routes allow open access instead of refusing to start.
- **Impact**: Any request to admin endpoints is accepted without authentication in default configurations.
- **Recommendation**: If `APPVIEW_ADMIN_SECRET` is missing, admin routes should refuse to start instead of allowing open access.

### HIGH — NotificationService uses read API for write operations
- **File**: Garazyk/Sources/AppView/Services/NotificationService.m
- **Description**: `markNotificationsAsReadForActor:` and `putPreferencesForActor:` should use the update API, not the query API.
- **Impact**: Write operations may silently fail or have no effect.
- **Recommendation**: Switch to the correct update/write API for mutation operations.

### HIGH — AppViewGroupIndexer writes rows using schema that doesn't match AppViewDatabase
- **File**: Garazyk/Sources/AppView/Server/Indexers/AppViewGroupIndexer.m
- **Description**: The indexer writes to columns that do not exist in the AppView group tables.
- **Impact**: Group indexing will fail at runtime — group data won't be indexed.
- **Recommendation**: Align the indexer's SQL with the actual AppViewDatabase schema.

### MEDIUM — FeedService has bad reply-count URI parse and ignores feed generator URI
- **File**: Garazyk/Sources/AppView/Services/FeedService.m
- **Description**: Reply count URI parsing is broken, and the requested feed generator URI is ignored.
- **Impact**: Reply counts may be incorrect; custom feed generators won't work.
- **Recommendation**: Fix the URI parsing logic and honor the feed generator URI parameter.

### MEDIUM — ContactService hashes phone numbers without salt and has no abuse controls
- **File**: Garazyk/Sources/AppView/Services/ContactService.m
- **Description**: Phone numbers are hashed without a salt, making rainbow table attacks feasible. No rate limiting or abuse controls on contact discovery.
- **Impact**: Privacy risk — unsalted hashes can be reversed. Abuse vector for contact discovery.
- **Recommendation**: Add a server-side salt to phone number hashing. Add rate limiting for contact lookup endpoints.
