#!/bin/bash
#set -e

# --- Configuration ---
ENV_FILE="${PODMAN_DATA_DIR}/.env"
POD_NAME="overleaf-pod"
PODMAN_DATA_DIR="${HOME}/podman_data"
POD_DIR="${PODMAN_DATA_DIR}/overleaf-pod"

POD_OVERLEAF_DIR="${POD_DIR}/overleaf"
POD_REDIS_DIR="${POD_DIR}/redis"
POD_MONGO_DIR="${POD_DIR}/mongo"

CONTAINER_OVERLEAF_NAME="overleaf-app"
CONTAINER_REDIS_NAME="redis-overleaf"
CONTAINER_MONGO_NAME="mongo-overleaf"
CONTAINER_OAUTH_NAME="oauth-overleaf"

# Create directories
mkdir -p ${POD_MONGO_DIR}/db
mkdir -p ${POD_MONGO_DIR}/configdb
mkdir -p ${POD_MONGO_DIR}/init
mkdir -p ${POD_REDIS_DIR}/data
mkdir -p ${POD_OVERLEAF_DIR}/data
mkdir -p ${POD_DIR}

# --- Create OAuth Environment File ---
cat > "${POD_DIR}/.env" << EOF
# Overleaf Configuration
OVERLEAF_MONGO_URL=mongodb://localhost:27017/overleaf?replicaSet=overleaf
OVERLEAF_REDIS_HOST=localhost
OVERLEAF_APP_NAME=Overleaf
ENABLED_LINKED_FILE_TYPES=project_file,project_output_file
ENABLE_CONVERSIONS=true
EMAIL_CONFIRMATION_DISABLED=true
OVERLEAF_SITE_URL=https://overleaf.bluewave.work
OVERLEAF_ADMIN_EMAIL=medzarka@live.fe
OVERLEAF_DISABLE_SIGNUPS=true
ALLOW_MONGO_ADMIN_CHECK_FAILURES=true

# OAuth2 Proxy Configuration
OAUTH2_PROXY_PROVIDER=google
OAUTH2_PROXY_CLIENT_ID=your-google-client-id-here
OAUTH2_PROXY_CLIENT_SECRET=your-google-client-secret-here
OAUTH2_PROXY_COOKIE_SECRET=uhc5eR1KnodE7enrQo6kR5i77xiqLx2BDTQbhxJdwL0
OAUTH2_PROXY_UPSTREAMS=http://localhost:80
OAUTH2_PROXY_HTTP_ADDRESS=0.0.0.0:4185
OAUTH2_PROXY_REDIRECT_URL=https://overleaf.bluewave.work/oauth2/callback
OAUTH2_PROXY_EMAIL_DOMAINS=*
OAUTH2_PROXY_AUTHENTICATED_EMAILS_FILE=/etc/oauth2_proxy/emails.txt
OAUTH2_PROXY_COOKIE_SECURE=true
OAUTH2_PROXY_COOKIE_HTTPONLY=true
OAUTH2_PROXY_COOKIE_SAMESITE=lax
OAUTH2_PROXY_COOKIE_DOMAINS=.bluewave.work
OAUTH2_PROXY_WHITELIST_DOMAINS=overleaf.bluewave.work
OAUTH2_PROXY_REVERSE_PROXY=true
OAUTH2_PROXY_BANNER=Overleaf LaTeX Editor
EOF

# --- Create Allowed Emails File ---
cat > "${POD_DIR}/allowed_emails.txt" << EOF
medzarka@gmail.com
admin@bluewave.work
EOF

# --- Mongo Init Script ---
cat > "${POD_MONGO_DIR}/init/mongo-init.js" << EOF
try {
  rs.status();
  console.log("Replica set already exists, skipping initialization.");
} catch (e) {
  console.log("Initializing new replica set...");
  rs.initiate({ _id: "overleaf", members: [{ _id: 0, host: "127.0.0.1:27017" }] });
}
EOF

# ---> Create the healthcheck.js file <---
cat > "${POD_MONGO_DIR}/init/healthcheck.js" <<EOF
const result = db.adminCommand({ ping: 1 });
if (result.ok === 1) {
  // Exit with 0 for success
  quit(0);
} else {
  // Exit with 1 for failure
  quit(1);
}
EOF

# --- Deploy ---
echo "Stopping and removing existing pod..."
systemctl --user stop pod-overleaf-pod.service 2>/dev/null || true
podman pod stop "${POD_NAME}" 2>/dev/null || true
podman pod rm "${POD_NAME}" 2>/dev/null || true

echo "Creating new pod: ${POD_NAME}"
# Updated port mapping for OAuth proxy
podman pod create --name "${POD_NAME}" -p "4185:4185" --network="podman-network"

