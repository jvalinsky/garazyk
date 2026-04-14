# AGENTS.md

This file provides operational guidance for AI assistants working with this repository.

## Quick Reference

For detailed information, see the steering files in `.kiro/steering/`:
- `product.md` - What September PDS is and does
- `tech.md` - Build system, dependencies, testing, quality gates
- `structure.md` - Project organization and architecture

## Critical Build Rules

1. **Always use out-of-source builds** - Never run `cmake` in repo root
2. **Use XcodeGen on macOS** - Run `xcodegen generate` before building
3. **Test runner registration** - Add new test classes to `testClasses` array in `Garazyk/Tests/test_main.m`

## Quality Gates (Pre-Push)

Before pushing code, verify:
1. `xcodegen generate` succeeds
2. `xcodebuild -scheme AllTests build` succeeds
3. `./build/tests/AllTests` passes with 0 failures
4. `xcodebuild -scheme kaszlak build` succeeds
5. Fuzzers build successfully (if modified)

## Production Deployment (pds.garazyk.xyz)

**CRITICAL**: Always run `docker compose` from `docker/pds/`, NEVER from repo root.

### Secure Defaults — MANDATORY

Never weaken these without explicit user approval:
- `session.invite_code_required`: `true`
- `plc.url`: `"https://plc.directory"` (never `"mock"` in production)
- All `debug.*` flags: `false`
- `rate_limit.enabled`: `true`
- `server.issuer`: `"https://pds.garazyk.xyz"`

### Production Environment

- VM: `DEPLOY_HOST`
- Architecture: `exe.dev HTTPS → nginx:3000 → PDS:2583`
- Config: `docker/pds/config.json` (read-only mount)
- Required env: `PDS_TRUST_PROXY_HEADERS=1`

### Never Do In Production

- Set `invite_code_required` to `false`
- Use `plc.url: "mock"` outside test/dev
- Enable any `debug.*` flags
- Expose port 2583 directly (nginx handles TLS)
- Store secrets in committed config files
- Run `docker compose` from repo root

### Deployment Commands

```bash
# On VM (DEPLOY_HOST):
cd DEPLOY_DIR/objpds/docker/pds
docker compose up -d
docker compose logs -f pds
docker exec nspds kaszlak invite create

# Verify correct config:
curl -s http://localhost:2583/xrpc/com.atproto.server.describeServer
# Must show: "did":"did:web:pds.garazyk.xyz"
```

### Volume Backup

```bash
mkdir -p DEPLOY_DIR/backup
TS=$(date +%Y%m%d-%H%M%S)
docker run --rm \
  -v pds_pds_data:/data \
  -v DEPLOY_DIR/backup:/backup \
  busybox sh -c "cd /data && tar -czf /backup/pds_pds_data-$TS.tar.gz ."
```

## Session Completion Protocol

When ending a work session, you MUST:
1. Run quality gates (if code changed)
2. Push to remote — work is NOT complete until `git push` succeeds
3. File issues for remaining work

```bash
git pull --rebase
deciduous sync
git push
git status  # Must show "up to date with origin"
```

**Never stop before pushing.** Never say "ready to push when you are" — YOU must push.

## Repository Skills

Audit and analysis skills in `.opencode/skills/`:
- `atproto-endpoint-stub-finder/` - endpoint-stub auditing with XRPC coverage
- `objc-concurrency-bug-audit/` - concurrency and race condition analysis
- `objc-cryptographic-security-audit/` - cryptographic implementation review
- `objc-firehose-ordering-backpressure-audit/` - firehose reliability
- `objc-gnustep-regression-audit/` - GNUstep compatibility checks
- `objc-locking-queue-audit/` - locking and queue safety
- `objc-log-redaction-audit/` - sensitive data in logs
- `objc-oauth-dpop-conformance-audit/` - OAuth/DPoP spec compliance
- `objc-parser-hardening-audit/` - input validation and parser safety
- `objc-rate-limiting-dos-audit/` - DoS protection
- `objc-reentrancy-audit/` - reentrancy issues

## Utility Scripts

- `scripts/stub_find.sh .` - scan for TODO/FIXME/not implemented markers
- `scripts/wipe_and_rebuild.sh` - clean rebuild from scratch
- `scripts/backup_pds.sh` - SQLite-safe production backup
- `scripts/db_dump.sh` - inspect PDS database contents
- `scripts/run-tests.sh` - run all tests

## CI/CD

GitHub Actions workflows:
- `ci.yml` - macOS build+test → Linux/GNUstep build+test → Docker build → PLC integration tests
- `security.yml` - clang-tidy, fuzzing, OSV dependency scan, TruffleHog secret scan
- `static-analysis.yml` - code quality, ShellCheck, secrets scan
- `linux.yml` - Docker image builds for tagged releases
