# Plan: Split chat.garazyk.xyz → syrena-chat, germ.garazyk.xyz → germ

**Objective:** Deploy `syrena-chat` at `chat.garazyk.xyz` (bsky client-facing) and move `germ` to `germ.garazyk.xyz` (E2EE crypto transport). Wire the PDS to proxy `chat.bsky.*` requests to the chat service.

## Current State

- `chat.garazyk.xyz` → nginx → `127.0.0.1:8082` (germ binary)
- `germ.garazyk.xyz` → does not exist (no DNS, no nginx, no TLS)
- PDS (`DEPLOY_HOST`) → handles `chat.bsky.*` locally (no `PDS_CHAT_URL` set)
- bsky clients hitting `chat.garazyk.xyz` get `MethodNotFound` for all `chat.bsky.*` methods

## Target State

```
bsky client
    │
    ▼
  PDS (garazyk.xyz) ──PDS_CHAT_URL──► chat.garazyk.xyz
    │                                      │
    │  com.atproto.*                        │  chat.bsky.*
    │  app.bsky.*                           │  (syrena-chat :2585)
    ▼                                      ▼
  Local handlers                     Conversation DB
                                         │
                                         │ (future: Germ crypto calls)
                                         ▼
                                   germ.garazyk.xyz
                                         │
                                         │  com.germnetwork.*
                                         │  (germ :8082)
                                         ▼
                                   Ciphertext store
```

## Steps

### 1. Build `syrena-chat` on the remote server

```bash
ssh DEPLOY_USER@DEPLOY_HOST
cd DEPLOY_DIR/objpds/build-linux
cmake --build . --target syrena-chat
```

Verify the binary exists and runs:
```bash
./bin/syrena-chat help
# Should print: "Syrena Chat - Standalone AT Protocol Chat Service"
```

### 2. Create data directory for syrena-chat

```bash
mkdir -p DEPLOY_DIR/chat-data
chown DEPLOY_USER:DEPLOY_USER DEPLOY_DIR/chat-data
```

### 3. Create systemd service for syrena-chat

Create `/etc/systemd/system/syrena-chat.service`:

```ini
[Unit]
Description=Garazyk Chat Service (syrena-chat)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=DEPLOY_USER
Group=DEPLOY_USER
WorkingDirectory=DEPLOY_DIR/objpds
ExecStart=DEPLOY_DIR/objpds/build-linux/bin/syrena-chat serve --port 2585 --data-dir DEPLOY_DIR/chat-data
Environment=CHAT_PDS_URL=http://127.0.0.1:2583
Environment=CHAT_PLC_URL=http://127.0.0.1:2582
Restart=on-failure
RestartSec=5
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
```

**Key env vars:**
- `CHAT_PDS_URL` — ChatAuthManager needs the PDS's JWKS endpoint to verify JWTs. The ChatConfiguration reads `PDS_URL` from env (line 37 of ChatConfiguration.m), but the docker-compose uses `CHAT_PDS_URL`. Check which the binary actually reads.

  Looking at ChatConfiguration.m line 37: `if (env[@"PDS_URL"]) self.pdsUrl = env[@"PDS_URL"];`
  So the env var is `PDS_URL`, not `CHAT_PDS_URL`. The docker-compose uses `CHAT_PDS_URL` but that's for the Docker network — the systemd service uses `PDS_URL` pointing to the local PDS.

- `CHAT_PLC_URL` — Not used by ChatConfiguration.m (only PDS_URL is read). Can omit.

**Corrected env var:**
```
Environment=PDS_URL=http://127.0.0.1:2583
```

This is critical — without it, ChatAuthManager can't verify JWTs and will either reject all requests (if pdsUrl is set but key fetch fails → 503) or accept unsigned tokens (if pdsUrl is empty → legacy trust mode, insecure).

### 4. Create systemd service for germ (update existing)

The existing germ.service should already be running on port 8082. Verify:

```bash
sudo systemctl status germ.service
```

If it doesn't exist, create `/etc/systemd/system/germ.service`:

```ini
[Unit]
Description=Garazyk Germ E2EE Mailbox
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=DEPLOY_USER
Group=DEPLOY_USER
WorkingDirectory=DEPLOY_DIR/objpds
ExecStart=DEPLOY_DIR/objpds/build-linux/bin/germ serve --port 8082 --data-dir DEPLOY_DIR/germ-data
Restart=on-failure
RestartSec=5
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
```

### 5. Add DNS record for germ.garazyk.xyz

Add an A record (or CNAME) pointing `germ.garazyk.xyz` to the same server IP as `chat.garazyk.xyz`.

### 6. Obtain TLS certificate for germ.garazyk.xyz

```bash
sudo certbot certonly --nginx -d germ.garazyk.xyz
```

Or expand the existing cert:
```bash
sudo certbot --expand -d garazyk.xyz -d pds.garazyk.xyz -d chat.garazyk.xyz -d germ.garazyk.xyz
```

