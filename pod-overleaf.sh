#!/bin/bash

#────────────────────────────────────────────────────────────
# 📝 OVERLEAF POD WITH MONGODB + REDIS + OAUTH (ALL-IN-ONE)
#────────────────────────────────────────────────────────────

# Deploys complete Overleaf pod with MongoDB, Redis, and OAuth2 protection
# Following the same pattern as VSCode deployment

#────────────────────────────────────────────────────────────

set -e

echo "📝 Starting Overleaf pod deployment with OAuth protection..."

# Configuration
NETWORK_NAME="zap-vps-podman-network"
POD_NAME="pod-overleaf"
HOST_UID=1000
HOST_GID=1000

# Check if network exists
if ! podman network exists "$NETWORK_NAME" 2>/dev/null; then
    echo "❌ Error: Network '$NETWORK_NAME' does not exist."
    echo "Please run the Cloudflare script first to create the network."
    exit 1
fi

echo "✅ Network '$NETWORK_NAME' found"

# Handle Google OAuth secrets
if ! podman secret exists google_oauth_client_id; then
    echo "🔑 Google OAuth Client ID secret not found"
    echo "Get your OAuth credentials from: https://console.cloud.google.com/"
    echo ""
    read -rsp "Enter your Google OAuth Client ID: " OAUTH_CLIENT_ID
    echo

    if [[ -z "$OAUTH_CLIENT_ID" ]]; then
        echo "❌ Client ID cannot be empty!"
        exit 1
    fi

    echo "$OAUTH_CLIENT_ID" | podman secret create google_oauth_client_id -
    echo "✅ Google OAuth Client ID saved securely"
else
    echo "✅ Using existing Google OAuth Client ID secret"
fi

if ! podman secret exists google_oauth_client_secret; then
    echo "🔑 Google OAuth Client Secret not found"
    read -rsp "Enter your Google OAuth Client Secret: " OAUTH_CLIENT_SECRET
    echo

    if [[ -z "$OAUTH_CLIENT_SECRET" ]]; then
        echo "❌ Client Secret cannot be empty!"
        exit 1
    fi

    echo "$OAUTH_CLIENT_SECRET" | podman secret create google_oauth_client_secret -
    echo "✅ Google OAuth Client Secret saved securely"
else
    echo "✅ Using existing Google OAuth Client Secret secret"
fi

# Create directories for persistent storage
mkdir -p ~/podman_data/overleaf/{mongo/db,mongo/configdb,mongo/init,redis/data,overleaf/data}
sudo chown -R mgrsys:mgrsys ~/podman_data/overleaf

# OAuth emails file
OAUTH_EMAILS_FILE=~/podman_data/overleaf/allowed_emails.txt
if [ ! -f "$OAUTH_EMAILS_FILE" ]; then
    echo "Creating allowed emails file for OAuth..."
    touch "$OAUTH_EMAILS_FILE"
    chmod 600 "$OAUTH_EMAILS_FILE"
    echo "medzarka@gmail.com" >> "$OAUTH_EMAILS_FILE"
    echo "Added default email to allowed list"
fi

# Create MongoDB initialization script
cat > ~/podman_data/overleaf/mongo/init/mongo-init.js << 'EOF'
try {
    rs.status();
    console.log("Replica set already exists, skipping initialization.");
} catch (e) {
    console.log("Initializing new replica set...");
    rs.initiate({ _id: "overleaf", members: [{ _id: 0, host: "127.0.0.1:27017" }] });
}
EOF

# Create MongoDB health check script
cat > ~/podman_data/overleaf/mongo/init/healthcheck.js << 'EOF'
try {
    var status = rs.status();
    if (status.ok === 1) {
        print("MongoDB replica set is healthy");
        quit(0);
    } else {
        print("MongoDB replica set is not healthy");
        quit(1);
    }
} catch (e) {
    print("Error checking MongoDB health: " + e);
    quit(1);
}
EOF

# Clean up existing pod
echo "🧹 Cleaning up existing deployment..."
systemctl --user stop "pod-$POD_NAME.service" 2>/dev/null || true
podman pod stop "$POD_NAME" 2>/dev/null || true
podman pod rm -f "$POD_NAME" 2>/dev/null || true

# Create the pod
echo "📝 Creating Overleaf pod..."
podman pod create \
    --name "$POD_NAME" \
    --network "$NETWORK_NAME" \
    --publish 4181:4181 \
    --label homepage.group="Productivity" \
    --label homepage.name="Overleaf LaTeX Editor" \
    --label homepage.icon="overleaf" \
    --label homepage.href="http://overleaf.local:4181" \
    --label homepage.description="Collaborative LaTeX editor with OAuth"

