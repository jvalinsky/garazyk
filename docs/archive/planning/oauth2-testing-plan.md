# OAuth2 Testing Plan

**Goal**: Debug and fix OAuth2 implementation to successfully log in with bsky clients

**Context**:
- Live PDS: `ssh DEPLOY_HOST` (behind exe.dev HTTP proxy)
- Issue: Login works on witchsky.app but posts/profiles don't render
- Error: Console shows 400 errors for atproto and bsky endpoints
- Available: Docker, git clone bsky/social-app

## Testing Strategy

### Phase 1: Build and Run Local PDS

- [ ] Build September PDS locally
  - [ ] Run `xcodegen generate` to regenerate Xcode project
  - [ ] Build CLI: `xcodebuild -scheme ATProtoPDS-CLI build`
  - [ ] Verify binary exists at `./build/bin/kaszlak`
- [ ] Create test account: `kaszlak account create`
- [ ] Start server: `kaszlak serve`
  - [ ] Verify server starts on port 2583
  - [ ] Note down admin credentials for testing

### Phase 2: Direct Endpoint Testing (Bypass exe.dev Proxy)

- [ ] Test `com.atproto.server.createSession` directly
  ```bash
  curl -X POST https://DEPLOY_HOST/xrpc/com.atproto.server.createSession \
    -H "Content-Type: application/json" \
    -d '{"identifier":"test5.garazyk.xyz","password":"TestPassword123"}'
  ```
- [ ] Test `com.atproto.server.getSession` with returned access token
- [ ] Test `app.bsky.actor.getPreferences` (requires auth)
  ```bash
  curl -X GET "http://localhost:2583/xrpc/app.bsky.actor.getPreferences" \
    -H "Authorization: Bearer <token>"
  ```
- [ ] Test `app.bsky.actor.putPreferences`
  ```bash
  curl -X POST "http://localhost:2583/xrpc/app.bsky.actor.putPreferences" \
    -H "Authorization: Bearer <token>" \
    -H "Content-Type: application/json" \
    -d '{"preferences":{"adultContentEnabled":true}}'
  ```
- [ ] Test `app.bsky.feed.getTimeline`
- [ ] Test `app.bsky.actor.getProfile` (public, no auth)
  ```bash
  curl "http://localhost:2583/xrpc/app.bsky.actor.getProfile?actor=did:plc:z72i7hdynmk6r22z5s6nt7"
  ```
- [ ] Test `app.bsky.feed.getAuthorFeed`
- [ ] Test `app.bsky.graph.getFollowers` and `getFollows`
- [ ] Test `app.bsky.notification.listNotifications`

### Phase 3: Check for Missing Endpoints

- [ ] Verify `app.bsky.feed.getPosts` is implemented (fetch by URI)
- [ ] Verify `app.bsky.graph.getMutes` is implemented
- [ ] Verify `app.bsky.graph.getBlocks` is implemented
- [ ] Verify `app.bsky.graph.getBlockedByActor` is implemented
- [ ] Verify `app.bsky.feed.getFeedGenerators` is implemented
- [ ] Verify `app.bsky.feed.getFeedGenerator` is implemented
- [ ] Verify `app.bsky.feed.getSuggestedFeeds` is implemented

### Phase 4: Database Schema Verification

- [ ] Check if `actor_preferences` table exists in database
  ```bash
  ./build/bin/kaszlak db dump service
  ```
- [ ] Verify table schema matches ActorService expectations
- [ ] Verify `getPreferencesForActor:error:` returns correct format
  - Should return: `{"preferences": {...}}`
  - Should return: `{"preferences": {}}` if no preferences

### Phase 5: Test with bsky/social-app

- [ ] Clone bsky/social-app locally
  ```bash
  git clone https://github.com/bluesky-social/social-app.git
  cd social-app
  ```
- [ ] Install dependencies
  ```bash
  npm install
  ```
- [ ] Configure to point to local PDS
  - Find config file (likely `.env` or similar)
  - Update `PDS_URL` to point to `http://localhost:2583`
- [ ] Run social-app locally
  ```bash
  npm run dev
  ```
- [ ] Attempt login with test5.garazyk.xyz / TestPassword123
- [ ] Check console for errors
- [ ] Verify posts and profile render correctly

### Phase 6: exe.dev Proxy Investigation

- [ ] Check if exe.dev proxy is stripping `Authorization` headers
  - Test with verbose logging on local PDS
  - Check server logs for incoming Authorization headers
- [ ] Verify `X-Forwarded-*` headers are being passed through
- [ ] Check if proxy is modifying request bodies
- [ ] Consider bypassing exe.dev proxy entirely for testing

### Phase 7: Response Format Verification

- [ ] Verify all responses match bsky.app API spec
- [ ] Check response structure for `getPreferences`:
  - Spec: Returns `{"preferences": {...}}`
  - Current: `{"preferences": {...}}` (verify format)
- [ ] Check response structure for `putPreferences`:
  - Spec: Returns `{"preferences": {...}}`
  - Current: `{"preferences": {...}}` (verify format)
- [ ] Verify error responses are correct:
  - 400 Bad Request
  - 401 Unauthorized
  - 404 Not Found
  - 500 Internal Server Error

### Phase 8: Authentication Flow Testing

- [ ] Test complete OAuth2 flow if implemented
  - [ ] Create OAuth2 client
  - [ ] Get authorization code
  - [ ] Exchange for access token
  - [ ] Use access token to make authenticated requests
- [ ] Test session creation and refresh
- [ ] Test JWT extraction from Authorization header
- [ ] Verify `XrpcAuthHelper.extractDIDFromAuthHeader:jwtMinter:adminController:request:response:` works correctly

### Phase 9: Live PDS Testing

- [ ] SSH into DEPLOY_HOST
- [ ] Check server logs for 400 errors
- [ ] Test endpoints directly against live PDS
- [ ] Compare responses between local and live PDS
- [ ] Identify differences causing issues

### Phase 10: Implement Missing Features

Based on test results, implement:
- [ ] Missing endpoints identified in Phase 3
- [ ] Fix any authentication issues found
- [ ] Fix any response format issues
- [ ] Fix any database schema issues
- [ ] Update tests to cover new endpoints

## Notes

- exe.dev proxy adds `X-Forwarded-*` headers
- exe.dev proxy might strip or modify `Authorization` headers
- Local testing bypasses proxy issues
- bsky/social-app is reference client implementation
