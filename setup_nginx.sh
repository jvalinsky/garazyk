#!/bin/bash
set -e

# Configuration
DOMAIN="september.exe.xyz"
PDS_PORT="2583"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit 1
fi

echo "Setting up Nginx for $DOMAIN on port $PDS_PORT..."

# Install Nginx if missing
if ! command -v nginx &> /dev/null; then
    echo "Installing Nginx..."
    apt-get update
    apt-get install -y nginx
fi

# Create configuration
cat > /etc/nginx/sites-available/pds <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:$PDS_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Enable site
echo "Enabling site..."
ln -sf /etc/nginx/sites-available/pds /etc/nginx/sites-enabled/

# Remove default if it exists
if [ -f /etc/nginx/sites-enabled/default ]; then
    rm /etc/nginx/sites-enabled/default
fi

# Test configuration
echo "Testing Nginx configuration..."
nginx -t

# Restart Nginx
echo "Restarting Nginx..."
systemctl enable nginx
systemctl restart nginx

echo "Success! Nginx is now proxying http://$DOMAIN to port $PDS_PORT"
