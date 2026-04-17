# ATProto/Bluesky tools.ozone.* Endpoints Documentation

Complete specification of all Ozone moderation and administration endpoints from the ATProto lexicon files.

**Total Endpoints: 47** (excluding 9 definition files)

## Table of Contents

1. [Communication Templates](#communication-templates) - 4 endpoints
2. [Hosting](#hosting) - 1 endpoint
3. [Moderation](#moderation) - 15 endpoints
4. [Safelink (URL Safety)](#safelink-url-safety) - 5 endpoints
5. [Server](#server) - 1 endpoint
6. [Set Management](#set-management) - 6 endpoints
7. [Settings](#settings) - 3 endpoints
8. [Signature (Threat Detection)](#signature-threat-detection) - 3 endpoints
9. [Team Management](#team-management) - 4 endpoints
10. [Verification](#verification) - 3 endpoints
11. [Common Patterns](#common-patterns)

---

## Communication Templates

Communication template management for reusable email/message templates used in moderation actions.

### tools.ozone.communication.createTemplate

**Type:** `procedure` (POST)
**Description:** Create a new, re-usable communication (email for now) template.
**Auth Required:** Admin role

**Input Parameters (POST body):**
- `name` (string, required) - Name of the template
- `subject` (string, required) - Subject of the message, used in emails
- `contentMarkdown` (string, required) - Content of the template, markdown supported, can contain variable placeholders
- `lang` (string, optional) - Message language (language format)
- `createdBy` (string/did, optional) - DID of the user who is creating the template

**Output:** `tools.ozone.communication.defs#templateView`

**Errors:**
- `DuplicateTemplateName` - A template with this name already exists

---

### tools.ozone.communication.deleteTemplate

**Type:** `procedure` (POST)
**Description:** Delete a communication template.
**Auth Required:** Admin role

**Input Parameters (POST body):**
- `id` (string, required) - Template ID to delete

**Output:** None

---

### tools.ozone.communication.listTemplates

**Type:** `query` (GET)
**Description:** Get list of all communication templates.
**Auth Required:** Yes

**Input Parameters:** None

**Output:**
- `communicationTemplates` (array of `tools.ozone.communication.defs#templateView`) - List of all templates

---

### tools.ozone.communication.updateTemplate

**Type:** `procedure` (POST)
**Description:** Update an existing communication template. Allows passing partial fields to patch specific fields only.
**Auth Required:** Admin role

**Input Parameters (POST body):**
- `id` (string, required) - ID of the template to be updated
- `name` (string, optional) - Name of the template
- `subject` (string, optional) - Subject of the message
- `contentMarkdown` (string, optional) - Content of the template
- `lang` (string, optional) - Message language
- `updatedBy` (string/did, optional) - DID of the user who is updating the template
- `disabled` (boolean, optional) - Whether template is disabled

**Output:** `tools.ozone.communication.defs#templateView`

**Errors:**
- `DuplicateTemplateName` - Another template with this name already exists

---

## Hosting

Account history and identity tracking.

### tools.ozone.hosting.getAccountHistory

**Type:** `query` (GET)
**Description:** Get account history, e.g. log of updated email addresses or other identity information.
**Auth Required:** Admin/Moderator role

**Input Parameters (Query params):**
- `did` (string/did, required) - The DID to get history for
- `events` (array of strings, optional) - Filter by event types: `accountCreated`, `emailUpdated`, `emailConfirmed`, `passwordUpdated`, `handleUpdated`
- `cursor` (string, optional) - Pagination cursor
- `limit` (integer, optional) - Max results (1-100, default 50)

**Output:**
- `events` (array) - Array of event objects with details, createdBy, createdAt
- `cursor` (string, optional) - Next page cursor

**Event Types:**
- `accountCreated` - Contains email, handle
- `emailUpdated` - Contains new email
- `emailConfirmed` - Contains confirmed email
- `passwordUpdated` - No additional data
- `handleUpdated` - Contains new handle

---

## Moderation

Core moderation functionality including events, actions, reports, and subject management.

### tools.ozone.moderation.emitEvent

**Type:** `procedure` (POST)
**Description:** Take a moderation action on an actor.
**Auth Required:** Moderator role or higher

**Input Parameters (POST body):**
- `event` (union, required) - One of: modEventTakedown, modEventAcknowledge, modEventEscalate, modEventComment, modEventLabel, modEventReport, modEventMute, modEventUnmute, modEventMuteReporter, modEventUnmuteReporter, modEventReverseTakedown, modEventResolveAppeal, modEventEmail, modEventDivert, modEventTag, accountEvent, identityEvent, recordEvent, modEventPriorityScore, ageAssuranceEvent, ageAssuranceOverrideEvent, revokeAccountCredentialsEvent, scheduleTakedownEvent, cancelScheduledTakedownEvent
- `subject` (union, required) - `com.atproto.admin.defs#repoRef` or `com.atproto.repo.strongRef`
- `createdBy` (string/did, required) - DID of moderator creating the event
- `subjectBlobCids` (array of cid strings, optional) - Specific blob CIDs related to the action
- `modTool` (object, optional) - Moderation tool information
- `externalId` (string, optional) - External ID for deduplication from external systems

**Output:** `tools.ozone.moderation.defs#modEventView`

**Errors:**
- `SubjectHasAction` - Subject already has a conflicting action
- `DuplicateExternalId` - An event with the same external ID already exists for the subject

---

### tools.ozone.moderation.queryStatuses

**Type:** `query` (GET)
**Description:** View moderation statuses of subjects (record or repo).
**Auth Required:** Moderator role or higher

**Input Parameters (Query params):**
- `subject` (string/uri, optional) - The subject to get status for
- `comment` (string, optional) - Search subjects by keyword from comments
- `reportedAfter` / `reportedBefore` (datetime, optional) - Filter by report time
- `reviewedAfter` / `reviewedBefore` (datetime, optional) - Filter by review time
- `hostingDeletedAfter` / `hostingDeletedBefore` (datetime, optional) - Filter by deletion time
- `hostingUpdatedAfter` / `hostingUpdatedBefore` (datetime, optional) - Filter by update time
- `hostingStatuses` (array of strings, optional) - Filter by hosting status
- `includeMuted` (boolean, optional) - Include muted subjects (default false)
- `onlyMuted` (boolean, optional) - Only return muted subjects
- `reviewState` (string, optional) - Filter by review state: reviewOpen, reviewClosed, reviewEscalated, reviewNone
- `ignoreSubjects` (array of uris, optional) - Subjects to exclude
- `lastReviewedBy` (string/did, optional) - Filter by moderator who last reviewed
- `sortField` (string, optional) - Sort by: lastReviewedAt, lastReportedAt, reportedRecordsCount, takendownRecordsCount, priorityScore (default: lastReportedAt)
- `sortDirection` (string, optional) - asc or desc (default: desc)
- `takendown` (boolean, optional) - Filter by takedown status
- `appealed` (boolean, optional) - Filter unresolved appeals
- `tags` (array of strings, optional) - Filter by tags (OR within array, use && for AND)
- `excludeTags` (array of strings, optional) - Exclude these tags
- `collections` (array of nsid, optional) - Filter by collection type (max 20)
- `subjectType` (string, optional) - Filter by type: account or record
- `includeAllUserRecords` (boolean, optional) - Include all records from the subject's account
- `queueCount` / `queueIndex` / `queueSeed` (optional) - Queue-based filtering for load distribution
- `minAccountSuspendCount` (integer, optional) - Minimum account suspension count
- `minReportedRecordsCount` (integer, optional) - Minimum reported records
- `minTakendownRecordsCount` (integer, optional) - Minimum takedowns
- `minPriorityScore` (integer 0-100, optional) - Minimum priority score
- `minStrikeCount` (integer, optional) - Minimum strike count
- `ageAssuranceState` (string, optional) - Filter by age assurance: pending, assured, unknown, reset, blocked
- `limit` (integer, optional) - Max results (1-100, default 50)
- `cursor` (string, optional) - Pagination cursor

**Output:**
- `subjectStatuses` (array of `tools.ozone.moderation.defs#subjectStatusView`)
- `cursor` (string, optional)

---

### tools.ozone.moderation.queryEvents

**Type:** `query` (GET)
**Description:** List moderation events related to a subject.
**Auth Required:** Moderator role or higher

**Input Parameters (Query params):**
- `types` (array of strings, optional) - Filter by event types (fully qualified, e.g., tools.ozone.moderation.defs#modEventTakedown)
- `createdBy` (string/did, optional) - Filter by creator DID
- `subject` (string/uri, optional) - Filter by subject
- `sortDirection` (string, optional) - asc or desc (default: desc)
- `createdAfter` / `createdBefore` (datetime, optional) - Filter by creation time
- `collections` (array of nsid, optional) - Filter by collections (max 20)
- `subjectType` (string, optional) - account or record
- `includeAllUserRecords` (boolean, optional) - Include all user records (default: false)
- `hasComment` (boolean, optional) - Only events with comments
- `comment` (string, optional) - Search in comments (use || for OR)
- `addedLabels` / `removedLabels` (array of strings, optional) - Filter by label changes
- `addedTags` / `removedTags` (array of strings, optional) - Filter by tag changes
- `reportTypes` (array of strings, optional) - Filter by report types
- `policies` (array of strings, optional) - Filter by policy names
- `modTool` (array of strings, optional) - Filter by moderation tool name
- `batchId` (string, optional) - Filter by batch ID
- `ageAssuranceState` (string, optional) - Filter by age assurance state
- `withStrike` (boolean, optional) - Only events with strike count set
- `limit` (integer, optional) - Max results (1-100, default 50)
- `cursor` (string, optional) - Pagination cursor

**Output:**
- `events` (array of `tools.ozone.moderation.defs#modEventView`)
- `cursor` (string, optional)

---

### tools.ozone.moderation.getEvent

**Type:** `query` (GET)
**Description:** Get details about a moderation event.
**Auth Required:** Moderator role or higher

**Input Parameters (Query params):**
- `id` (integer, required) - Event ID

**Output:** `tools.ozone.moderation.defs#modEventViewDetail`

---

### tools.ozone.moderation.getRecord

**Type:** `query` (GET)
**Description:** Get details about a record.
**Auth Required:** Moderator role or higher

**Input Parameters (Query params):**
- `uri` (string/at-uri, required) - Record URI
- `cid` (string/cid, optional) - Specific CID version

**Output:** `tools.ozone.moderation.defs#recordViewDetail`

**Errors:**
- `RecordNotFound` - Record does not exist

---

### tools.ozone.moderation.getRecords

**Type:** `query` (GET)
**Description:** Get details about some records (batch).
**Auth Required:** Moderator role or higher

**Input Parameters (Query params):**
- `uris` (array of at-uri strings, required) - Record URIs (max 100)

**Output:**
- `records` (array) - Array of `recordViewDetail` or `recordViewNotFound`

---

### tools.ozone.moderation.getRepo

**Type:** `query` (GET)
**Description:** Get details about a repository.
**Auth Required:** Moderator role or higher

**Input Parameters (Query params):**
- `did` (string/did, required) - Repository DID

**Output:** `tools.ozone.moderation.defs#repoViewDetail`

**Errors:**
- `RepoNotFound` - Repository does not exist

---

### tools.ozone.moderation.getRepos

**Type:** `query` (GET)
**Description:** Get details about some repositories (batch).
**Auth Required:** Moderator role or higher

**Input Parameters (Query params):**
- `dids` (array of did strings, required) - Repository DIDs (max 100)

**Output:**
- `repos` (array) - Array of `repoViewDetail` or `repoViewNotFound`

---

### tools.ozone.moderation.getReporterStats

**Type:** `query` (GET)
**Description:** Get reporter stats for a list of users.
**Auth Required:** Moderator role or higher

**Input Parameters (Query params):**
- `dids` (array of did strings, required) - User DIDs (max 100)

**Output:**
- `stats` (array of `tools.ozone.moderation.defs#reporterStats`) - Statistics including report counts, takedown counts, etc.

---

### tools.ozone.moderation.getSubjects

**Type:** `query` (GET)
**Description:** Get details about subjects.
**Auth Required:** Moderator role or higher

**Input Parameters (Query params):**
- `subjects` (array of strings, required) - Subject URIs or DIDs (1-100)

**Output:**
- `subjects` (array of `tools.ozone.moderation.defs#subjectView`)

---

### tools.ozone.moderation.searchRepos

**Type:** `query` (GET)
**Description:** Find repositories based on a search term.
**Auth Required:** Moderator role or higher

**Input Parameters (Query params):**
- `q` (string, optional) - Search query
- `term` (string, optional) - DEPRECATED: use 'q' instead
- `limit` (integer, optional) - Max results (1-100, default 50)
- `cursor` (string, optional) - Pagination cursor

**Output:**
- `repos` (array of `tools.ozone.moderation.defs#repoView`)
- `cursor` (string, optional)

---

### tools.ozone.moderation.getAccountTimeline

**Type:** `query` (GET)
**Description:** Get timeline of all available events of an account. This includes moderation events, account history and DID history.
**Auth Required:** Moderator role or higher

**Input Parameters (Query params):**
- `did` (string/did, required) - Account DID

**Output:**
- `timeline` (array of timelineItem) - Daily summaries with event counts grouped by day and event type

**Errors:**
- `RepoNotFound` - Account does not exist

---

### tools.ozone.moderation.scheduleAction

**Type:** `procedure` (POST)
**Description:** Schedule a moderation action to be executed at a future time.
**Auth Required:** Moderator role or higher

**Input Parameters (POST body):**
- `action` (union, required) - Currently only supports `takedown` action type
- `subjects` (array of did strings, required) - DIDs to schedule action for (max 100)
- `createdBy` (string/did, required) - Moderator DID
- `scheduling` (object, required) - Timing configuration with `executeAt` (exact time) OR `executeAfter`/`executeUntil` (randomized window)
- `modTool` (object, optional) - Moderation tool metadata

**Takedown Action Fields:**
- `comment` (string, optional)
- `durationInHours` (integer, optional) - Auto-expiry duration
- `acknowledgeAccountSubjects` (boolean, optional)
- `policies` (array of strings, optional, max 5)
- `severityLevel` (string, optional)
- `strikeCount` (integer, optional)
- `strikeExpiresAt` (datetime, optional)
- `emailContent` (string, optional) - Email to send to user
- `emailSubject` (string, optional)

**Output:**
- `succeeded` (array of did strings) - Successfully scheduled
- `failed` (array) - Failed with error details

---

### tools.ozone.moderation.listScheduledActions

**Type:** `procedure` (POST)
**Description:** List scheduled moderation actions with optional filtering.
**Auth Required:** Moderator role or higher

**Input Parameters (POST body):**
- `statuses` (array of strings, required) - Filter by status: pending, executed, cancelled, failed
- `startsAfter` / `endsBefore` (datetime, optional) - Filter by execution time window
- `subjects` (array of did strings, optional, max 100) - Filter by specific subjects
- `limit` (integer, optional) - Max results (1-100, default 50)
- `cursor` (string, optional) - Pagination cursor

**Output:**
- `actions` (array of `tools.ozone.moderation.defs#scheduledActionView`)
- `cursor` (string, optional)

---

### tools.ozone.moderation.cancelScheduledActions

**Type:** `procedure` (POST)
**Description:** Cancel all pending scheduled moderation actions for specified subjects.
**Auth Required:** Moderator role or higher

**Input Parameters (POST body):**
- `subjects` (array of did strings, required) - DIDs to cancel actions for (max 100)
- `comment` (string, optional) - Reason for cancellation

**Output:**
- `succeeded` (array of did strings) - Successfully cancelled
- `failed` (array) - Failed with error details including did, error, errorCode

---

## Safelink (URL Safety)

URL safety rule management for blocking/warning about malicious or policy-violating links.

### tools.ozone.safelink.addRule

**Type:** `procedure` (POST)
**Description:** Add a new URL safety rule.
**Auth Required:** Admin role

**Input Parameters (POST body):**
- `url` (string, required) - The URL or domain to apply the rule to
- `pattern` (ref, required) - Pattern type from `tools.ozone.safelink.defs#patternType`
- `action` (ref, required) - Action type from `tools.ozone.safelink.defs#actionType`
- `reason` (ref, required) - Reason type from `tools.ozone.safelink.defs#reasonType`
- `comment` (string, optional) - Optional comment about the decision
- `createdBy` (string/did, optional) - Author DID (only respected with admin auth)

**Output:** `tools.ozone.safelink.defs#event`

**Errors:**
- `InvalidUrl` - The provided URL is invalid
- `RuleAlreadyExists` - A rule for this URL/domain already exists

---

### tools.ozone.safelink.updateRule

**Type:** `procedure` (POST)
**Description:** Update an existing URL safety rule.
**Auth Required:** Admin role

**Input Parameters (POST body):**
- `url` (string, required) - The URL or domain to update
- `pattern` (ref, required) - Pattern type
- `action` (ref, required) - Action type
- `reason` (ref, required) - Reason type
- `comment` (string, optional)
- `createdBy` (string/did, optional)

**Output:** `tools.ozone.safelink.defs#event`

**Errors:**
- `RuleNotFound` - No active rule found for this URL/domain

---

### tools.ozone.safelink.removeRule

**Type:** `procedure` (POST)
**Description:** Remove an existing URL safety rule.
**Auth Required:** Admin role

**Input Parameters (POST body):**
- `url` (string, required) - The URL or domain to remove the rule for
- `pattern` (ref, required) - Pattern type
- `comment` (string, optional) - Why the rule is being removed
- `createdBy` (string/did, optional)

**Output:** `tools.ozone.safelink.defs#event`

**Errors:**
- `RuleNotFound` - No active rule found for this URL/domain

---

### tools.ozone.safelink.queryRules

**Type:** `procedure` (POST)
**Description:** Query URL safety rules.
**Auth Required:** Moderator role or higher

**Input Parameters (POST body):**
- `cursor` (string, optional) - Pagination cursor
- `limit` (integer, optional) - Max results (1-100, default 50)
- `urls` (array of strings, optional) - Filter by specific URLs or domains
- `patternType` (string, optional) - Filter by pattern type
- `actions` (array of strings, optional) - Filter by action types
- `reason` (string, optional) - Filter by reason type
- `createdBy` (string/did, optional) - Filter by rule creator
- `sortDirection` (string, optional) - asc or desc (default: desc)

**Output:**
- `rules` (array of `tools.ozone.safelink.defs#urlRule`)
- `cursor` (string, optional)

---

### tools.ozone.safelink.queryEvents

**Type:** `procedure` (POST)
**Description:** Query URL safety audit events.
**Auth Required:** Moderator role or higher

**Input Parameters (POST body):**
- `cursor` (string, optional) - Pagination cursor
- `limit` (integer, optional) - Max results (1-100, default 50)
- `urls` (array of strings, optional) - Filter by specific URLs or domains
- `patternType` (string, optional) - Filter by pattern type
- `sortDirection` (string, optional) - asc or desc (default: desc)

**Output:**
- `events` (array of `tools.ozone.safelink.defs#event`)
- `cursor` (string, optional)

---

## Server

Server configuration and metadata.

### tools.ozone.server.getConfig

**Type:** `query` (GET)
**Description:** Get details about ozone's server configuration.
**Auth Required:** Yes

**Input Parameters:** None

**Output:**
- `appview` (object) - AppView service config with URL
- `pds` (object) - PDS service config with URL
- `blobDivert` (object) - Blob diversion service config with URL
- `chat` (object) - Chat service config with URL
- `viewer` (object) - Current viewer's role (admin, moderator, triage, verifier)
- `verifierDid` (string/did) - The DID of the verifier used for verification

---

## Set Management

Manage sets of values (e.g., blocklists, allowlists, custom groupings).

### tools.ozone.set.upsertSet

**Type:** `procedure` (POST)
**Description:** Create or update set metadata.
**Auth Required:** Admin role

**Input Parameters (POST body):** `tools.ozone.set.defs#set` object
- `name` (string) - Set identifier
- `description` (string, optional)
- Other metadata fields

**Output:** `tools.ozone.set.defs#setView`

---

### tools.ozone.set.deleteSet

**Type:** `procedure` (POST)
**Description:** Delete an entire set.
**Auth Required:** Admin role

**Input Parameters (POST body):**
- `name` (string, required) - Name of the set to delete

**Output:** Empty object

**Errors:**
- `SetNotFound` - Set with the given name does not exist

---

### tools.ozone.set.querySets

**Type:** `query` (GET)
**Description:** Query available sets.
**Auth Required:** Moderator role or higher

**Input Parameters (Query params):**
- `limit` (integer, optional) - Max results (1-100, default 50)
- `cursor` (string, optional) - Pagination cursor
- `namePrefix` (string, optional) - Filter by name prefix
- `sortBy` (string, optional) - Sort by: name, createdAt, updatedAt (default: name)
- `sortDirection` (string, optional) - asc or desc (default: asc)

**Output:**
- `sets` (array of `tools.ozone.set.defs#setView`)
- `cursor` (string, optional)

---

### tools.ozone.set.getValues

**Type:** `query` (GET)
**Description:** Get a specific set and its values.
**Auth Required:** Moderator role or higher

**Input Parameters (Query params):**
- `name` (string, required) - Set name
- `limit` (integer, optional) - Max values (1-1000, default 100)
- `cursor` (string, optional) - Pagination cursor

**Output:**
- `set` (`tools.ozone.set.defs#setView`) - Set metadata
- `values` (array of strings) - Set values
- `cursor` (string, optional)

**Errors:**
- `SetNotFound` - Set with the given name does not exist

---

### tools.ozone.set.addValues

**Type:** `procedure` (POST)
**Description:** Add values to a specific set.
**Auth Required:** Admin role

**Input Parameters (POST body):**
- `name` (string, required) - Name of the set to add values to
- `values` (array of strings, required) - Values to add (1-1000)

**Output:** None (success indicates values were added)

**Note:** Attempting to add values to a set that does not exist will result in an error.

---

### tools.ozone.set.deleteValues

**Type:** `procedure` (POST)
**Description:** Delete values from a specific set.
**Auth Required:** Admin role

**Input Parameters (POST body):**
- `name` (string, required) - Name of the set to delete values from
- `values` (array of strings, required) - Values to delete (min 1)

**Output:** None

**Errors:**
- `SetNotFound` - Set with the given name does not exist

**Note:** Attempting to delete values that are not in the set will not result in an error.

---

## Settings

Instance and personal configuration management.

### tools.ozone.setting.upsertOption

**Type:** `procedure` (POST)
**Description:** Create or update setting option.
**Auth Required:** Based on managerRole setting

**Input Parameters (POST body):**
- `key` (string/nsid, required) - Setting key
- `scope` (string, required) - instance or personal
- `value` (unknown, required) - Setting value (any type)
- `description` (string, optional, max 2000 chars)
- `managerRole` (string, optional) - Minimum role required to manage: roleModerator, roleTriage, roleVerifier, roleAdmin

**Output:**
- `option` (`tools.ozone.setting.defs#option`)

---

### tools.ozone.setting.listOptions

**Type:** `query` (GET)
**Description:** List settings with optional filtering.
**Auth Required:** Based on setting visibility

**Input Parameters (Query params):**
- `limit` (integer, optional) - Max results (1-100, default 50)
- `cursor` (string, optional) - Pagination cursor
- `scope` (string, optional) - instance or personal (default: instance)
- `prefix` (string, optional) - Filter keys by prefix
- `keys` (array of nsid strings, optional, max 100) - Filter for specific keys (ignored if prefix provided)

**Output:**
- `options` (array of `tools.ozone.setting.defs#option`)
- `cursor` (string, optional)

---

### tools.ozone.setting.removeOptions

**Type:** `procedure` (POST)
**Description:** Delete settings by key.
**Auth Required:** Based on managerRole of settings

**Input Parameters (POST body):**
- `keys` (array of nsid strings, required) - Keys to remove (1-200)
- `scope` (string, required) - instance or personal

**Output:** Empty object

---

## Signature (Threat Detection)

Threat signature analysis for detecting coordinated abuse, ban evasion, and related accounts.

### tools.ozone.signature.findRelatedAccounts

**Type:** `query` (GET)
**Description:** Get accounts that share some matching threat signatures with the root account.
**Auth Required:** Moderator role or higher

**Input Parameters (Query params):**
- `did` (string/did, required) - Root account DID
- `cursor` (string, optional) - Pagination cursor
- `limit` (integer, optional) - Max results (1-100, default 50)

**Output:**
- `accounts` (array of relatedAccount) - Accounts with similarity details
- `cursor` (string, optional)

---

### tools.ozone.signature.findCorrelation

**Type:** `query` (GET)
**Description:** Find all correlated threat signatures between 2 or more accounts.
**Auth Required:** Moderator role or higher

**Input Parameters (Query params):**
- `dids` (array of did strings, required) - Accounts to compare

**Output:**
- `details` (array of `tools.ozone.signature.defs#sigDetail`) - Shared threat signatures

---

### tools.ozone.signature.searchAccounts

**Type:** `query` (GET)
**Description:** Search for accounts that match one or more threat signature values.
**Auth Required:** Moderator role or higher

**Input Parameters (Query params):**
- `values` (array of strings, required) - Signature values to search for
- `cursor` (string, optional) - Pagination cursor
- `limit` (integer, optional) - Max results (1-100, default 50)

**Output:**
- `accounts` (array of `com.atproto.admin.defs#accountView`)
- `cursor` (string, optional)

---

## Team Management

Manage ozone moderation team members and roles.

### tools.ozone.team.addMember

**Type:** `procedure` (POST)
**Description:** Add a member to the ozone team.
**Auth Required:** Admin role

**Input Parameters (POST body):**
- `did` (string/did, required) - Member DID
- `role` (string, required) - One of: roleAdmin, roleModerator, roleVerifier, roleTriage

**Output:** `tools.ozone.team.defs#member`

**Errors:**
- `MemberAlreadyExists` - Member already exists in the team

---

### tools.ozone.team.updateMember

**Type:** `procedure` (POST)
**Description:** Update a member in the ozone service.
**Auth Required:** Admin role

**Input Parameters (POST body):**
- `did` (string/did, required) - Member DID
- `disabled` (boolean, optional) - Disable/enable member
- `role` (string, optional) - New role: roleAdmin, roleModerator, roleVerifier, roleTriage

**Output:** `tools.ozone.team.defs#member`

**Errors:**
- `MemberNotFound` - The member being updated does not exist in the team

---

### tools.ozone.team.deleteMember

**Type:** `procedure` (POST)
**Description:** Delete a member from ozone team.
**Auth Required:** Admin role

**Input Parameters (POST body):**
- `did` (string/did, required) - Member DID to remove

**Output:** None

**Errors:**
- `MemberNotFound` - The member being deleted does not exist
- `CannotDeleteSelf` - You cannot delete yourself from the team

---

### tools.ozone.team.listMembers

**Type:** `query` (GET)
**Description:** List all members with access to the ozone service.
**Auth Required:** Admin role

**Input Parameters (Query params):**
- `q` (string, optional) - Search query
- `disabled` (boolean, optional) - Filter by disabled status
- `roles` (array of strings, optional) - Filter by roles
- `limit` (integer, optional) - Max results (1-100, default 50)
- `cursor` (string, optional) - Pagination cursor

**Output:**
- `members` (array of `tools.ozone.team.defs#member`)
- `cursor` (string, optional)

---

## Verification

Manage user verification status (blue checkmarks).

### tools.ozone.verification.grantVerifications

**Type:** `procedure` (POST)
**Description:** Grant verifications to multiple subjects. Allows batch processing of up to 100 verifications at once.
**Auth Required:** Verifier role or higher

**Input Parameters (POST body):**
- `verifications` (array, required, max 100) - Array of verification requests, each containing:
  - `subject` (string/did, required) - DID being verified
  - `handle` (string/handle, required) - Handle at time of verification
  - `displayName` (string, required) - Display name at time of verification
  - `createdAt` (datetime, optional) - Timestamp (defaults to current time)

**Output:**
- `verifications` (array of `tools.ozone.verification.defs#verificationView`) - Successfully granted
- `failedVerifications` (array) - Failed with error and subject

---

### tools.ozone.verification.revokeVerifications

**Type:** `procedure` (POST)
**Description:** Revoke previously granted verifications in batches of up to 100.
**Auth Required:** Verifier role or higher

**Input Parameters (POST body):**
- `uris` (array of at-uri strings, required, max 100) - Verification record URIs to revoke
- `revokeReason` (string, optional, max 1000 chars) - Reason for revocation

**Output:**
- `revokedVerifications` (array of at-uri strings) - Successfully revoked
- `failedRevocations` (array) - Failed with uri and error

---

### tools.ozone.verification.listVerifications

**Type:** `query` (GET)
**Description:** List verifications with filtering options.
**Auth Required:** Verifier role or higher

**Input Parameters (Query params):**
- `cursor` (string, optional) - Pagination cursor
- `limit` (integer, optional) - Max results (1-100, default 50)
- `createdAfter` / `createdBefore` (datetime, optional) - Filter by creation time
- `issuers` (array of did strings, optional, max 100) - Filter by verifier DIDs
- `subjects` (array of did strings, optional, max 100) - Filter by verified DIDs
- `sortDirection` (string, optional) - asc or desc (default: desc)
- `isRevoked` (boolean, optional) - Filter by revocation status (default: include both)

**Output:**
- `verifications` (array of `tools.ozone.verification.defs#verificationView`)
- `cursor` (string, optional)

---

## Common Patterns

### Authentication & Authorization

All endpoints require authentication. Authorization is role-based:

**Roles (hierarchical, higher includes lower permissions):**
1. **Admin** - Full access to all endpoints
2. **Moderator** - Can perform moderation actions, view reports
3. **Verifier** - Can grant/revoke verifications
4. **Triage** - Can view and categorize reports

### Request Methods

- **Query** (`query` type) - GET requests with query parameters
- **Procedure** (`procedure` type) - POST requests with JSON body

### Pagination

Most list/query endpoints support pagination:
- `cursor` (string) - Opaque cursor for next page
- `limit` (integer) - Max results per page (typically 1-100, default 50)

### Common Parameters

- **DID** (`did` format) - Decentralized Identifier (e.g., `did:plc:abc123`)
- **AT-URI** (`at-uri` format) - AT Protocol URI (e.g., `at://did:plc:abc123/app.bsky.feed.post/abc123`)
- **Handle** (`handle` format) - Username (e.g., `alice.bsky.social`)
- **CID** (`cid` format) - Content Identifier hash
- **Datetime** (`datetime` format) - ISO 8601 timestamp

### Batch Operations

Many endpoints support batch operations with limits:
- Most batch endpoints: max 100 items
- `tools.ozone.set.addValues`: max 1000 values
- `tools.ozone.setting.removeOptions`: max 200 keys

### Error Handling

Common error patterns:
- `NotFound` errors - Resource does not exist
- `AlreadyExists` errors - Duplicate resource
- `Unauthorized` - Insufficient permissions
- Batch operations return partial success with `succeeded` and `failed` arrays

### Moderation Events

The core moderation system revolves around events emitted via `emitEvent`:

**Event Types:**
- **Action Events:** Takedown, ReverseTakedown, Acknowledge, Escalate, Mute, Unmute
- **Communication:** Email, Comment
- **Labeling:** Label (add/remove labels)
- **Appeals:** ResolveAppeal
- **Tags:** Tag (add/remove tags)
- **Reports:** Report, MuteReporter, UnmuteReporter
- **Lifecycle:** accountEvent, identityEvent, recordEvent
- **Scoring:** PriorityScore
- **Age Assurance:** ageAssuranceEvent, ageAssuranceOverrideEvent
- **Security:** revokeAccountCredentialsEvent, Divert
- **Scheduling:** scheduleTakedownEvent, cancelScheduledTakedownEvent

### Subject Types

Moderation actions can target:
- **Repositories** (accounts) - Referenced by DID
- **Records** (posts, profiles, etc.) - Referenced by AT-URI
- **Chat Messages** - Referenced by message ref
- **Blobs** (images, videos) - Referenced by CID

### Review States

Subject statuses track review progress:
- `reviewOpen` - Needs review
- `reviewEscalated` - Escalated for senior review
- `reviewClosed` - Resolved
- `reviewNone` - No review needed (but metadata tracked)

### Hosting Status

Tracks account/record state on hosting service:
- **Account:** takendown, suspended, deleted, deactivated, unknown
- **Record:** deleted, unknown

---

## Summary Statistics

**Total Endpoints: 47**
- Communication: 4 endpoints
- Hosting: 1 endpoint
- Moderation: 15 endpoints (core moderation functionality)
- Safelink: 5 endpoints
- Server: 1 endpoint
- Set Management: 6 endpoints
- Settings: 3 endpoints
- Signature: 3 endpoints
- Team: 4 endpoints
- Verification: 3 endpoints

**Definition Files (not callable endpoints): 9**
- tools.ozone.communication.defs
- tools.ozone.moderation.defs
- tools.ozone.report.defs
- tools.ozone.safelink.defs
- tools.ozone.set.defs
- tools.ozone.setting.defs
- tools.ozone.signature.defs
- tools.ozone.team.defs
- tools.ozone.verification.defs
