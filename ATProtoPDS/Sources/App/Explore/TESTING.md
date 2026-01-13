# PDS Explorer UI/UX Testing Plan

## Overview
This document outlines comprehensive testing for the PDS Explorer web interface.

## Test Categories

### 1. Core Navigation & Routing

#### 1.1 Deep Link Navigation
- [ ] **Home page load**: Navigate to `/` - should show empty state
- [ ] **Direct DID link**: Navigate to `#/{did}` - should load account and show DID doc
- [ ] **Direct collections link**: Navigate to `#/{did}/collections` - should show collections
- [ ] **Direct collection records**: Navigate to `#/{did}/{collection}` - should show records
- [ ] **Direct record link**: Navigate to `#/{did}/{collection}/{rkey}` - should show record detail
- [ ] **CID decoder link**: Navigate to `#/cid-decode` - should show decoder
- [ ] **CID decoder with value**: Navigate to `#/cid-decode/{cid}` - should pre-fill and decode
- [ ] **Invalid DID**: Navigate to `#/did:plc:invalid` - should show error gracefully
- [ ] **Invalid route**: Navigate to `#/invalid/path` - should handle gracefully

#### 1.2 Browser Navigation
- [ ] **Back button**: Navigate through multiple views, press back - should return correctly
- [ ] **Forward button**: After going back, press forward - should work
- [ ] **URL updates**: Each navigation should update the URL hash
- [ ] **Refresh**: Refresh page on any view - should restore state from URL

#### 1.3 Sidebar Navigation
- [ ] **Account click**: Click account - should navigate and update URL
- [ ] **DID Document nav**: Click nav item - should switch view
- [ ] **PLC Operations nav**: Click nav item - should switch view
- [ ] **Collections nav**: Click nav item - should switch view
- [ ] **CID Decoder nav**: Click nav item - should switch view
- [ ] **Nav without account**: Click nav items without account selected - should prompt

### 2. Account & Identity Features

#### 2.1 Account List
- [ ] **Load accounts**: On page load, accounts should appear in sidebar
- [ ] **Account highlight**: Selected account should be visually highlighted
- [ ] **Empty state**: If no accounts, show appropriate message
- [ ] **Multiple accounts**: If multiple accounts exist, all should be listed

#### 2.2 Search/Lookup
- [ ] **DID search**: Enter DID in search - should navigate to account
- [ ] **Handle search**: Enter handle - should resolve and navigate
- [ ] **Invalid search**: Enter invalid value - should show error
- [ ] **Enter key**: Pressing Enter should trigger search
- [ ] **Loading state**: During lookup, input should be disabled

#### 2.3 DID Document View
- [ ] **Identity properties**: Should show id, alsoKnownAs
- [ ] **Verification methods**: Should show keys with type and truncated value
- [ ] **Services**: Should show service endpoints
- [ ] **Full JSON**: Should have expandable full document view
- [ ] **Local DID fallback**: Local accounts should show generated DID doc

#### 2.4 PLC Operations View
- [ ] **Operations list**: Should show PLC operation history
- [ ] **Operation details**: Each operation should show type, timestamp
- [ ] **Local fallback**: Local accounts should show simulated operation
- [ ] **Empty state**: Account without PLC history should show message

### 3. Repository & Records

#### 3.1 Collections View
- [ ] **Collection list**: Should show all collections with records
- [ ] **Collection count**: Should show correct collection count
- [ ] **View Records button**: Should navigate to records list
- [ ] **Empty state**: Account with no records should show "No collections"

#### 3.2 Records List View
- [ ] **Records table**: Should show rkey, CID (truncated), action button
- [ ] **Record count**: Should show correct count in description
- [ ] **Back to Collections**: Button should navigate back
- [ ] **View Detail button**: Should navigate to record detail
- [ ] **Empty collection**: Collection with no records should show message
- [ ] **Pagination**: If >50 records, should handle pagination (future)

#### 3.3 Record Detail View
- [ ] **Formatted view**: Should show type-specific formatted view
- [ ] **Raw JSON view**: Toggle should show raw JSON
- [ ] **View toggle**: Switching between views should work
- [ ] **URI display**: Should show full AT URI
- [ ] **CID display**: Should show full CID
- [ ] **Back to Records**: Button should navigate back

### 4. Record Type Renderers

#### 4.1 Post (app.bsky.feed.post)
- [ ] **Basic post**: Should show text content
- [ ] **Post with facets**: Links and mentions should be clickable
- [ ] **Post with images**: Should indicate images attached
- [ ] **Post with external embed**: Should show link card
- [ ] **Post with quote**: Should show quoted post reference
- [ ] **Reply post**: Should show reply indicator with parent link
- [ ] **Timestamp**: Should show formatted date

