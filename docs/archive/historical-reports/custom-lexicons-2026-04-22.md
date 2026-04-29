# Custom PDS Lexicon Schemas — Non-Standard XRPC Methods

**Date**: 2026-04-22
**Deciduous node**: #158
**Context**: These 8 XRPC methods are registered in the garazyk PDS dispatcher with working handlers, but have no corresponding lexicon JSON in the official `bluesky-social/atproto` repository. We created schemas matching our handler implementations.

## Why These Don't Exist Upstream

The official atproto repo has different method names or doesn't include these admin/PDS-specific endpoints:

| Our Method | Official Equivalent | Difference |
|------------|-------------------|------------|
| `tools.ozone.moderation.getSubjectStatus` | `com.atproto.admin.getSubjectStatus` | Ozone namespace vs admin namespace; different output schema |
| `tools.ozone.moderation.cancelScheduledAction` | `tools.ozone.moderation.cancelScheduledActions` | Singular (cancel by ID) vs plural (cancel by subject array) |
| `tools.ozone.server.updateConfig` | (none — only `getConfig` exists) | New endpoint for writing config |
| `com.atproto.admin.getServerStats` | (none) | PDS-specific server statistics |
| `com.atproto.admin.queryAuditLog` | (none) | PDS-specific audit log query |
| `com.atproto.admin.repairRepo` | (none) | PDS-specific repo repair |
| `com.atproto.admin.runBlobAudit` | (none) | PDS-specific blob audit |
| `com.atproto.admin.getBlobAuditStatus` | (none) | PDS-specific blob audit status |

## Schema Details

### tools.ozone.moderation.getSubjectStatus
- **Type**: query
- **Parameters**: `did` (did format), `uri` (at-uri format)
- **Output**: `{ status: ref to tools.ozone.moderation.defs#subjectStatusView }`
- **Handler**: `XrpcToolsOzonePack.m` — queries moderation service for subject status

### tools.ozone.moderation.cancelScheduledAction
- **Type**: procedure
- **Input**: `{ id: string (required) }` — the scheduled action ID to cancel
- **Output**: `{ success: boolean }`
- **Handler**: `XrpcToolsOzonePack.m:391-418` — cancels a single scheduled action by ID
- **Note**: Official repo has `cancelScheduledActions` (plural) which takes an array of DIDs

### tools.ozone.server.updateConfig
- **Type**: procedure
- **Input**: `{ settings: object }` — key-value pairs to update
- **Output**: `{ success: boolean }`
- **Handler**: `XrpcToolsOzonePack.m:1350-1371` — calls `updateServerSettings:updatedBy:error:`
- **Note**: Official repo only has `tools.ozone.server.getConfig`

### com.atproto.admin.getServerStats
- **Type**: query
- **Output**: `{ accountCount, repoCount, blobCount, lastIndexed }`
- **Handler**: `XrpcAdminMethods.m:366-387` — calls `getServerStatsWithError:`
- **Auth**: Admin only

### com.atproto.admin.queryAuditLog
- **Type**: query
- **Parameters**: `limit` (1-100, default 50), `cursor`, `adminDid` (did format)
- **Output**: `{ cursor, events: [com.atproto.admin.defs#auditLogEvent] }`
- **Handler**: `XrpcAdminMethods.m:389-419` — calls `queryAuditLog:limit:cursor:error:`
- **Auth**: Admin only

### com.atproto.admin.repairRepo
- **Type**: procedure
- **Input**: `{ did: string (required, did format) }`
- **Output**: `{ success: boolean, did: string }`
- **Handler**: `XrpcAdminMethods.m:421-466` — calls `forceReinitializeRepoForDid:error:`
- **Auth**: Admin only
- **Side effect**: Logs admin action as `REPAIR_REPO`

### com.atproto.admin.runBlobAudit
- **Type**: procedure
- **Input**: `{ type: string (default "consistency"), dryRun: boolean (default false) }`
- **Output**: `{ jobId: string, type: string, status: string }`
- **Handler**: `XrpcAdminMethods.m:468-499` — calls `startAuditWithType:dryRun:`
- **Auth**: Admin only

### com.atproto.admin.getBlobAuditStatus
- **Type**: query
- **Parameters**: `jobId` (string, required)
- **Output**: `{ jobId, status, progress, totalBlobs, processedBlobs, errorCount }`
- **Handler**: `XrpcAdminMethods.m:501-528` — calls `jobStatusForId:`
- **Auth**: Admin only

## Maintenance Notes

- If these methods are ever added to the official atproto repo, replace our custom schemas with the official ones
- The `id` field in each JSON must exactly match the NSID used in `registerMethod:` calls
- Handler implementations are the source of truth for input/output schemas — keep lexicons in sync
