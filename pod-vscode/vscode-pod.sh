#!/bin/bash
#────────────────────────────────────────────────────────────
#  🎛️ VSCODE POD WITH CUSTOM DEV IMAGE + ALPINE OAUTH2-PROXY
#────────────────────────────────────────────────────────────
# Uses custom development image with comprehensive toolset
#────────────────────────────────────────────────────────────

set -e

echo "🎛️ Starting VSCode development pod with custom image..."

# Network Configuration
NETWORK_NAME="zap-vps-podman-network"
POD_NAME="pod-vscode"
CUSTOM_IMAGE="localhost/vscode-dev-custom:latest"

# User mapping configuration
HOST_UID=1000  # mgrsys user ID
HOST_GID=1000  # mgrsys group ID

# Check if custom image exists
if ! podman image exists "$CUSTOM_IMAGE"; then
    echo "❌ Error: Custom image '$CUSTOM_IMAGE' does not exist."
    echo "Please run './build-dev-image.sh' first to build the custom image."
    exit 1
fi

echo "✅ Custom development image found"

# Check if network exists
if ! podman network exists "$NETWORK_NAME" 2>/dev/null; then
    echo "❌ Error: Network '$NETWORK_NAME' does not exist."
    echo "Please run the Cloudflare script first to create the network."
    exit 1
fi

echo "✅ Network '$NETWORK_NAME' found"

# Handle secrets (same as before)
if ! podman secret exists vscode_password; then
    echo "🔑 VSCode password secret not found"
    read -rsp "Enter your VSCode password: " VSCODE_PASSWORD
    echo
    echo "$VSCODE_PASSWORD" | podman secret create vscode_password -
    echo "✅ VSCode password saved securely as Podman secret"
else
    echo "✅ Using existing VSCode password secret"
fi

if ! podman secret exists google_oauth_client_id; then
    echo "🔑 Google OAuth Client ID secret not found"
    read -rsp "Enter your Google OAuth Client ID: " OAUTH_CLIENT_ID
    echo
    echo "$OAUTH_CLIENT_ID" | podman secret create google_oauth_client_id -
    echo "✅ Google OAuth Client ID saved securely"
else
    echo "✅ Using existing Google OAuth Client ID secret"
fi

if ! podman secret exists google_oauth_client_secret; then
    echo "🔑 Google OAuth Client Secret not found"
    read -rsp "Enter your Google OAuth Client Secret: " OAUTH_CLIENT_SECRET
    echo
    echo "$OAUTH_CLIENT_SECRET" | podman secret create google_oauth_client_secret -
    echo "✅ Google OAuth Client Secret saved securely"
else
    echo "✅ Using existing Google OAuth Client Secret secret"
fi

# Create directories for persistent storage
mkdir -p ~/podman_data/vscode/{config,workspace}
sudo chown -R mgrsys:mgrsys ~/podman_data/vscode

# Clean up existing pod
echo "🧹 Cleaning up existing deployment..."
systemctl --user stop container-vscode-dev-pod.service 2>/dev/null || true
podman pod stop "$POD_NAME" 2>/dev/null || true
podman pod rm -f "$POD_NAME" 2>/dev/null || true

# Create the pod
echo "🎛️ Creating development pod..."
podman pod create \
    --name "$POD_NAME" \
    --network "$NETWORK_NAME" \
    --publish 4180:4180 \
    --label homepage.group="Development" \
    --label homepage.name="VSCode Dev Pod" \
    --label homepage.icon="vscode" \
    --label homepage.href="http://pod-vscode:4180" \
    --label homepage.description="Full-stack development environment"