#### 4.2 Profile (app.bsky.actor.profile)
- [ ] **Display name**: Should show displayName prominently
- [ ] **Description**: Should show description text
- [ ] **Avatar indicator**: Should indicate if avatar attached
- [ ] **Banner indicator**: Should indicate if banner attached

#### 4.3 Social Graph Records
- [ ] **Follow**: Should show "Following: {did}"
- [ ] **Block**: Should show "Blocked: {did}"
- [ ] **Like**: Should show "Liked: {uri}" with link
- [ ] **Repost**: Should show "Reposted: {uri}" with link

#### 4.4 Other Record Types
- [ ] **List**: Should show name, description, purpose
- [ ] **List item**: Should show subject and list reference
- [ ] **Threadgate**: Should show rules
- [ ] **Unknown type**: Should fall back to generic field table

### 5. CID Decoder Tool

#### 5.1 Basic Functionality
- [ ] **Input field**: Should accept CID input
- [ ] **Decode button**: Should trigger decode
- [ ] **Enter key**: Should trigger decode
- [ ] **Results display**: Should show version, codec, hash algorithm, size

#### 5.2 CID Formats
- [ ] **CIDv1 base32**: Should decode correctly (bafyrei...)
- [ ] **CIDv0**: Should identify as v0 and show implicit values
- [ ] **Invalid CID**: Should show error message
- [ ] **Empty input**: Should not crash

### 6. Visual Design & UX

#### 6.1 Layout
- [ ] **Sidebar width**: Should be consistent ~250px
- [ ] **Content area**: Should have proper max-width
- [ ] **Section headers**: Should have blue gradient style
- [ ] **Tables**: Should have proper borders and alternating rows

#### 6.2 States
- [ ] **Loading states**: Should show "Loading..." during fetches
- [ ] **Error states**: Should show red error messages
- [ ] **Empty states**: Should show helpful empty messages
- [ ] **Placeholder states**: Should show prompts when no data selected

#### 6.3 Interactive Elements
- [ ] **Buttons**: Should have hover states
- [ ] **Active nav items**: Should be highlighted in blue
- [ ] **Clickable links**: Should have hover underline
- [ ] **View toggle**: Active button should be highlighted

### 7. Responsive Design

#### 7.1 Desktop (1200px+)
- [ ] **Full layout**: Sidebar + content should display properly
- [ ] **Tables**: Should not overflow

#### 7.2 Tablet (768px-1199px)
- [ ] **Layout adaptation**: Should remain usable
- [ ] **Text truncation**: Long values should truncate gracefully

#### 7.3 Mobile (320px-767px)
- [ ] **Sidebar behavior**: May need to collapse/hide
- [ ] **Touch targets**: Buttons should be large enough
- [ ] **Content readability**: Text should remain readable

### 8. Error Handling

#### 8.1 Network Errors
- [ ] **API timeout**: Should show error, not hang
- [ ] **Server down**: Should show connection error
- [ ] **Partial failure**: Should show what loaded, error for what failed

#### 8.2 Data Errors
- [ ] **Missing fields**: Should handle null/undefined gracefully
- [ ] **Invalid data**: Should not crash on malformed responses
- [ ] **Large data**: Should handle large records/lists

### 9. Accessibility (Future)

- [ ] **Keyboard navigation**: Tab through interactive elements
- [ ] **Screen reader**: ARIA labels and semantic HTML
- [ ] **Color contrast**: Text should be readable
- [ ] **Focus indicators**: Focused elements should be visible

### 10. Performance

- [ ] **Initial load**: Page should load quickly
- [ ] **Navigation**: View switches should be instant for cached data
- [ ] **Large lists**: Should handle 50+ records smoothly
- [ ] **Memory**: Should not leak memory on navigation

---

## Test Execution Notes

For each test:
1. Navigate to the starting state
2. Perform the action
3. Verify the expected outcome
4. Take screenshot if needed for documentation
5. Note any issues found

## Issue Tracking

Document issues found during testing:

| ID | Category | Description | Severity | Status |
|----|----------|-------------|----------|--------|
| 1 | Responsive | Mobile layout (375px) - sidebar doesn't collapse, content cut off | Major | Open |
| 2 | UX | No copy-to-clipboard for DIDs, URIs, CIDs | Minor | Open |
| 3 | UX | No loading spinner/indicator during API calls | Minor | Open |
| 4 | Nav | Breadcrumb links not functional (just text) | Minor | Open |
| 5 | A11y | No keyboard shortcuts for common actions | Enhancement | Open |
| 6 | UX | Handle search may timeout without visual feedback | Minor | Open |

Severity levels:
- **Critical**: Blocks core functionality
- **Major**: Significant UX impact
- **Minor**: Cosmetic or minor annoyance
- **Enhancement**: Not a bug, but could be better
