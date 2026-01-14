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
Pass the module directory to msfconsole (requires correct folder structure `auxiliary/...` inside `security/metasploit`, which we currently don't have, so **use Method A**).

## 3. Run the Automated Security Suite

We have a resource script (`security/metasploit/run_pds_suite.rc`) that automates the attack flow:
1.  **Discovery**: Fingerprints the server.
2.  **Auth Probe**: Checks for `alg: none` and signature bypasses.
3.  **DoS Check**: Sends a controlled "Recursion Bomb" (Depth 100) to verify logic without crashing the dev machine.

**Command:**
```bash
# Run against localhost:2583 (default in the script is 8080, so we override it)
msfconsole -x "setg RPORT 2583; resource security/metasploit/run_pds_suite.rc"
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

## Troubleshooting

*   **"Connection Refused"**: Ensure `atprotopds-cli serve` is running and the port matches `RPORT`.
*   **"Module not found"**: Verify the symlinks in `~/.msf4/modules/` match the path structure `auxiliary/[category]/atproto/`.
*   **"Ruby Error"**: Ensure you have the required gems (standard Metasploit install covers this).
