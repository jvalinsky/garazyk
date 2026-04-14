# Cappuccino UI Debugging Notes

## Issues Found & Fixes Applied

### 1. NSNotificationCenter → CPNotificationCenter
**Problem**: Using `NSNotificationCenter` (Apple Foundation) instead of `CPNotificationCenter` (Cappuccino).
**Files**: `RelayDashboardController.j:123`, `AppViewBackfillController.j:110`
**Fix**: Changed to `CPNotificationCenter`

### 2. setAutohidesScroller vs setAutohidesScrollers  
**Problem**: Typos using singular `setAutohidesScroller` instead of plural `setAutohidesScrollers`
**Files**: `PLCTimelineController.j:81`, `PLCDirectoryController.j:152`
**Fix**: Changed to `setAutohidesScrollers`

### 3. Uninitialized _queueData
**Problem**: `_queueData` array not initialized in init, causing crash when queue table accesses `.length`
**File**: `AppViewBackfillController.j:62`
**Fix**: Added `_queueData = []` to init method

### 4. ResponsiveMixin Global Declaration
**Problem**: Missing `@global CPNotificationCenter` declaration in ResponsiveMixin
**File**: `ResponsiveMixin.j:12-13`
**Fix**: Added both `@global CPNotificationCenter` and `@global CPViewFrameDidChangeNotification`

## Root Cause Analysis

The UI loads all controllers regardless of service profile, but:
- Each service profile (pds/relay/plc/appview) should only render relevant tabs
- Controllers for disabled services are still instantiated and their `rootView` is called
- This triggers bugs in controllers that won't be used on certain services

## Service Profile Configuration

| Service | Profile | Controllers Loaded |
|---------|---------|-------------------|
| PDS | `pds` | Explorer, Admin, MST, OAuthDemo |
| Relay | `relay` | Dashboard, Upstreams, Events |
| PLC | `plc` | Directory, Detail, Timeline, Metrics |
| AppView | `appview` | Backfill |

## API Endpoint Issues

- `/api/pds/accounts` - 404 (not implemented in local testnet)
- `/api/mst/accounts` - 404 (not implemented)
- These are expected in dev mode without full PDS stack

## Build & Deploy Process

```bash
# Rebuild Cappuccino UI
./scripts/build_cappuccino_ui.sh

# Rebuild Docker images
cd docker/local-network && docker compose build --no-cache

# Restart services
docker compose down && docker compose up -d
```

## Future Work

- Consider lazy-loading controllers only for active service profile
- Add API endpoint stubs for accounts/mst in dev mode
- Fix remaining warnings: unused variables (filterLower, sortedLog, valueWidth)