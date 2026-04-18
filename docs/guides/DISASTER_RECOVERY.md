# Disaster Recovery Playbook

## Overview

This playbook provides procedures for recovering ATProto PDS from data loss, corruption, or service failure. It includes RTO/RPO targets, backup verification procedures, and step-by-step recovery processes.

---

## Recovery Objectives

### Recovery Time Objective (RTO)

**Target**: **< 30 minutes** for full service restoration

- Database corruption: 5-10 minutes
- Complete data loss: 15-30 minutes
- Point-in-time recovery: 15-30 minutes

### Recovery Point Objective (RPO)

**Target**: **< 4 hours** of data loss

Depends on backup frequency. Recommended:
- Automated daily backups (3 AM local time)
- Weekly backup retention (14 days typical)
- Monthly archival for compliance

---

## Backup Verification

### Automated Daily Verification

**Schedule**: Run automatically before server startup or via cron

**Location**: `scripts/ops/verify_backup.sh`

**Checks performed**:
1. Backup file exists and is recent (< 24 hours old)
2. Archive integrity (tar.gz can be extracted)
3. SQLite database integrity (PRAGMA integrity_check)

**Usage**:
```bash
#!/bin/bash
# scripts/ops/verify_backup.sh

BACKUP_FILE="/var/backups/atprotopds/pds-backup-latest.tar.gz"

# 1. Check file exists and is recent
if [ ! -f "$BACKUP_FILE" ]; then
    echo "ERROR: Backup file not found"
    exit 1
fi

AGE=$(( $(date +%s) - $(stat -c %Y "$BACKUP_FILE") ))
if [ $AGE -gt 86400 ]; then
    echo "ERROR: Backup is older than 24 hours"
    exit 1
fi

# 2. Verify archive integrity
tar -tzf "$BACKUP_FILE" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: Backup archive is corrupted"
    exit 1
fi

# 3. Extract to temp and verify SQLite integrity
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"

for db in "$TEMP_DIR"/*.db "$TEMP_DIR"/**/*.sqlite; do
    if [ -f "$db" ]; then
        sqlite3 "$db" "PRAGMA integrity_check;" | grep -q "ok"
        if [ $? -ne 0 ]; then
            echo "ERROR: Database $db failed integrity check"
            exit 1
        fi
    fi
done

echo "SUCCESS: Backup verified at $(date)"
```

---

## Recovery Procedures

### Scenario 1: Database Corruption

**Symptoms**:
- Service fails to start with database errors
- Error logs contain: "database corruption", "malformed database", "disk I/O error"
- `sqlite3 service.db "PRAGMA integrity_check;"` returns errors

**Recovery Steps**:

1. **Stop the service**:
   ```bash
   sudo systemctl stop pds
   # or: sudo launchctl unload /Library/LaunchDaemons/com.atproto.pds.plist
   ```

2. **Identify corrupted database**:
   ```bash
   cd /var/lib/atprotopds
   find . -name "*.db" -o -name "*.sqlite" | while read db; do
       echo "Checking $db..."
       sqlite3 "$db" "PRAGMA integrity_check;"
   done
   ```

3. **Restore from backup**:
   ```bash
   # Move corrupted DB aside for analysis
   mv service/service.db service/service.db.corrupted.$(date +%s)

   # Extract latest backup
   LATEST_BACKUP=$(ls -t /var/backups/atprotopds/pds-backup-*.tar.gz | head -1)
   tar -xzf "$LATEST_BACKUP" -C /tmp/pds-restore

   # Copy restored database
   cp /tmp/pds-restore/service/service.db service/service.db

   # Verify integrity after restore
   sqlite3 service/service.db "PRAGMA integrity_check;"
   ```

4. **Restart service**:
   ```bash
   sudo systemctl start pds
   sudo systemctl status pds
   ```

5. **Verify health**:
   ```bash
   curl -f http://localhost:2583/xrpc/_health
   echo "Health check: $?"
   ```

**Expected Recovery Time**: 5-10 minutes

