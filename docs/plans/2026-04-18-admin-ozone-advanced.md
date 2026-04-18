# Plan: Ozone Advanced Operations

## Objective
Fully expose the Ozone moderation toolkit, enabling deep auditing of moderation events, management of moderation sets, and advanced account correlation detection.

## Backend Enhancements
### ModerationService.m
- Ensure `listSets`, `getSet`, `listMembersInSet` are fully implemented and connected to the database.
- Ensure `findRelatedAccounts` (Signature service) is functional.

### XrpcToolsOzonePack.m
- Audit all `tools.ozone.*` handlers to ensure they correctly delegate to the service layer and aren't just stubs.

## Frontend Implementation
### Sidebar & Navigation
- Expand the "Ozone" section in `index.html` with: "Sets", "Correlations", and "Verification".

### Partial Templates
- `ozone_sets.html`: CRUD interface for moderation sets.
- `ozone_correlations.html`: A tool where admins can input a DID and see a visual list of correlated accounts based on PII signatures (IP, email, etc. - hashed if necessary).
- `ozone_team_detail.html`: Manage specific team member permissions.

### UI Controls
- **Bulk Action**: Select multiple DIDs in a set and "Emit Event" (e.g., bulk label or takedown).
- **Correlation Visualizer**: Show a list of shared "signatures" between accounts.

## Implementation Steps
1. Audit and complete `ModerationService.m` logic for Sets and Signatures.
2. Register partial routes in `AdminUIHandler.m`.
3. Implement `AdminOzone` JS module for handling complex multi-step actions.
4. Create rich HTML templates using HTMX for real-time set updates.
