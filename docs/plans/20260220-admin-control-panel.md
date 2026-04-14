---
title: Admin Control Panel Implementation Plan
---

# Admin Control Panel Implementation Plan

**Created:** 2026-02-20
**Base Commit:** `a03e1f2a6324ca2c4753a3dad62078c5d0ffae08`
**Status:** Completed

---

## Summary

Build a unified Admin Control Panel with 4 tabs (Overview, Accounts, Moderation, System) following macOS Classic UI patterns. Add backend audit logging and a reports queue system.

---

## Implementation Completed

### Phase 1: Backend - Audit Logging & Stats ✅

**Files Modified:**
- `Garazyk/Sources/Database/Schema.h` - Added table declarations
- `Garazyk/Sources/Database/Schema.m` - Added admin_audit_log, reports, admin_config tables
- `Garazyk/Sources/Database/PDSDatabase.h` - Added category declarations
- `Garazyk/Sources/Database/PDSDatabase.m` - Added AdminAudit, Reports, AdminConfig categories
- `Garazyk/Sources/Services/PDSAdminService.h` - Added protocol methods
- `Garazyk/Sources/Services/PDSAdminService.m` - Implemented audit log, stats, reports methods
- `Garazyk/Sources/Admin/PDSAdminController.h` - Added controller methods
- `Garazyk/Sources/Admin/PDSAdminController.m` - Implemented delegation
- `Garazyk/Sources/Admin/PDSAdminHandler.m` - Added /admin/stats, /admin/audit-log routes

### Phase 2: Backend - Reports System ✅

**Files Modified:**
- `Garazyk/Sources/Network/XrpcHandler.h` - Added report endpoint declarations
- `Garazyk/Sources/Network/XrpcHandler.m` - Added registration methods
- `Garazyk/Sources/Network/XrpcMethodRegistry.m` - Implemented handlers for:
  - `com.atproto.admin.getModerationReports`
  - `com.atproto.admin.resolveReport`

### Phase 3: Frontend - Admin Control Panel UI ✅

**Files Created:**
- `Garazyk/Sources/App/AdminUI/Assets/js/admin-panel.js` - Main module with API helpers
- `Garazyk/Sources/App/AdminUI/Assets/js/admin-overview.js` - Overview tab
- `Garazyk/Sources/App/AdminUI/Assets/js/admin-accounts.js` - Accounts tab with search
- `Garazyk/Sources/App/AdminUI/Assets/js/admin-reports.js` - Moderation tab with filters
- `Garazyk/Sources/App/AdminUI/Assets/js/admin-system.js` - System tab with audit log
- `Garazyk/Sources/App/AdminUI/Assets/admin-panel.css` - Styling

**Files Modified:**
- `Garazyk/Sources/App/Explore/Assets/index.html` - Added Admin Control Panel window
- `Garazyk/Sources/App/Explore/Assets/js/ui.js` - Integrated admin panel modules

### Phase 4: Integration & Cleanup ✅

- Updated Admin menu items to open unified Admin Control Panel
- Added tab switching logic with lazy loading
- Integrated existing invite code functionality into System tab
- Added search for accounts, filters for reports

---

## Phase 1: Backend - Audit Logging & Stats

### 1.1 Database Schema

**File:** `Garazyk/Sources/Database/Schema.m`

Add new tables:

```sql
-- Configuration storage (for audit retention, etc.)
CREATE TABLE IF NOT EXISTS admin_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at DATETIME NOT NULL
);

-- Audit log for all admin actions
CREATE TABLE IF NOT EXISTS admin_audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    admin_did TEXT NOT NULL,
    action TEXT NOT NULL,           -- 'account.disable', 'invite.create', etc.
    subject_type TEXT,              -- 'account', 'record', 'invite_code', 'report'
    subject_id TEXT,
    details TEXT,                   -- JSON blob with action-specific data
    ip_address TEXT,
    created_at DATETIME NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_log_admin ON admin_audit_log(admin_did);
CREATE INDEX IF NOT EXISTS idx_audit_log_subject ON admin_audit_log(subject_type, subject_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_created ON admin_audit_log(created_at);
```

### 1.2 Database Methods

**File:** `Garazyk/Sources/Database/PDSDatabase.m`

Add category `PDSDatabase (AdminAudit)`:

- `- (BOOL)insertAuditLog:(NSDictionary *)entry error:(NSError **)error`
- `- (NSArray *)queryAuditLog:(NSDictionary *)filters limit:(NSInteger)limit cursor:(NSString *)cursor error:(NSError **)error`
- `- (BOOL)deleteAuditLogsOlderThan:(NSInteger)days error:(NSError **)error`
- `- (NSString *)getConfigValue:(NSString *)key error:(NSError **)error`
- `- (BOOL)setConfigValue:(NSString *)value forKey:(NSString *)key error:(NSError **)error`

