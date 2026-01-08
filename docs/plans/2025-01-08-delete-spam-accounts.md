# Delete Spam Accounts Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Delete spam accounts from a bluesky PDS server running on a remote VM

**Architecture:** Connect to remote NixOS VM via SSH, diagnose pdsadmin issues, use pdsadmin CLI to list accounts, identify spam accounts, and delete them using admin tools.

**Tech Stack:** SSH, pdsadmin CLI, NixOS

### Task 1: Connect to remote server via SSH

**Files:**
- None

**Step 1: SSH to the server**

Run: `ssh atproto@94.237.98.73`

Expected: Successful login to the NixOS server.

**Step 2: Verify connection**

Run: `whoami && hostname`

Expected: `atproto` and the server's hostname.

**Step 3: Check PDS status**

Run: `sudo systemctl status pds` (assuming PDS is running as a service)

Expected: Active status.

**Step 4: Commit**

No changes yet.

### Task 2: Diagnose pdsadmin list error

**Files:**
- None

**Step 1: Attempt pdsadmin list**

Run: `sudo pdsadmin list`

Expected: "ERROR: list not found" as reported.

**Step 2: Check available commands**

Run: `sudo pdsadmin --help` or `sudo pdsadmin help`

Expected: List of available subcommands, including "account".

**Step 3: Try correct command**

Run: `sudo pdsadmin account list`

Expected: List of accounts in JSON or table format.

**Step 4: Commit**

No changes.

### Task 3: List all accounts

**Files:**
- Create: `accounts_list.json`

**Step 1: Run account list command**

Run: `sudo pdsadmin account list > accounts_list.json`

Expected: File created with account data.

**Step 2: Review the list**

Run: `cat accounts_list.json | head -20`

Expected: Sample of account entries, each with DID, handle, etc.

**Step 3: Count total accounts**

Run: `grep -c '"did"' accounts_list.json` (assuming JSON format)

Expected: Number of accounts.

**Step 4: Commit**

```bash
git add accounts_list.json
git commit -m "feat: list all accounts on PDS server"
```

### Task 4: Identify spam accounts

**Files:**
- Modify: `accounts_list.json`
- Create: `spam_accounts.txt`

**Step 1: Review handles for spam patterns**

Run: `grep -i "spam\|promo\|bot\|fake" accounts_list.json`

Expected: Potential spam accounts.

**Step 2: Manually inspect suspicious accounts**

Run: `jq '.[] | select(.handle | contains("spam"))' accounts_list.json` (if jq available)

Expected: Filtered list.

**Step 3: Create list of DIDs to delete**

Run: `echo "did:plc:example1" >> spam_accounts.txt` (repeat for identified)

Expected: File with one DID per line.

**Step 4: Commit**

```bash
git add spam_accounts.txt
git commit -m "feat: identify spam accounts for deletion"
```

### Task 5: Delete spam accounts

**Files:**
- Modify: `spam_accounts.txt`

**Step 1: Delete first account**

Run: `sudo pdsadmin account delete $(head -1 spam_accounts.txt)`

Expected: Success message.

**Step 2: Verify deletion**

Run: `sudo pdsadmin account list | grep $(head -1 spam_accounts.txt)`

Expected: No output (account gone).

**Step 3: Remove from list**

Run: `sed -i '1d' spam_accounts.txt`

Expected: First line removed.

**Step 4: Commit**

```bash
git add spam_accounts.txt
git commit -m "feat: delete one spam account"
```

### Task 6: Delete remaining spam accounts

**Files:**
- Modify: `spam_accounts.txt`

**Step 1: Loop delete**

Run: `while read did; do sudo pdsadmin account delete $did; done < spam_accounts.txt`

Expected: All deleted.

**Step 2: Verify all gone**

Run: `sudo pdsadmin account list | wc -l`

Expected: Reduced count.

**Step 3: Clear file**

Run: `> spam_accounts.txt`

Expected: Empty file.

**Step 4: Commit**

```bash
git add spam_accounts.txt
git commit -m "feat: delete all identified spam accounts"
```

### Task 7: Final verification

**Files:**
- None

**Step 1: List accounts again**

Run: `sudo pdsadmin account list > final_accounts_list.json`

Expected: Updated list.

**Step 2: Compare counts**

Run: `wc -l accounts_list.json final_accounts_list.json`

Expected: Fewer lines in final.

**Step 3: Backup logs if needed**

Run: `cp /pds/pds.log backup_before_deletion.log` (assuming log location)

Expected: Backup created.

**Step 4: Commit**

```bash
git add final_accounts_list.json
git commit -m "feat: verify spam account deletions"
```</content>
<parameter name="filePath">docs/plans/2025-01-08-delete-spam-accounts.md