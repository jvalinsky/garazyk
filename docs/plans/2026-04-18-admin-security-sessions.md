# Plan: Security & Session Dashboard

## Objective
Provide a unified security dashboard for auditing active user sessions, revoking OAuth tokens, and managing application passwords to protect user accounts.

## Backend Enhancements
### SessionService / OAuth2Server
- Implement an admin-level `listSessionsForDid:` method to query active refresh tokens and their metadata (IP, User-Agent, Issued At).
- Implement `revokeSessionWithId:` to manually invalidate a specific session.

### PDSDatabase
- Ensure the `sessions` and `app_passwords` tables are correctly indexed for DID-based lookups.

## Frontend Implementation
### Sidebar & Navigation
- Add a new "Security" service segment to the top toolbar.
- Sidebar items: "Active Sessions", "App Passwords", "Audit Log".

### Partial Templates
- `security_sessions.html`: Search by DID, then list all active devices/sessions with "Revoke" buttons.
- `security_app_passwords.html`: List all app passwords for a DID with "Revoke" and "History" views.

### UI Controls
- **Global Revoke**: One-click "Log Out from All Devices" for a specific DID.
- **Session Detail**: Show metadata like geolocation (if available) or IP for an active session.

## Implementation Steps
1. Implement internal session listing in `OAuth2Handler.m` or a separate `PDSSessionService.m`.
2. Register the `/admin/security/*` routes.
3. Implement `renderSecuritySessionsPartial` in `AdminUIHandler.m`.
4. Add global JS logic for handling token revocation and forcing client logout.
