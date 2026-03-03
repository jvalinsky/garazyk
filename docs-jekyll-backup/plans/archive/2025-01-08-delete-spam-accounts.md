# Delete Spam Accounts Implementation Plan

## Objective

Delete spam accounts from a Bluesky PDS server running on a remote NixOS VM.

## Architecture

Connect to remote NixOS VM via SSH, diagnose pdsadmin issues, use pdsadmin CLI to list accounts, identify spam accounts, and delete them using admin tools.

## Technology Stack

SSH, pdsadmin CLI, NixOS

### Task 1: Connect to Remote Server via SSH

**Files:** None

#### Step 1: SSH to Server
Run: `ssh atproto@94.237.98.73`

Expected: Successful login to NixOS server.

#### Step 2: Verify Connection
Run: `whoami && hostname`

Expected: `atproto` and server hostname.

#### Step 3: Check PDS Status
Run: `sudo systemctl status pds` (assuming PDS runs as service)

Expected: Active status.

#### Step 4: Commit
No changes to commit.

### Task 2: Diagnose pdsadmin List Error

**Files:** None

#### Step 1: Attempt pdsadmin List
Run: `sudo pdsadmin list`

Expected: "ERROR: list not found" as reported.

#### Step 2: Check Available Commands
Run: `sudo pdsadmin --help` or `sudo pdsadmin help`

Expected: List of available subcommands, including "account".

#### Step 3: Try Correct Command
Run: `sudo pdsadmin account list`

Expected: List of accounts in JSON or table format.

#### Step 4: Commit
No changes to commit.

### Task 3: List All Accounts

**Files:** Create `accounts_list.json`

#### Step 1: Run Account List Command
Run: `sudo pdsadmin account list > accounts_list.json`

Expected: File created with account data.

#### Step 2: Review List
Run: `cat accounts_list.json | head -20`

Expected: Sample of account entries with DID, handle, etc.

#### Step 3: Count Total Accounts
Run: `grep -c '"did"' accounts_list.json` (assuming JSON format)

Expected: Number of accounts.

#### Step 4: Commit
```bash
git add accounts_list.json
git commit -m "feat: list all accounts on PDS server"
```

### Task 4: Identify Spam Accounts

**Files:** Modify `accounts_list.json`, Create `spam_accounts.txt`

#### Step 1: Review Handles for Spam Patterns
Run: `grep -i "spam\|promo\|bot\|fake" accounts_list.json`

Expected: Potential spam accounts.

#### Step 2: Manually Inspect Suspicious Accounts
Run: `jq '.[] | select(.handle | contains("spam"))' accounts_list.json` (if jq available)

Expected: Filtered list.

#### Step 3: Create List of DIDs to Delete
Run: `echo "did:plc:example1" >> spam_accounts.txt` (repeat for identified)

Expected: File with one DID per line.

#### Step 4: Commit
```bash
git add spam_accounts.txt
git commit -m "feat: identify spam accounts for deletion"
```

### Task 5: Delete Spam Accounts

**Files:** Modify `spam_accounts.txt`

#### Step 1: Delete First Account
Run: `sudo pdsadmin account delete $(head -1 spam_accounts.txt)`

Expected: Success message.

#### Step 2: Verify Deletion
Run: `sudo pdsadmin account list | grep $(head -1 spam_accounts.txt)`

Expected: No output (account removed).

#### Step 3: Remove from List
Run: `sed -i '1d' spam_accounts.txt`

Expected: First line removed.

#### Step 4: Commit
```bash
git add spam_accounts.txt
git commit -m "feat: delete one spam account"
```

### Task 6: Delete Remaining Spam Accounts

**Files:** Modify `spam_accounts.txt`

#### Step 1: Loop Delete
Run: `while read did; do sudo pdsadmin account delete $did; done < spam_accounts.txt`

Expected: All deleted.

#### Step 2: Verify All Gone
Run: `sudo pdsadmin account list | wc -l`

Expected: Reduced count.

#### Step 3: Clear File
Run: `> spam_accounts.txt`

Expected: Empty file.

#### Step 4: Commit
```bash
git add spam_accounts.txt
git commit -m "feat: delete all identified spam accounts"
```

### Task 7: Final Verification

**Files:** None

#### Step 1: List Accounts Again
Run: `sudo pdsadmin account list > final_accounts_list.json`

Expected: Updated list.

#### Step 2: Compare Counts
Run: `wc -l accounts_list.json final_accounts_list.json`

Expected: Fewer lines in final list.

#### Step 3: Backup Logs if Needed
Run: `cp /pds/pds.log backup_before_deletion.log` (assuming log location)

Expected: Backup created.

#### Step 4: Commit
```bash
git add final_accounts_list.json
git commit -m "feat: verify spam account deletions"
```

---

## Related Documentation

- [Archive Index](./README.md) - Index of all archived plans
- [Current Plans](../README.md) - Active implementation plans
- [Architecture Docs](../../architecture/README.md) - System architecture documentation</content>
<parameter name="filePath">docs/plans/2025-01-08-delete-spam-accounts.md