**Post-Recovery**:
- Monitor logs for first 30 minutes: `journalctl -u pds -f`
- Verify account count: `sqlite3 service/service.db "SELECT COUNT(*) FROM accounts;"`
- Test critical operations (login, post creation, etc.)

---

### Scenario 2: Complete Data Loss

**Symptoms**:
- Entire data directory lost (disk failure, accidental deletion)
- Server fails to initialize databases
- Error: "data directory not found" or "cannot create databases"

**Recovery Steps**:

1. **Prepare clean environment**:
   ```bash
   sudo systemctl stop pds
   sudo rm -rf /var/lib/atprotopds/*
   sudo mkdir -p /var/lib/atprotopds
   sudo chown -R atprotopds:atprotopds /var/lib/atprotopds
   ```

2. **Extract latest backup**:
   ```bash
   LATEST_BACKUP=$(ls -t /var/backups/atprotopds/pds-backup-*.tar.gz | head -1)
   echo "Restoring from: $LATEST_BACKUP"

   sudo tar -xzf "$LATEST_BACKUP" -C /var/lib/atprotopds
   sudo chown -R atprotopds:atprotopds /var/lib/atprotopds
   ```

3. **Verify database integrity after restore**:
   ```bash
   for db in /var/lib/atprotopds/**/*.{db,sqlite}; do
       if [ -f "$db" ]; then
           sqlite3 "$db" "PRAGMA integrity_check;" || echo "FAILED: $db"
       fi
   done
   ```

4. **Restore configuration** (if lost):
   ```bash
   # Extract config from backup
   tar -xzf "$LATEST_BACKUP" config.json -O | sudo tee /etc/atprotopds/production.json > /dev/null
   sudo chown root:root /etc/atprotopds/production.json
   ```

5. **Restart service**:
   ```bash
   sudo systemctl start pds
   journalctl -u pds -f  # Monitor startup
   ```

6. **Verify all services**:
   ```bash
   # Health check
   curl -f http://localhost:2583/xrpc/_health && echo "OK" || echo "FAIL"

   # Describe server
   curl http://localhost:2583/xrpc/com.atproto.server.describeServer | jq .

   # Check metrics
   curl http://localhost:2583/metrics | head -20
   ```

**Expected Recovery Time**: 15-30 minutes

**Post-Recovery**:
- Full service verification (all endpoints tested)
- Account count verification
- Recent activity check
- Client connectivity test

---

### Scenario 3: Point-in-Time Recovery

**Use Case**: Need to restore to specific point in time (e.g., before ransomware attack or malicious operation)

**Prerequisites**: Multiple backup versions retained

**Steps**:

1. **Identify target backup**:
   ```bash
   # List available backups with timestamps
   ls -lh /var/backups/atprotopds/ | grep pds-backup

   # Find backup from before incident
   # Example: restore to 2026-04-15 03:00
   ```

2. **Test restore in separate location**:
   ```bash
   mkdir /tmp/pds-recovery-test
   SELECTED_BACKUP="/var/backups/atprotopds/pds-backup-20260415_030000.tar.gz"

   tar -xzf "$SELECTED_BACKUP" -C /tmp/pds-recovery-test

   # Verify integrity and data
   sqlite3 /tmp/pds-recovery-test/service/service.db "SELECT COUNT(*) FROM accounts;"
   sqlite3 /tmp/pds-recovery-test/service/service.db "SELECT MAX(created_at) FROM records;"
   ```

3. **Review recovered data**:
   - Check account count is acceptable
   - Verify max record timestamp (data loss extent)
   - Check for presence of expected accounts/records

4. **Proceed with full restore** (follow Scenario 2):
   ```bash
   sudo systemctl stop pds
   sudo rm -rf /var/lib/atprotopds/*
   sudo tar -xzf "$SELECTED_BACKUP" -C /var/lib/atprotopds
   sudo chown -R atprotopds:atprotopds /var/lib/atprotopds
   sudo systemctl start pds
   ```

5. **Validate recovered state**:
   - Verify account counts match expectations
   - Check latest record timestamps
   - Run full health check
   - Monitor for any issues