# Deploy custom VSCode container
echo "💻 Deploying custom VSCode development container..."
podman run -d \
    --pod "$POD_NAME" \
    --name vscode-app \
    --memory 4096m \
    --cpu-shares 4096 \
    --cpus 3.0 \
    --env PUID=$HOST_UID \
    --env PGID=$HOST_GID \
    --env TZ=Europe/Berlin \
    --env PASSWORD=$(podman run --rm --secret vscode_password alpine cat "/run/secrets/vscode_password") \
    --env SUDO_PASSWORD=$(podman run --rm --secret vscode_password alpine cat "/run/secrets/vscode_password") \
    --env DEFAULT_WORKSPACE=/config/workspace \
    --volume ~/podman_data/vscode/config:/config:Z \
    --volume ~/podman_data/vscode/workspace:/config/workspace:Z \
    "$CUSTOM_IMAGE"

# Deploy OAuth2-Proxy (same as before)
echo "🔐 Deploying Google OAuth2-Proxy container (Alpine)..."
podman run -d \
    --pod "$POD_NAME" \
    --name google-oauth \
    --memory 128m \
    --cpu-shares 256 \
    --cpus 0.5 \
    --env OAUTH2_PROXY_CLIENT_ID=$(podman run --rm --secret google_oauth_client_id alpine cat "/run/secrets/google_oauth_client_id") \
    --env OAUTH2_PROXY_CLIENT_SECRET=$(podman run --rm --secret google_oauth_client_secret alpine cat "/run/secrets/google_oauth_client_secret") \
    --env OAUTH2_PROXY_COOKIE_SECRET=$(openssl rand -base64 32 | tr -d '\n') \
    --env OAUTH2_PROXY_HTTP_ADDRESS=0.0.0.0:4180 \
    --env OAUTH2_PROXY_UPSTREAMS=http://localhost:8443 \
    --env OAUTH2_PROXY_PROVIDER=google \
    --env OAUTH2_PROXY_EMAIL_DOMAINS=* \
    --env OAUTH2_PROXY_REDIRECT_URL=http://localhost:4180/oauth2/callback \
    quay.io/oauth2-proxy/oauth2-proxy:latest-alpine

# Initialize development environment
echo "🔧 Initializing development environment..."
sleep 10
podman exec vscode-dev /init-dev-env.sh

# Get assigned IP and generate systemd service
ASSIGNED_IP=$(podman pod inspect "$POD_NAME" --format '{{.InfraContainerID}}' | xargs podman inspect --format '{{.NetworkSettings.Networks.'"$NETWORK_NAME"'.IPAddress}}' 2>/dev/null || echo "IP not assigned yet")

mkdir -p ~/.config/systemd/user
podman generate systemd --new --name "$POD_NAME" --files
mv "pod-$POD_NAME.service" ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable "pod-$POD_NAME.service"

echo ""
echo "🎉 Custom VSCode development pod deployed successfully!"
echo ""
echo "🏗️ Custom Image Features:"
echo "   💻 LinuxServer code-server base"
echo "   🐍 Python 3 + multiple virtual environments"
echo "   📊 Jupyter Lab/Notebook + pandas + numpy + matplotlib"
echo "   ☕ Java (8, 11, 17, 21) via SDKMAN + Maven + Gradle"
echo "   📄 LaTeX (full texlive distribution)"
echo "   🌐 Node.js + npm + Go language"
echo "   🔧 VS Code extensions pre-installed"
echo "   🐍 Conda for advanced environment management"
echo ""
echo "🎛️ Pod Configuration:"
echo "   Network: $NETWORK_NAME"
echo "   Assigned IP: $ASSIGNED_IP"
echo "   VSCode: 8443, OAuth: 4180, Jupyter: 8888"
echo ""
echo "💾 Resource Allocation:"
echo "   VSCode: 4GB RAM, 3 CPU cores (development workload)"
echo "   OAuth: 128MB RAM, 0.5 CPU cores (lightweight proxy)"
echo ""
echo "🌐 Access Points:"
echo "   OAuth Protected: http://$ASSIGNED_IP:4180"
echo "   Direct VSCode: http://$ASSIGNED_IP:8443"
echo ""
echo "🚀 Your comprehensive development environment is ready!"
echo "Initialize with: podman exec vscode-dev /init-dev-env.sh"
