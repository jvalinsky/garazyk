# Clean PDS Setup Plan

## Current State

- **VM**: $DEPLOY_HOST
- **DNS**: garazyk.xyz on Cloudflare; `pds.garazyk.xyz`, `bober.garazyk.xyz`, `admin.garazyk.xyz` all CNAME → $DEPLOY_HOST
- **TLS**: exe.dev auto-issues certs for CNAMEd subdomains, but **no wildcard support** — each subdomain needs an explicit CNAME
- **Code**: git@github.com:jvalinsky/garazyk.git on `main`
- **Existing accounts**: 2 accounts with DIDs never registered at plc.directory (useless)
- **Build**: cmake on Linux, binary = `kaszlak`

## Problem with Wildcard Handles

exe.dev cannot issue wildcard TLS certs. For `*.garazyk.xyz` handles to work via HTTPS verification (`https://handle.garazyk.xyz/.well-known/atproto-did`), each handle subdomain needs:
1. An explicit CNAME record in Cloudflare DNS → $DEPLOY_HOST
2. exe.dev then auto-issues a cert for that specific subdomain

**Alternative**: DNS TXT verification (`_atproto.handle.garazyk.xyz` TXT record containing `did=did:plc:...`). This doesn't need TLS on the handle subdomain. But it requires a DNS record per handle too.

Either way, each new handle needs a DNS record. The CNAME approach is better because:
- The PDS can serve `/.well-known/atproto-did` dynamically (already implemented)
- No need to manage TXT records per account
- Standard AT Protocol verification path

**Action**: For each account created, add a CNAME in Cloudflare. This is a manual step (or scriptable via Cloudflare API if we store the API token).

## Plan

### Phase 1: Cleanup

1. Stop all services: `pds`, `garazyk-ui`, `plc`
2. Remove old data:
   - `$DEPLOY_DIR/pds-data/`
   - `$DEPLOY_DIR/.local/share/ATProtoPDS/`
   - `$DEPLOY_DIR/plc-data/`
   - `$DEPLOY_DIR/garazyk/` (old clone)
   - `$DEPLOY_DIR/build_test/`, `gnustep-build/`, `gnustep-test/`, `tools-xctest/`
   - `$DEPLOY_DIR/source.tar.gz`, misc scripts, docker files
   - `$DEPLOY_DIR/keys/` (old keys from broken setup)
3. Remove old systemd services: `plc.service`, `garazyk-ui.service`
4. Keep: `nginx`, `certbot`, SSH keys, `.gitconfig`, `.bashrc`, shelley config

### Phase 2: Fresh Build

1. `cd $DEPLOY_DIR && git clone git@github.com:jvalinsky/garazyk.git objpds` (already there, just `git pull`)
2. Install/verify build deps: `clang libblocksruntime-dev cmake libsqlite3-dev libssl-dev`
3. Build: `cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Release && cmake --build build-linux -j`

### Phase 3: Configuration

Create `$DEPLOY_DIR/objpds/config.json`:

```json
{
  "server": {
    "host": "pds.garazyk.xyz",
    "port": 2583,
    "data_dir": "$DEPLOY_DIR/pds-data",
    "issuer": "https://pds.garazyk.xyz",
    "available_user_domains": ["garazyk.xyz"]
  },
  "plc": {
    "url": "https://plc.directory"
  },
  "session": {
    "invite_code_required": true
  },
  "cors": {
    "allowed_origins": ["*"]
  },
  "links": {
    "privacy_policy": "https://garazyk.xyz/privacy",
    "terms_of_service": "https://garazyk.xyz/terms"
  }
}
```

### Phase 4: Key Management

**PDS server rotation key**: Used to sign PLC operations on behalf of all accounts.
- Generated once during first `kaszlak` run or via init command
- Stored at `$DEPLOY_DIR/pds-data/keys/server_rotation.key` (0600)
- **Backup**: Copy to `$DEPLOY_DIR/.secrets/server_rotation.key` (0700 dir, 0600 file)
- This key is the master key — if lost, you can't update DID documents for accounts

**Per-account keys**:
- Signing key: stored in actor store DB (per-DID SQLite)
- Rotation key: stored encrypted in actor store DB
- Both generated during `kaszlak account create`

**Directory permissions**:
```
$DEPLOY_DIR/pds-data/          0750
$DEPLOY_DIR/pds-data/keys/     0700
$DEPLOY_DIR/.secrets/           0700
```

### Phase 5: Setup Script (`scripts/setup-pds.sh`)

The script will:

1. **Pre-flight checks**: Verify binary exists, config exists, plc.directory is reachable
2. **Initialize data directories** with correct permissions
3. **Create admin account**:
   - `kaszlak account create --email <email> --handle admin.garazyk.xyz --config config.json`
   - This generates keys and registers the DID at plc.directory
   - Verify DID is registered: `curl https://plc.directory/<did>`
4. **Generate invite codes**:
   - `kaszlak invite create --config config.json`
5. **Verify setup**:
   - Hit `https://pds.garazyk.xyz/xrpc/com.atproto.server.describeServer`
   - Hit `https://pds.garazyk.xyz/xrpc/com.atproto.sync.listRepos`
   - Check DID resolution at plc.directory
6. **Print next steps**: DNS records to add for each handle

### Phase 6: nginx Config

Simplify to just PDS (no local PLC, no admin UI for now):

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

upstream pds_backend {
    server 127.0.0.1:2583;
    keepalive 8;
}

# PDS - pds.garazyk.xyz and *.garazyk.xyz handle subdomains
server {
    listen 80;
    listen 3000;
    server_name pds.garazyk.xyz *.garazyk.xyz;

    location / {
        proxy_pass http://pds_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_read_timeout 300s;
        proxy_connect_timeout 2s;
        client_max_body_size 100m;
    }
}

server {
    listen 80 default_server;
    listen 3000 default_server;
    server_name _;
    return 444;
}
```

### Phase 7: systemd Service

`/etc/systemd/system/pds.service` — same as current but pointing to fresh build.

### Phase 8: DNS Records Needed

In Cloudflare for garazyk.xyz:
- `pds.garazyk.xyz` → CNAME → `$DEPLOY_HOST` ✅ (exists)
- `admin.garazyk.xyz` → CNAME → `$DEPLOY_HOST` ✅ (exists)
- For each new account `<handle>.garazyk.xyz` → CNAME → `$DEPLOY_HOST`

**Important**: Cloudflare proxy must be **disabled** (grey cloud / DNS Only) for these records, otherwise exe.dev can't issue TLS certs.

## Execution Order

1. Push any uncommitted work to git
2. Stop services
3. Clean up old data and services
4. Fresh build
5. Write config
6. Write nginx config
7. Write systemd service
8. Write setup script
9. Run setup script (creates admin account, registers DID, generates invites)
10. Start PDS service
11. Verify on pdsls.dev

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| plc.directory rejects genesis op (bad signature/encoding) | Script verifies DID registration immediately after creation |
| DNS propagation delay for new handle subdomains | Use `dig` to verify before creating accounts |
| Cloudflare proxy mode intercepts traffic | Document that records must be DNS Only (grey cloud) |
| Key loss | Backup server rotation key to `.secrets/` immediately after generation |
| exe.dev TLS cert issuance delay | Wait and retry in verification step |
