#!/bin/bash
#────────────────────────────────────────────────────────────
#  📝 SIMPLE OVERLEAF POD DEPLOYMENT
#────────────────────────────────────────────────────────────

set -e

echo "🚀 Starting Overleaf deployment..."

# Create directories
mkdir -p ~/podman_data/overleaf/{mongodb-data,redis-data,overleaf-data}

# Create environment file
cat > ~/podman_data/overleaf/.env << 'EOF'
TZ=Africa/Tunis
OVERLEAF_APP_NAME=Overleaf
OVERLEAF_SITE_URL=https://overleaf.example.com
OVERLEAF_ADMIN_EMAIL=medzarka@live.fr
ENABLE_CONVERSIONS=true
EMAIL_CONFIRMATION_DISABLED=true
OVERLEAF_DISABLE_SIGNUPS=true
ALLOW_MONGO_ADMIN_CHECK_FAILURES=true
OVERLEAF_MONGO_URL=mongodb://localhost:27017/overleaf
REDIS_URL=redis://localhost:6379
OVERLEAF_REDIS_HOST=localhost
OVERLEAF_REDIS_PORT=6379
OAUTH2_PROXY_PROVIDER=google
OAUTH2_PROXY_CLIENT_ID=your-google-client-id
OAUTH2_PROXY_CLIENT_SECRET=your-google-client-secret
OAUTH2_PROXY_COOKIE_SECRET=your-32-byte-random-string
OAUTH2_PROXY_UPSTREAMS=http://localhost:80
OAUTH2_PROXY_HTTP_ADDRESS=0.0.0.0:4185
OAUTH2_PROXY_REDIRECT_URL=https://overleaf.example.com/oauth2/callback
OAUTH2_PROXY_EMAIL_DOMAINS=*
OAUTH2_PROXY_AUTHENTICATED_EMAILS_FILE=/etc/oauth2_proxy/emails.txt
EOF

# Create allowed emails file
echo "admin@example.com" > ~/podman_data/overleaf/allowed_emails.txt

# Clean up any existing deployment
echo "🧹 Cleaning up existing deployment..."
systemctl --user stop pod-overleaf.service 2>/dev/null || true
podman pod rm -f overleaf-pod 2>/dev/null || true

# Create pod
echo "📦 Creating Overleaf pod..."
podman pod create \
    --name overleaf-pod \
    --publish 4185:4185 \
    --network podman-network

# Deploy MongoDB (passwordless)
echo "🗄️ Deploying MongoDB..."
podman run -d \
    --name overleaf-mongodb \
    --pod overleaf-pod \
    --restart unless-stopped \
    --memory 512m \
    --volume ~/podman_data/overleaf/mongodb-data:/data/db:Z \
    mongo:6.0 --bind_ip_all --noauth

# Deploy Redis (passwordless)
echo "🔴 Deploying Redis..."
podman run -d \
    --name overleaf-redis \
    --pod overleaf-pod \
    --restart unless-stopped \
    --memory 128m \
    --volume ~/podman_data/overleaf/redis-data:/data:Z \
    redis:alpine redis-server --save 60 1 --loglevel warning

# Deploy OAuth2 Proxy
echo "🔐 Deploying OAuth2 Proxy..."
podman run -d \
    --name overleaf-oauth \
    --pod overleaf-pod \
    --restart unless-stopped \
    --memory 256m \
    --env-file ~/podman_data/overleaf/.env \
    --volume ~/podman_data/overleaf/allowed_emails.txt:/etc/oauth2_proxy/emails.txt:ro,Z \
    quay.io/oauth2-proxy/oauth2-proxy:latest-alpine

# Deploy Overleaf
echo "📝 Deploying Overleaf..."
podman run -d \
    --name overleaf \
    --pod overleaf-pod \
    --restart unless-stopped \
    --memory 2048m \
    --env-file ~/podman_data/overleaf/.env \
    --volume ~/podman_data/overleaf/overleaf-data:/var/lib/overleaf:Z \
    sharelatex/sharelatex:latest

# Wait for services to start
echo "⏳ Waiting for services to start..."
sleep 10

# Generate systemd service
echo "⚙️ Creating systemd service..."
mkdir -p ~/.config/systemd/user
podman generate systemd --new --name overleaf-pod --files
mv pod-overleaf-pod.service ~/.config/systemd/user/pod-overleaf.service
mv container-*.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable pod-overleaf.service

echo ""
echo "🎉 Overleaf deployment completed!"
echo ""
echo "📋 Next Steps:"
echo "1. Edit ~/podman_data/overleaf/.env and add your Google OAuth credentials:"
echo "   - OAUTH2_PROXY_CLIENT_ID=your-google-client-id"
echo "   - OAUTH2_PROXY_CLIENT_SECRET=your-google-client-secret"
echo "   - OAUTH2_PROXY_COOKIE_SECRET=your-32-byte-random-string"
echo ""
echo "2. Add allowed email addresses to:"
echo "   ~/podman_data/overleaf/allowed_emails.txt"
echo ""
echo "3. Restart the service:"
echo "   systemctl --user restart pod-overleaf.service"
echo ""
echo "4. Create your first admin user:"
echo "   podman exec -it overleaf /bin/bash -c \\"
echo "   \"cd /overleaf/services/web && node modules/server-ce-scripts/scripts/create-user \\"
echo "   --admin --email='admin@example.com' --password='YourPassword123'\""
echo ""
echo "5. Access Overleaf at: http://your-server:4185"
echo ""
echo "🔧 Management Commands:"
echo "  Start:  systemctl --user start pod-overleaf.service"
echo "  Stop:   systemctl --user stop pod-overleaf.service"
echo "  Status: systemctl --user status pod-overleaf.service"
echo "  Logs:   podman logs -f overleaf"