### 1.3 Admin Service Updates

**File:** `Garazyk/Sources/Services/PDSAdminService.m`

- Add `logAdminAction:` method that writes to audit log
- Add `getServerStats` method returning:
  - Total accounts, active accounts (recent activity)
  - Total repos, records, blobs
  - Storage size estimate
  - Recent signups (7 days)
  - Pending reports count
  - Invite code stats

### 1.4 Admin Controller Updates

**File:** `Garazyk/Sources/Admin/PDSAdminController.m`

- Add `- (NSDictionary *)getServerStats:(NSError **)error`
- Add `- (NSArray *)queryAuditLog:(NSDictionary *)filters limit:(NSInteger)limit cursor:(NSString **)cursor error:(NSError **)error`
- Wrap existing admin actions with audit logging

### 1.5 Admin HTTP Handler

**File:** `Garazyk/Sources/Admin/PDSAdminHandler.m`

Add routes:
- `GET /admin/stats` - Return server statistics
- `GET /admin/audit-log` - Query audit log (admin only)

### 1.6 Config Defaults

Initialize `admin_config` with:
- `audit_log_retention_days`: `90`

---

## Phase 2: Backend - Reports System

### 2.1 Database Schema

**File:** `Garazyk/Sources/Database/Schema.m`

```sql
CREATE TABLE IF NOT EXISTS reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    report_id TEXT NOT NULL UNIQUE,     -- UUID for external reference
    reason_type TEXT NOT NULL,          -- lexicon reason type
    reason TEXT,                        -- free-form explanation
    reported_by_did TEXT NOT NULL,      -- always authenticated
    subject_type TEXT NOT NULL,         -- 'account' or 'record'
    subject_did TEXT,                   -- DID of subject
    subject_uri TEXT,                   -- AT-URI if record
    status TEXT NOT NULL DEFAULT 'open', -- 'open', 'in_progress', 'resolved', 'dismissed'
    resolved_by_did TEXT,
    resolved_at DATETIME,
    resolution_notes TEXT,
    created_at DATETIME NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status);
CREATE INDEX IF NOT EXISTS idx_reports_subject ON reports(subject_type, subject_did);
CREATE INDEX IF NOT EXISTS idx_reports_reported_by ON reports(reported_by_did);
CREATE INDEX IF NOT EXISTS idx_reports_created ON reports(created_at);
```

### 2.2 Database Methods

**File:** `Garazyk/Sources/Database/PDSDatabase.m`

Add category `PDSDatabase (Reports)`:

- `- (NSString *)createReport:(NSDictionary *)report error:(NSError **)error`
- `- (NSArray *)queryReports:(NSDictionary *)filters limit:(NSInteger)limit cursor:(NSString *)cursor error:(NSError **)error`
- `- (NSDictionary *)getReportById:(NSString *)reportId error:(NSError **)error`
- `- (BOOL)updateReportStatus:(NSString *)reportId status:(NSString *)status resolvedBy:(NSString *)adminDid notes:(NSString *)notes error:(NSError **)error`

### 2.3 Admin Service Reports

**File:** `Garazyk/Sources/Services/PDSAdminService.m`

Add methods:
- `- (NSDictionary *)createReport:(NSDictionary *)params error:(NSError **)error`
- `- (NSDictionary *)getReports:(NSDictionary *)params error:(NSError **)error`
- `- (BOOL)resolveReport:(NSString *)reportId status:(NSString *)status notes:(NSString *)notes adminDid:(NSString *)adminDid error:(NSError **)error`

### 2.4 Admin Controller Reports

**File:** `Garazyk/Sources/Admin/PDSAdminController.m`

Add:
- `- (NSDictionary *)getReports:(NSDictionary *)params error:(NSError **)error`
- `- (BOOL)resolveReport:(NSString *)reportId status:(NSString *)status notes:(NSString *)notes adminDid:(NSString *)adminDid error:(NSError **)error`

### 2.5 XRPC Registration

**File:** `Garazyk/Sources/Network/XrpcHandler.m`

Register endpoints:
- `com.atproto.admin.getModerationReports` - Query reports
- `com.atproto.admin.resolveReport` - Resolve/dismiss a report

**File:** `Garazyk/Sources/Network/XrpcMethodRegistry.m`

Implement handlers with proper auth checks.

### 2.6 Update Existing createReport

**File:** `Garazyk/Sources/Network/XrpcMethodRegistry.m`

Verify `com.atproto.moderation.createReport` stores to `reports` table.

### 2.7 Report Reason Types

