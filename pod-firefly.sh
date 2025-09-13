#!/bin/bash
#────────────────────────────────────────────────────────────
#  💰 SIMPLE FIREFLY III POD DEPLOYMENT
#────────────────────────────────────────────────────────────
# Just works - no complexity, no variables, hardcoded values
#────────────────────────────────────────────────────────────

set -e

echo "🚀 Starting Firefly III deployment..."

# Generate valid secrets
COOKIE_SECRET=$(python3 -c "import os, base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode().rstrip('='))")
APP_KEY="base64:$(head -c 32 /dev/urandom | base64)"

# Create directories
mkdir -p ~/podman_data/firefly/{data/database,uploads}

# Set proper permissions for Firefly III
sudo chown -R ${USER}:${USER} ~/podman_data/firefly
sudo chmod -R 775 ~/podman_data/firefly

# Create SQLite database file
touch ~/podman_data/firefly/data/database/database.sqlite

# Create environment file with all configurations
cat > ~/podman_data/firefly/.env << EOF
# Firefly III Configuration
APP_KEY=$APP_KEY
SITE_OWNER=admin@bluewave.work
TZ=Africa/Tunis
DEFAULT_LANGUAGE=en_US
DEFAULT_LOCALE=en_US

# Database (SQLite)
DB_CONNECTION=sqlite
DB_DATABASE=/var/www/html/storage/database/database.sqlite

# Security
TRUSTED_PROXIES=**
APP_URL=https://firefly.bluewave.work

# Email Configuration (SMTP)
MAIL_MAILER=smtp
MAIL_HOST=smtp.gmail.com
MAIL_PORT=587
MAIL_FROM=noreply@bluewave.work
MAIL_USERNAME=medzarka@gmail.com
MAIL_PASSWORD=your-app-password
MAIL_ENCRYPTION=tls
MAIL_FROM_NAME="Firefly III"

# OAuth2 Proxy Configuration
OAUTH2_PROXY_PROVIDER=google
OAUTH2_PROXY_CLIENT_ID=your-google-client-id
OAUTH2_PROXY_CLIENT_SECRET=your-google-client-secret
OAUTH2_PROXY_COOKIE_SECRET=$COOKIE_SECRET
OAUTH2_PROXY_UPSTREAMS=http://localhost:8080
OAUTH2_PROXY_HTTP_ADDRESS=0.0.0.0:4182
OAUTH2_PROXY_REDIRECT_URL=https://firefly.bluewave.work/oauth2/callback
OAUTH2_PROXY_EMAIL_DOMAINS=*
OAUTH2_PROXY_AUTHENTICATED_EMAILS_FILE=/etc/oauth2_proxy/emails.txt
OAUTH2_PROXY_COOKIE_SECURE=true
OAUTH2_PROXY_COOKIE_HTTPONLY=true
OAUTH2_PROXY_COOKIE_SAMESITE=lax
OAUTH2_PROXY_COOKIE_DOMAINS=.bluewave.work
OAUTH2_PROXY_WHITELIST_DOMAINS=firefly.bluewave.work
OAUTH2_PROXY_REVERSE_PROXY=true
OAUTH2_PROXY_BANNER=Firefly III Personal Finance Manager
EOF

# Create allowed emails file
cat > ~/podman_data/firefly/allowed_emails.txt << EOF
admin@bluewave.work
your-email@gmail.com
EOF

# Clean up any existing deployment
echo "🧹 Cleaning up existing deployment..."
systemctl --user stop pod-firefly.service 2>/dev/null || true
podman pod rm -f firefly-pod 2>/dev/null || true

# Create pod
echo "📦 Creating Firefly III pod..."
podman pod create \
    --name firefly-pod \
    --publish 4182:4182 \
    --network podman-network

# Deploy Firefly III
echo "💰 Deploying Firefly III..."
podman run -d \
    --name firefly-app \
    --pod firefly-pod \
    --restart unless-stopped \
    --memory 1024m \
    --env-file ~/podman_data/firefly/.env \
    --volume ~/podman_data/firefly/data:/var/www/html/storage:Z \
    --volume ~/podman_data/firefly/uploads:/var/www/html/storage/upload:Z \
    --security-opt label=disable \
    --health-cmd "curl -f http://localhost:8080/health || exit 1" \
    --health-interval 60s \
    --health-timeout 10s \
    --health-retries 3 \
    fireflyiii/core:latest

# Deploy OAuth2 Proxy
echo "🔐 Deploying OAuth2 Proxy..."
podman run -d \
    --name firefly-oauth \
    --pod firefly-pod \
    --restart unless-stopped \
    --memory 256m \
    --env-file ~/podman_data/firefly/.env \
    --volume ~/podman_data/firefly/allowed_emails.txt:/etc/oauth2_proxy/emails.txt:ro,Z \
    --health-cmd "wget --no-verbose --tries=1 --spider http://localhost:4182/ping || exit 1" \
    --health-interval 30s \
    --health-timeout 10s \
    --health-retries 3 \
    quay.io/oauth2-proxy/oauth2-proxy:latest-alpine

# Wait for services to start
echo "⏳ Waiting for services to start..."
sleep 15

# Generate systemd service
echo "⚙️ Creating systemd service..."
mkdir -p ~/.config/systemd/user
podman generate systemd --new --name firefly-pod --files
mv pod-firefly-pod.service ~/.config/systemd/user/pod-firefly.service
mv container-*.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable pod-firefly.service

echo ""
echo "🎉 Firefly III deployment completed!"
echo ""
echo "📋 Next Steps:"
echo "1. Edit ~/podman_data/firefly/.env and add your credentials:"
echo "   - OAUTH2_PROXY_CLIENT_ID=your-google-client-id"
echo "   - OAUTH2_PROXY_CLIENT_SECRET=your-google-client-secret"
echo "   - MAIL_USERNAME=your-email@gmail.com"
echo "   - MAIL_PASSWORD=your-app-password"
echo ""
echo "2. Add allowed email addresses to:"
echo "   ~/podman_data/firefly/allowed_emails.txt"
echo ""
echo "3. Restart the service:"
echo "   systemctl --user restart pod-firefly.service"
echo ""
echo "4. Access Firefly III at: https://firefly.bluewave.work:4182"
echo ""
echo "5. Complete the initial setup wizard in the web interface"
echo ""
echo "🔧 Management Commands:"
echo "  Start:  systemctl --user start pod-firefly.service"
echo "  Stop:   systemctl --user stop pod-firefly.service"
echo "  Status: systemctl --user status pod-firefly.service"
echo "  Logs:   podman logs -f firefly-app"
echo ""
echo "✨ Generated APP_KEY: $APP_KEY"
echo "🔐 Generated Cookie Secret: $COOKIE_SECRET"