# Deploy MongoDB container
echo "🗄️ Deploying MongoDB container..."
podman run -d \
    --pod "$POD_NAME" \
    --name overleaf-mongo \
    --memory 1024m \
    --cpu-shares 1024 \
    --cpus 1.0 \
    --env PUID=$HOST_UID \
    --env PGID=$HOST_GID \
    --volume ~/podman_data/overleaf/mongo/db:/data/db:Z,U \
    --volume ~/podman_data/overleaf/mongo/configdb:/data/configdb:Z,U \
    --volume ~/podman_data/overleaf/mongo/init:/docker-entrypoint-initdb.d:Z,U \
    --health-cmd "mongosh --eval 'rs.status()' --quiet || exit 1" \
    --health-interval 30s \
    --health-timeout 10s \
    --health-retries 5 \
    --health-start-period 60s \
    mongo:6.0 \
    mongod --replSet overleaf

# Deploy Redis container
echo "📦 Deploying Redis container..."
podman run -d \
    --pod "$POD_NAME" \
    --name overleaf-redis \
    --memory 256m \
    --cpu-shares 512 \
    --cpus 0.5 \
    --env PUID=$HOST_UID \
    --env PGID=$HOST_GID \
    --volume ~/podman_data/overleaf/redis/data:/data:Z,U \
    --health-cmd "redis-cli ping" \
    --health-interval 60s \
    --health-timeout 5s \
    --health-retries 3 \
    redis:7-alpine \
    redis-server --appendonly yes

# Wait for MongoDB and Redis to be ready
echo "⏳ Waiting for database services to initialize..."
sleep 20

# Deploy Overleaf container
echo "📝 Deploying Overleaf container..."
podman run -d \
    --pod "$POD_NAME" \
    --name overleaf-app \
    --memory 2048m \
    --cpu-shares 2048 \
    --cpus 2.0 \
    --env PUID=$HOST_UID \
    --env PGID=$HOST_GID \
    --env OVERLEAF_APP_NAME="ZAP-VPS Overleaf" \
    --env OVERLEAF_MONGO_URL=mongodb://localhost:27017/overleaf?replicaSet=overleaf \
    --env OVERLEAF_REDIS_HOST="localhost" \
    --env OVERLEAF_SITE_URL=https://overleaf.bluewave.work \
    --env OVERLEAF_NAV_TITLE="ZAP-VPS LaTeX Editor" \
    --env ENABLED_LINKED_FILE_TYPES=url,project_file,project_output_file \
    --env ENABLE_CONVERSIONS=true \
    --env EMAIL_CONFIRMATION_DISABLED="false" \
    --env OVERLEAF_DISABLE_SIGNUPS="true" \
    --volume ~/podman_data/overleaf/overleaf/data:/var/lib/sharelatex:Z,U \
    --health-cmd "curl -f http://localhost:3000/status || exit 1" \
    --health-interval 60s \
    --health-timeout 10s \
    --health-retries 5 \
    sharelatex/sharelatex:latest

# TODO SMTP configuration for email notifications

# Deploy OAuth2-Proxy container
echo "🔐 Deploying Google OAuth2-Proxy container..."
podman run -d \
    --pod "$POD_NAME" \
    --name overleaf-google-oauth \
    --memory 128m \
    --cpu-shares 256 \
    --cpus 0.5 \
    --volume "${OAUTH_EMAILS_FILE}:/etc/oauth2_proxy/emails.txt:ro,Z,U" \
    --env OAUTH2_PROXY_CLIENT_ID=$(podman run --rm --secret google_oauth_client_id alpine cat "/run/secrets/google_oauth_client_id") \
    --env OAUTH2_PROXY_CLIENT_SECRET=$(podman run --rm --secret google_oauth_client_secret alpine cat "/run/secrets/google_oauth_client_secret") \
    --env OAUTH2_PROXY_COOKIE_SECRET=$(python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())') \
    --env OAUTH2_PROXY_HTTP_ADDRESS=0.0.0.0:4181 \
    --env OAUTH2_PROXY_UPSTREAMS=http://localhost:3000 \
    --env OAUTH2_PROXY_PROVIDER=google \
    --env OAUTH2_PROXY_EMAIL_DOMAINS=* \
    --env OAUTH2_PROXY_REDIRECT_URL=https://overleaf.bluewave.work/oauth2/callback \
    --env OAUTH2_PROXY_CUSTOM_SIGN_IN_LOGO="https://cdn.overleaf.com/img/ol-brand/overleaf_og_logo.png" \
    --env OAUTH2_PROXY_TITLE="Overleaf LaTeX Editor" \
    --env OAUTH2_PROXY_FOOTER="Collaborative LaTeX Editor with OAuth Protection" \
    --env OAUTH2_PROXY_AUTHENTICATED_EMAILS_FILE=/etc/oauth2_proxy/emails.txt \
    --env OAUTH2_PROXY_COOKIE_HTTPONLY=true \
    --env OAUTH2_PROXY_COOKIE_SECURE=true \
    --env OAUTH2_PROXY_COOKIE_SAMESITE=lax \
    --env OAUTH2_PROXY_SESSION_STORE_TYPE=cookie \
    --env OAUTH2_PROXY_COOKIE_EXPIRE=168h \
    --health-cmd "wget --no-verbose --tries=1 --spider http://localhost:4181/ping || exit 1" \
    --health-interval 30s \
    --health-timeout 10s \
    --health-retries 3 \
    quay.io/oauth2-proxy/oauth2-proxy:latest-alpine