**Expected Recovery Time**: 15-30 minutes

**Data Loss Assessment**:
- Time since selected backup to incident = data loss window
- Example: backup at 2026-04-15 03:00, incident at 2026-04-15 14:30 = 11.5 hours of data loss

---

## Post-Recovery Verification Checklist

After any recovery procedure, verify the following:

- [ ] Service is running: `systemctl status pds`
- [ ] Health endpoint responds: `curl http://localhost:2583/xrpc/_health`
- [ ] Database files exist: `ls -la /var/lib/atprotopds/service/`
- [ ] Database integrity: Run `PRAGMA integrity_check` on all DBs
- [ ] Account count reasonable: `sqlite3 service.db "SELECT COUNT(*) FROM accounts;"`
- [ ] Recent activity visible: Check latest records in database
- [ ] WebSocket functional: `curl http://localhost:2583/xrpc/com.atproto.sync.subscribeRepos` (should upgrade to WS)
- [ ] Admin authentication works: Attempt admin login
- [ ] Blob storage operational: Upload test blob
- [ ] No errors in logs: `journalctl -u pds --since "10 minutes ago" | grep ERROR` (should be empty)
- [ ] Metrics endpoint works: `curl http://localhost:2583/metrics`

---

## Testing Schedule

### Monthly DR Drill

**First Saturday of each month at 2 PM**:

1. Notify team of planned drill
2. Select random backup from backup list
3. Spin up test environment or isolated VM
4. Restore selected backup (follow Scenario 2)
5. Run full verification checklist
6. Document actual recovery time
7. Note any issues or deviations from playbook
8. Update playbook with lessons learned
9. Report findings to team

### Quarterly Full Test

**One per quarter - full failover test**:

1. Restore backup to production environment (after scheduled maintenance window)
2. Verify full functionality with live clients
3. Test failover procedures
4. Update RTO/RPO based on actual timings

---

## Emergency Response

### Initial Assessment

When discovering data loss or corruption:

1. **DO NOT PANIC** - We have backups
2. **Stop affected service** immediately to prevent further corruption
3. **Assess impact**:
   - Is it localized (one database) or widespread (all data)?
   - How much data is affected?
   - What time period is affected?
4. **Determine which scenario applies** (see above)
5. **Follow the appropriate recovery procedure**

### Communication

1. **Internal**:
   - Notify team immediately
   - Declare status on status page
   - Open incident ticket

2. **External**:
   - Update status page: "We're experiencing technical difficulties"
   - Provide ETA for recovery based on RTO target
   - Provide updates every 15 minutes during incident

### Post-Incident

1. **Root cause analysis**: Why did this happen?
2. **Preventive measures**: How can we prevent this in the future?
3. **Update playbook**: Document lessons learned
4. **Increase monitoring**: Add alerts for early detection

---

## Emergency Contacts

- **Primary On-Call**: [FILL IN NAME] - [PHONE] - [EMAIL]
- **Secondary On-Call**: [FILL IN NAME] - [PHONE] - [EMAIL]
- **Database Expert**: [FILL IN NAME] - [PHONE] - [EMAIL]
- **Infrastructure**: [FILL IN NAME] - [PHONE] - [EMAIL]
- **On-Call Rotation**: [LINK TO ROTATION SCHEDULE]

---

## Lessons Learned Log

| Date | Incident Type | Recovery Time | Issues | Improvements Made |
|------|---------------|---------------|--------|-------------------|
| [Date] | [Type] | [XX mins] | [List] | [Changes] |
| Example | Corruption | 8 mins | Backup outdated | Automated verification added |

---

## References

- Backup Script: `scripts/ops/backup_pds.sh`
- Backup Verification: `scripts/ops/verify_backup.sh`
- Configuration Guide: `docs/guides/DEPLOYMENT.md`
- Database Documentation: `docs/05-database-layer/`
- Status Page: [URL]

---

**Last Updated**: 2026-04-17
**Next Review**: 2026-05-17
**Playbook Owner**: [NAME]
