# Plan: Deploy E2EE Mailbox (Germ) for chat.garazyk.xyz

**Objective:** Configure and serve the `chat.garazyk.xyz` domain on the remote `DEPLOY_HOST` server, proxying requests to the Garazyk "Germ" E2EE mailbox service.

## 1. Build the `germ` Binary
The `germ` binary is the standalone E2EE mailbox service defined in `Garazyk/Binaries/germ/main.m`, but it is not currently built on the remote server.

```bash
ssh DEPLOY_USER@DEPLOY_HOST
cd DEPLOY_DIR/objpds/build-linux
cmake --build . --target germ
```

## 2. Set Up Data Directory
Create a dedicated data directory for the Germ SQLite database to persist ephemeral mailboxes and ciphertexts.

```bash
mkdir -p DEPLOY_DIR/germ-data
chown DEPLOY_USER:DEPLOY_USER DEPLOY_DIR/germ-data
```

## 3. Create Systemd Service
Create `/etc/systemd/system/germ.service` (requires `sudo`) to ensure the service runs persistently and restarts on failure.

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

Reload systemd and start the service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now germ.service
sudo systemctl status germ.service
```

## 4. Configure Nginx Proxy
Create a new Nginx block for `chat.garazyk.xyz` to proxy traffic to the internal port `8082`.
Edit `/etc/nginx/sites-enabled/garazyk.xyz` (or create a new file `/etc/nginx/sites-enabled/chat.garazyk.xyz`):

```nginx
# Germ E2EE Mailbox - chat.garazyk.xyz
server {
    listen 80;
    listen 3000;
    server_name chat.garazyk.xyz;

    location / {
        proxy_pass http://127.0.0.1:8082;
        proxy_hide_header Server;
        add_header Server $upstream_http_server always;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
        client_max_body_size 10m;
    }
}
```

Verify and reload Nginx:
```bash
sudo nginx -t
sudo systemctl reload nginx
```