# Get assigned IP
echo "⏳ Waiting for pod to fully initialize..."
sleep 15

ASSIGNED_IP=$(podman pod inspect "$POD_NAME" --format '{{.InfraContainerID}}' | xargs podman inspect --format '{{.NetworkSettings.Networks.'"$NETWORK_NAME"'.IPAddress}}' 2>/dev/null || echo "IP not assigned yet")

# Generate systemd service
echo "⚙️ Creating systemd service..."
mkdir -p ~/.config/systemd/user
podman generate systemd --new --name "$POD_NAME" --files
mv "pod-$POD_NAME.service" ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable "pod-$POD_NAME.service"

echo ""
echo "🎉 Overleaf pod deployed successfully!"
echo ""
echo "🏗️ Pod Architecture:"
echo " 📝 Overleaf: Full-featured LaTeX editor"
echo " 🗄️ MongoDB: Document database with replica set"
echo " 📦 Redis: Session and cache storage"
echo " 🔐 OAuth2-Proxy: Google authentication gateway"
echo ""
echo "🎛️ Pod Configuration:"
echo " Network: $NETWORK_NAME"
echo " Assigned IP: $ASSIGNED_IP"
echo " Overleaf Port: 3000 (internal)"
echo " OAuth Port: 4181 (external access)"
echo ""
echo "💾 Resource Allocation:"
echo " Overleaf: 2GB RAM, 2.0 CPU cores (LaTeX compilation)"
echo " MongoDB: 1GB RAM, 1.0 CPU cores (database operations)"
echo " Redis: 256MB RAM, 0.5 CPU cores (caching)"
echo " OAuth: 128MB RAM, 0.5 CPU cores (lightweight proxy)"
echo ""
echo "🌐 Access Points:"
echo " OAuth Protected: http://$ASSIGNED_IP:4181 (Google login required)"
echo " Direct Overleaf: http://$ASSIGNED_IP:3000 (internal access only)"
echo " Via Tailscale: Access from any Tailscale device"
echo ""
echo "📁 Persistent Storage:"
echo " Overleaf Data: ~/podman_data/overleaf/overleaf/data"
echo " MongoDB Database: ~/podman_data/overleaf/mongo/db"
echo " Redis Cache: ~/podman_data/overleaf/redis/data"
echo " OAuth Config: ~/podman_data/overleaf/allowed_emails.txt"
echo ""
echo "🔧 Management Commands:"
echo " Start Pod: systemctl --user start pod-$POD_NAME.service"
echo " Stop Pod: systemctl --user stop pod-$POD_NAME.service"
echo " Status: systemctl --user status pod-$POD_NAME.service"
echo " Overleaf Logs: podman logs overleaf-app"
echo " MongoDB Logs: podman logs mongo-overleaf"
echo " Redis Logs: podman logs redis-overleaf"
echo " OAuth Logs: podman logs google-oauth-overleaf"
echo ""
echo "🔑 Secret Management:"
echo " OAuth Client ID: podman secret inspect google_oauth_client_id"
echo " OAuth Secret: podman secret inspect google_oauth_client_secret"
echo ""
echo "📋 Database Health:"
echo " MongoDB Status: podman exec mongo-overleaf mongosh --eval 'rs.status()'"
echo " Redis Status: podman exec redis-overleaf redis-cli ping"
echo ""
echo "🌟 Your collaborative LaTeX environment is ready!"
echo "🚀 Access via Google OAuth at: http://$ASSIGNED_IP:4181"
echo ""
echo "📝 Next Steps:"
echo "1. Add allowed emails to: ~/podman_data/overleaf/allowed_emails.txt"
echo "2. Configure Cloudflare tunnel for https://overleaf.bluewave.work"
echo "3. Create your first LaTeX project!"
