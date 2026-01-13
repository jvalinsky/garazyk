#!/bin/bash
# deploy.sh - Deploy Objective-C Runner to a VM
set -e

echo "🚀 Deploying Objective-C Runner"

# Install Docker if needed
if ! command -v docker &> /dev/null; then
    echo "📦 Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
    echo "⚠️  Log out and back in for Docker permissions, then re-run."
    exit 1
fi

# Install Node.js if needed
if ! command -v node &> /dev/null; then
    echo "📦 Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt install -y nodejs
fi

# Build sandbox container
echo "🐳 Building sandbox container..."
docker build -t objc-sandbox ./sandbox

# Install dependencies
echo "📦 Installing Node dependencies..."
npm install --production

# Setup systemd service
echo "⚙️  Setting up systemd service..."
sudo cp objc-runner.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable objc-runner
sudo systemctl restart objc-runner

echo "✅ Deployment complete!"
echo "   Status: sudo systemctl status objc-runner"
echo "   Logs:   sudo journalctl -u objc-runner -f"