echo "Starting MongoDB container..."
podman run -d --pod "${POD_NAME}" --name "${CONTAINER_MONGO_NAME}" \
  --restart=always \
  --memory=128m \
  --cpu-shares=256 \
  --volume="${POD_MONGO_DIR}/db:/data/db:Z" \
  --volume="${POD_MONGO_DIR}/configdb:/data/configdb:Z" \
  --volume="${POD_MONGO_DIR}/init/mongo-init.js:/docker-entrypoint-initdb.d/init.js:Z" \
  --volume="${POD_MONGO_DIR}/init/healthcheck.js:/healthcheck.js:ro,Z" \
  --env MONGO_INITDB_DATABASE=overleaf \
  --health-cmd='["CMD-SHELL", "mongosh --norc --quiet --file /healthcheck.js"]' \
  --health-interval=30s \
  --health-start-period=10s \
  mongo:6.0 --replSet overleaf --bind_ip_all --noauth

echo "Starting Redis container..."
podman run -d --pod "${POD_NAME}" --name "${CONTAINER_REDIS_NAME}" \
  --restart=always \
  --memory=128m \
  --cpu-shares=256 \
  --health-cmd='["CMD-SHELL", "redis-cli ping | grep PONG"]' \
  --health-interval=30s \
  --health-start-period=10s \
  --volume="${POD_REDIS_DIR}/data:/data:Z" \
  docker.io/library/redis:8-alpine redis-server --save 60 1 --loglevel warning

echo "Starting OAuth2 Proxy container..."
podman run -d --pod "${POD_NAME}" --name "${CONTAINER_OAUTH_NAME}" \
  --restart=unless-stopped \
  --memory=256m \
  --cpu-shares=512 \
  --env-file="${POD_DIR}/.env" \
  --volume="${POD_DIR}/allowed_emails.txt:/etc/oauth2_proxy/emails.txt:ro,Z" \
  --health-cmd='["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:4185/ping || exit 1"]' \
  --health-interval=30s \
  --health-start-period=10s \
  --health-retries=3 \
  quay.io/oauth2-proxy/oauth2-proxy:latest-alpine

echo "Starting Overleaf container..."
podman run -d --pod "${POD_NAME}" --name "${CONTAINER_OVERLEAF_NAME}" \
  --restart=unless-stopped \
  --memory=2048m \
  --cpu-shares=1024 \
  --env-file="${POD_DIR}/.env" \
  --volume="${POD_OVERLEAF_DIR}/data:/var/lib/overleaf:Z" \
  --label homepage.group="Production" \
  --label homepage.name="Overleaf" \
  --label homepage.icon="overleaf" \
  --label homepage.href="https://overleaf.bluewave.work" \
  --label homepage.description="Collaborative LaTeX Editor with OAuth" \
  --health-cmd='["CMD-SHELL", "curl -f http://localhost:80 || exit 1"]' \
  --health-interval=1m \
  --health-start-period=30s \
  --health-retries=3 \
  --health-timeout=10s \
  sharelatex/sharelatex:latest

echo "Deployment complete."

# Generate the files for the pod and its containers
echo "Generating systemd services..."
podman generate systemd --new --name overleaf-pod --files

# Move all generated service files
mv pod-${POD_NAME}.service ~/.config/systemd/user/
mv container-${CONTAINER_MONGO_NAME}.service ~/.config/systemd/user/
mv container-${CONTAINER_REDIS_NAME}.service ~/.config/systemd/user/
mv container-${CONTAINER_OAUTH_NAME}.service ~/.config/systemd/user/
mv container-${CONTAINER_OVERLEAF_NAME}.service ~/.config/systemd/user/

systemctl --user daemon-reload
systemctl --user enable --now pod-overleaf-pod.service

echo ""
echo "🎉 Overleaf with OAuth2 Proxy deployed successfully!"
echo ""
echo "📋 Next Steps:"
echo "1. Edit ${POD_DIR}/.env and add your Google OAuth credentials:"
echo "   - OAUTH2_PROXY_CLIENT_ID=your-google-client-id"
echo "   - OAUTH2_PROXY_CLIENT_SECRET=your-google-client-secret"
echo ""
echo "2. Add allowed email addresses to:"
echo "   ${POD_DIR}/allowed_emails.txt"
echo ""
echo "3. Restart the service:"
echo "   systemctl --user restart pod-overleaf-pod.service"
echo ""
echo "4. Access Overleaf at: https://overleaf.bluewave.work (port 4185)"
echo ""
echo "5. Create your first admin user:"
echo "   podman exec -it ${CONTAINER_OVERLEAF_NAME} /bin/bash -c \\"
echo "   \"cd /overleaf/services/web && node modules/server-ce-scripts/scripts/create-user \\"
echo "   --admin --email='medzarka@gmail.com' --password='YourStrongPassword'\""
