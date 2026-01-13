# Objective-C Code Runner

A secure server for executing Objective-C code snippets from the NSPds tutorial.

## Quick Start

```bash
# 1. Build sandbox container
npm run build-sandbox

# 2. Install dependencies
npm install

# 3. Start server
npm start
```

Server runs on `http://localhost:3001`

## API

### POST /api/execute

Execute Objective-C code.

**Request:**
```json
{
  "code": "NSLog(@\"Hello!\");",
  "timeout": 5
}
```

**Response:**
```json
{
  "success": true,
  "phase": "run",
  "exitCode": 0,
  "stdout": "Hello!\n",
  "stderr": "",
  "executionTime": 234
}
```

### GET /health

Health check endpoint.

## Security

The sandbox container runs with:
- No network access (`--network none`)
- 128MB memory limit
- 5 second timeout
- Read-only filesystem
- Non-root user
- Process limit (50 PIDs)

## Self-Hosted VM Deployment

### Prerequisites

- Ubuntu 22.04+ VM
- Docker installed
- Node.js 18+
- Nginx (for reverse proxy)

### Deploy Script

```bash
# On your VM:
./deploy.sh
```

### Manual Setup

```bash
# 1. Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# 2. Install Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# 3. Clone and setup
git clone <repo> /opt/objc-runner
cd /opt/objc-runner/objc-runner
npm install
npm run build-sandbox

# 4. Run with systemd (see objc-runner.service)
sudo cp objc-runner.service /etc/systemd/system/
sudo systemctl enable objc-runner
sudo systemctl start objc-runner
```

### Nginx Reverse Proxy

```nginx
server {
    listen 443 ssl;
    server_name runner.yourdomain.com;

    location / {
        proxy_pass http://127.0.0.1:3001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```