Use standard ATProto lexicon types:
- `com.atproto.moderation.defs#reasonSpam`
- `com.atproto.moderation.defs#reasonViolation`
- `com.atproto.moderation.defs#reasonMisleading`
- `com.atproto.moderation.defs#reasonSexual`
- `com.atproto.moderation.defs#reasonRude`
- `com.atproto.moderation.defs#reasonOther`

### 2.8 Email Notifications

Add optional email notification when reports are resolved:
- Add `notify_reporter` param to resolve endpoint
- If true, send email to reporter with resolution details
- Requires email templates

---

## Phase 3: Frontend - Admin Control Panel

### 3.1 New Files

```

Garazyk/Sources/App/AdminUI/Assets/
├── admin-panel.html      # Main panel HTML (embedded in index.html or separate)
├── admin-panel.css       # Panel-specific styles
├── js/
│   ├── admin-panel.js    # Main module, tab switching, API helpers
│   ├── admin-overview.js # Overview tab logic
│   ├── admin-accounts.js # Accounts tab + Get Info window
│   ├── admin-reports.js  # Moderation tab logic
│   └── admin-system.js   # System tab, audit log, invites
```

### 3.2 Admin Panel Window Structure

**Window:** `win-admin-panel`

```

┌──────────────────────────────────────────────────────────────────┐
│ Admin Control Panel                                    [Close]    │
├──────────────────────────────────────────────────────────────────┤
│  [Overview] [Accounts] [Moderation] [System]                     │
├──────────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────┬────────────────────────────────────┐ │
│ │                         │                                    │ │
│ │    Tab content          │   Detail Panel (context-sensitive) │ │
│ │    (list, stats, etc)   │   Shows on selection               │ │
│ │                         │                                    │ │
│ │                         │   [Get Info...] opens modal        │ │
│ │                         │                                    │ │
│ └─────────────────────────┴────────────────────────────────────┘ │
├──────────────────────────────────────────────────────────────────┤
│ Ready                                            Admin: [did]   │
└──────────────────────────────────────────────────────────────────┘
```

### 3.3 Overview Tab

**Stats cards:**
- Total accounts / Active (last 7 days)
- Pending reports
- Active invite codes / Used this week
- Server uptime

**Recent activity:**
- Signups (7 days)
- Posts created (7 days)
- Admin actions (24 hours)

### 3.4 Accounts Tab

**Master list:**
- Searchable by handle, DID, email
- Columns: Handle, DID, Email (partial), Status
- Status indicators: 🟢 Active, 🔴 Disabled, 🟡 Takedown
- Sortable columns

**Detail panel:**
- Shows summary on row select
- Quick actions: Enable/Disable, View Profile, Get Info

**Get Info window (classic modal):**
```

┌───────────────────────────────────────────┐
│ Account Info: [handle]          [Close]   │
├───────────────────────────────────────────┤
│ ┌─ Identity ─────────────────────────────┐│
│ │ Handle: [handle]                       ││
│ │ DID: [did]                             ││
│ │ Email: [email]                         ││
│ │ Email Verified: ✅/❌                  ││
│ └────────────────────────────────────────┘│
│ ┌─ Activity ─────────────────────────────┐│
│ │ Posts: N    Likes: N    Reposts: N     ││
│ │ Following: N    Followers: N           ││
│ │ Last Active: [date]                    ││
│ └────────────────────────────────────────┘│
│ ┌─ Moderation ───────────────────────────┐│
│ │ Takedown: Yes/No                       ││
│ │ Labels: [list or "none"]               ││
│ │ Reports: N open, N resolved            ││
│ └────────────────────────────────────────┘│
│ ┌─ Invites ──────────────────────────────┐│
│ │ Codes Created: N                       ││
│ │ Used By: [handles...]                  ││
│ └────────────────────────────────────────┘│
│                                           │
│ [Reset Password] [Send Email] [Disable]   │
└───────────────────────────────────────────┘
```

### 3.5 Moderation Tab

**Reports queue:**
- Filter by status: All / Open / In Progress / Resolved / Dismissed
- Filter by reason type
- Search by subject handle/DID

**List columns:**
- Status indicator
- Reason type (icon + text)
- Subject (handle or post preview)
- Reporter (or "Anonymous" - not supported but UI ready)
- Created at

**Detail panel:**
- Full report details
- Subject preview (profile card or post content)
- Reporter info
- Resolution history

**Actions:**
- Dismiss (no action needed)
- Warn (send warning email)
- Takedown (apply takedown)
- Assign to me (set status to in_progress)
- Resolve with notes

### 3.6 System Tab

**Server status section:**
- Status: Running/Stopped
- Uptime
- PDS version
- Database path

**Database section:**
- Size
- Repositories count
- Records count
- Blobs count and total size

**Invite codes section:**
- Stats summary
- Link to manage (could be inline or button)

**Audit log section:**
- Recent 10 entries preview
- [View Full Audit Log] button opens modal

