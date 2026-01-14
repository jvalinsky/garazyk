# Pentesting the AT Protocol PDS with Metasploit

This guide explains how to start the AT Protocol PDS server and run the custom Metasploit security suite against it.

## 1. Start the PDS Server

First, you need the target running. The default port is **2583**.

```bash
# Build the server (if not already built)
cd build
make atprotopds-cli

# Start the server (foreground mode recommended for testing)
./bin/atprotopds-cli serve --foreground
```

*Note: Keep this terminal open, or run in a separate tab.*

## 2. Prepare Metasploit Environment

We have created custom modules in `security/metasploit/` and a skill to help manage them.

**Method A: Using Symlinks (Recommended)**
Ensure the modules are linked to your Metasploit directory so `msfconsole` can find them.

```bash
mkdir -p ~/.msf4/modules/auxiliary/scanner/atproto
mkdir -p ~/.msf4/modules/auxiliary/dos/atproto
mkdir -p ~/.msf4/modules/auxiliary/admin/atproto

ln -sf $(pwd)/security/metasploit/atproto_pds_scanner.rb ~/.msf4/modules/auxiliary/scanner/atproto/
ln -sf $(pwd)/security/metasploit/atproto_cbor_dos.rb ~/.msf4/modules/auxiliary/dos/atproto/
ln -sf $(pwd)/security/metasploit/atproto_jwt_bypass.rb ~/.msf4/modules/auxiliary/admin/atproto/
```

**Method B: Loading at Runtime**
Pass the module directory to msfconsole (requires correct folder structure `auxiliary/...` inside `security/metasploit`).

**Method C: Using Docker Compose (Highly Recommended for CI/Clean Environment)**
Run the entire suite in isolated containers.

```bash
docker-compose -f docker-compose.metasploit.yml up --build --exit-code-from msf-harness
```

## 3. Run the Automated Security Suite

We have a resource script (`security/metasploit/run_pds_suite.rc`) and a runner script (`scripts/run-metasploit-tests.sh`) that automate the attack flow:
1.  **Discovery**: Fingerprints the server and probes for standard endpoints.
2.  **Repo Sync Probe**: [NEW] Checks if CAR files can be retrieved without authorization.
3.  **Auth Probe**: Checks for `alg: none`, signature bypasses, and [NEW] Blob access control.
4.  **DoS Check**: Sends Allocation Bombs, Recursion Bombs, and [NEW] Large String Bombs.

**Commands:**

*Local Run (requires Metasploit installed):*
```bash
./scripts/run-metasploit-tests.sh
```

*Docker Run (automatic setup):*
```bash
docker-compose -f docker-compose.metasploit.yml up --build
```

## 4. Manual Testing

You can also run modules individually.

**Start MSF:**
```bash
msfconsole
```

**Run Scanner:**
```bash
use auxiliary/scanner/atproto/atproto_pds_scanner
set RHOSTS 127.0.0.1
set RPORT 2583
run
```

**Run DoS Test:**
```bash
use auxiliary/dos/atproto/atproto_cbor_dos
set RHOSTS 127.0.0.1
set RPORT 2583
set RECURSION_DEPTH 500
run
```

**Run Auth Bypass:**
```bash
use auxiliary/admin/atproto/atproto_jwt_bypass
set RHOSTS 127.0.0.1
set RPORT 2583
set DID did:plc:admin
run
```

**Run Blob Access Check:**
```bash
use auxiliary/admin/atproto/blob_access_check
set RHOSTS 127.0.0.1
set RPORT 2583
set CID <blob-cid>
run
```

**Run Repo Sync Probe:**
```bash
use auxiliary/scanner/atproto/repo_sync_probe
set RHOSTS 127.0.0.1
set RPORT 2583
run
```

## Reporting

The automated suite generates a JSON report `msf_report.json` in the current directory (or inside the container if using Docker). This report includes:
-   Host information.
-   Discovered vulnerabilities and service findings.
-   Timestamp and workspace details.

## Troubleshooting

*   **"Connection Refused"**: Ensure `atprotopds-cli serve` is running and the port matches `RPORT`.
*   **"Module not found"**: Verify the symlinks in `~/.msf4/modules/` match the path structure `auxiliary/[category]/atproto/`.
*   **"Ruby Error"**: Ensure you have the required gems (standard Metasploit install covers this).