### 7. Update nginx configuration

Edit the nginx config (likely `/etc/nginx/sites-enabled/garazyk.xyz` or similar).

**Change `chat.garazyk.xyz` to proxy to syrena-chat (port 2585):**

```nginx
# Chat Service - chat.garazyk.xyz
upstream chat_backend {
    server 127.0.0.1:2585;
    keepalive 8;
}

server {
    listen 80;
    listen 3000;
    server_name chat.garazyk.xyz;

    location / {
        proxy_pass http://chat_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
        proxy_connect_timeout 2s;
        client_max_body_size 10m;
    }
}
```

**Add `germ.garazyk.xyz` proxy to germ (port 8082):**

```nginx
# Germ E2EE Mailbox - germ.garazyk.xyz
upstream germ_backend {
    server 127.0.0.1:8082;
    keepalive 8;
}

server {
    listen 80;
    listen 3000;
    server_name germ.garazyk.xyz;

    location / {
        proxy_pass http://germ_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_read_timeout 300s;
        proxy_connect_timeout 2s;
        client_max_body_size 10m;
    }
}
```

Add matching HTTPS server blocks (443 ssl) once TLS certs are in place.

Verify and reload:
```bash
sudo nginx -t
sudo systemctl reload nginx
```

### 8. Start syrena-chat service

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now syrena-chat.service
sudo systemctl status syrena-chat.service
```

### 9. Verify syrena-chat is running

```bash
# Health check
curl -s http://127.0.0.1:2585/_health
# Expected: "ok"

# XRPC method existence (should return auth error, not MethodNotFound)
curl -s http://127.0.0.1:2585/xrpc/chat.bsky.convo.listConvos
# Expected: {"error":"AuthenticationRequired","message":"Authorization header missing"}
# NOT: {"error":"MethodNotFound",...}
```

### 10. Configure PDS to proxy chat.bsky.* to chat service

Set the environment variable on the PDS service:

```bash
# Edit the PDS systemd service or environment file
# Add:
Environment=PDS_CHAT_URL=http://127.0.0.1:2585
# Or for external proxy:
Environment=PDS_CHAT_URL=https://chat.garazyk.xyz
```

Then restart the PDS:
```bash
sudo systemctl restart syrena.service
```

This causes `XrpcAppBskyPack.m:119` to skip local chat handler registration:
```objc
if (!dispatcher.chatURL) {
    // These lines will NO LONGER execute:
    [XrpcChatBskyGroupPack registerWithDispatcher:dispatcher services:services];
    [XrpcChatBskyActorPack registerWithDispatcher:dispatcher services:services];
    [XrpcChatBskyConvoPack registerWithDispatcher:dispatcher services:services];
}
```

And `XrpcHandler.m:336-341` will proxy instead:
```objc
} else if (self.chatURL) {
    XrpcProxyHandler *proxy = [[XrpcProxyHandler alloc] initWithProxyURL:self.chatURL ...];
    [proxy handleRequest:request response:response];
}
```

### 11. Verify end-to-end

```bash
# Through the PDS (should proxy to chat service)
curl -s https://garazyk.xyz/xrpc/chat.bsky.convo.listConvos -H "Authorization: Bearer <valid-jwt>"
# Expected: conversation list or auth error (NOT MethodNotFound)

# Direct to chat service
curl -s https://chat.garazyk.xyz/_health
# Expected: "ok"

curl -s https://chat.garazyk.xyz/xrpc/chat.bsky.convo.listConvos
# Expected: {"error":"AuthenticationRequired",...}

# Germ at new domain
curl -s https://germ.garazyk.xyz/_health
# Expected: "ok"

curl -s https://germ.garazyk.xyz/xrpc/com.germnetwork.identity.getAnchorKey?did=test -H "Authorization: Bearer <valid-jwt>"
# Expected: 404 or key data (NOT MethodNotFound)
```

## Rollback

If something breaks:
1. Remove `PDS_CHAT_URL` from PDS env → restart PDS → local chat handlers resume
2. Revert nginx `chat.garazyk.xyz` to proxy to port 8082 (germ)
3. `sudo systemctl stop syrena-chat.service`

## Open Questions

- **`PDS_CHAT_DID`**: The XrpcProxyHandler uses `chatDID` for service-to-service auth. If the chat service doesn't have its own DID, this can be left nil (the proxy will forward the user's JWT instead). For proper service auth, register a DID for the chat service.
- **Admin secret**: ChatConfiguration has `adminSecret` but it's empty by default. Consider setting `CHAT_ADMIN_SECRET` for admin-protected endpoints.
- **Germ ↔ Chat wiring**: Not in this plan. Future work (Germ E2EE phases 4-6) will add calls from syrena-chat to germ.garazyk.xyz for crypto operations.