**Audit log modal:**
- Filterable by action type, date range
- Paginated table
- Columns: Timestamp, Admin, Action, Subject, Details

### 3.7 JavaScript Modules

**admin-panel.js:**
```javascript
export const AdminPanel = {
    init() {},
    open() {},
    close() {},
    switchTab(tabId) {},
    // Auth check
    isAuthenticated() {},
    getToken() {},
    // API helpers
    async fetchStats() {},
    async fetchAuditLog() {},
};
```

**admin-overview.js:**
```javascript
export const AdminOverview = {
    async load() {},
    render(stats) {},
    refresh() {},
};
```

**admin-accounts.js:**
```javascript
export const AdminAccounts = {
    async load() {},
    render(accounts) {},
    search(query) {},
    selectAccount(did) {},
    showAccountInfo(did) {},
    async disableAccount(did) {},
    async enableAccount(did) {},
};
```

**admin-reports.js:**
```javascript
export const AdminReports = {
    async load() {},
    render(reports) {},
    filterByStatus(status) {},
    selectReport(reportId) {},
    async resolveReport(reportId, status, notes) {},
};
```

**admin-system.js:**
```javascript
export const AdminSystem = {
    async load() {},
    render(systemInfo) {},
    showAuditLog() {},
    showInviteManager() {},
};
```

---

## Phase 4: Integration & Cleanup

### 4.1 Update Main UI

**File:** `Garazyk/Sources/App/Explore/Assets/index.html`

- Remove `win-invite-codes` and `win-moderation` windows
- Add `win-admin-panel` window structure
- Add script imports for admin modules

**File:** `Garazyk/Sources/App/Explore/Assets/js/ui.js`

- Update Admin menu handlers:
  - Remove direct invite/moderation window opens
  - Add Admin Control Panel open
- Keep AdminAPI helper functions
- Add Admin Panel initialization

### 4.2 Migrate Invite Codes

- Move invite code generation/management into System tab
- Keep existing `/admin/invites` endpoints
- Add audit logging to invite operations

### 4.3 Add Audit Logging

Wrap existing admin actions with audit log writes:
- Account disable/enable
- Account takedown/untakedown
- Invite create/disable
- Label create

### 4.4 Testing

Manual testing checklist:
- [ ] Admin login flow
- [ ] Overview tab loads stats
- [ ] Accounts tab search and filter
- [ ] Account Get Info shows correct data
- [ ] Account disable/enable works
- [ ] Moderation tab shows reports
- [ ] Report resolution works
- [ ] Audit log records actions
- [ ] System tab shows server info
- [ ] Invite codes work from System tab

---

## Dependencies

- No new external dependencies
- Uses existing CSS system (Mac Classic theme)
- Uses existing admin auth system

---

## Files Modified Summary

| File | Changes |
|------|---------|
| `Sources/Database/Schema.m` | Add admin_config, admin_audit_log, reports tables |
| `Sources/Database/PDSDatabase.m` | Add audit log and reports methods |
| `Sources/Services/PDSAdminService.m` | Add audit, stats, reports methods |
| `Sources/Admin/PDSAdminController.m` | Add stats, audit, reports endpoints |
| `Sources/Admin/PDSAdminHandler.m` | Add /admin/stats, /admin/audit-log routes |
| `Sources/Network/XrpcHandler.m` | Register new XRPC endpoints |
| `Sources/Network/XrpcMethodRegistry.m` | Implement report endpoints |
| `Sources/App/Explore/Assets/index.html` | Restructure admin UI |
| `Sources/App/Explore/Assets/js/ui.js` | Update admin menu handlers |

## Files Created Summary

| File | Purpose |
|------|---------|
| `Sources/App/AdminUI/Assets/admin-panel.html` | Admin panel HTML |
| `Sources/App/AdminUI/Assets/admin-panel.css` | Admin panel styles |
| `Sources/App/AdminUI/Assets/js/admin-panel.js` | Main panel module |
| `Sources/App/AdminUI/Assets/js/admin-overview.js` | Overview tab |
| `Sources/App/AdminUI/Assets/js/admin-accounts.js` | Accounts tab |
| `Sources/App/AdminUI/Assets/js/admin-reports.js` | Moderation tab |
| `Sources/App/AdminUI/Assets/js/admin-system.js` | System tab |

---

## Effort Estimate

| Phase | Hours |
|-------|-------|
| Phase 1: Audit Logging | 2-3 |
| Phase 2: Reports System | 3-4 |
| Phase 3: Admin UI | 6-8 |
| Phase 4: Integration | 2-3 |
| **Total** | **13-18** |

---

## Open Questions

None - all questions resolved.

---

## Changelog

| Date | Changes |
|------|---------|
| 2026-02-20 | Initial plan created |
