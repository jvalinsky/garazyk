# Docker E2E - Idempotency Verification

## Node 94

**Status**: In Progress

## Idempotency Strategy

### 1. Unique Identifiers
- Each test uses unique handles: `e2e-{timestamp|random}-{testname}`
- Prevents collision between runs
- Format: `e2e-{random}-{testname}.garazyk.xyz`

### 2. Unique Emails
- Each account uses unique email: `e2e-{random}@{testname}.test.com`
- Prevents email constraint conflicts

### 3. Test Isolation
- Tests clean up after themselves (implicitly via unique handles)
- No shared state between test runs
- Can run multiple times without conflict

### 4. Volume Management
- `docker compose down --volumes` cleans all data
- Each test run starts fresh
- Test script handles cleanup

## Verification Required
- [x] Tests use unique handles
- [x] Tests handle account creation race conditions
- [x] Tests are independent
- [ ] Run tests multiple times to verify
