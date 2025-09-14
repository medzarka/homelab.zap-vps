#!/bin/bash
#────────────────────────────────────────────────────────────
#  ☁️ SIMPLE CLOUDFLARE TUNNEL WITH DHCP-STYLE IP ASSIGNMENT
#────────────────────────────────────────────────────────────

set -e

echo "☁️ Starting Cloudflare Tunnel deployment with DHCP-style IP assignment..."

# Network Configuration
NETWORK_NAME="zap-vps-podman-network"
NETWORK_SUBNET="10.2.1.0/24"
NETWORK_IP_RANGE="10.2.1.128/25"  # IPs 10.88.1.128-10.88.1.255 automatically assigned
NETWORK_GATEWAY="10.2.1.1"

# Handle Cloudflare token (ask once, save securely, reuse)
if [[ ! -f ~/.cloudflare_token ]]; then
    echo "🔑 First time setup - Cloudflare tunnel token required"
    echo "Get your token from: https://one.dash.cloudflare.com/"
    echo "Navigate to: Networks → Tunnels → Your Tunnel → Configure"
    echo ""
    read -rsp "Enter your Cloudflare tunnel token: " CLOUDFLARE_TOKEN
    echo
    
    # Validate token is not empty
    if [[ -z "$CLOUDFLARE_TOKEN" ]]; then
        echo "❌ Token cannot be empty!"
        exit 1
    fi
    
    # Save token securely
    echo "$CLOUDFLARE_TOKEN" > ~/.cloudflare_token
    chmod 600 ~/.cloudflare_token
    echo "✅ Token saved securely to ~/.cloudflare_token"
else
    echo "✅ Using saved Cloudflare token"
fi

# Read token from secure file
CLOUDFLARE_TOKEN=$(cat ~/.cloudflare_token)

# Create custom network with DHCP-style IP assignment
if ! podman network exists "$NETWORK_NAME" 2>/dev/null; then
    echo "🌐 Creating custom network with DHCP-style IP assignment: $NETWORK_NAME"
    podman network create \
        --subnet "$NETWORK_SUBNET" \
        --ip-range "$NETWORK_IP_RANGE" \
        --gateway "$NETWORK_GATEWAY" \
        "$NETWORK_NAME"
    echo "✅ Network created - IPs will be auto-assigned from range $NETWORK_IP_RANGE"
else
    echo "✅ Network $NETWORK_NAME already exists"
fi

# Create directories
mkdir -p ~/podman_data/cloudflare-custom
mkdir -p ~/podman_data/cloudflare

# Create Dockerfile if it doesn't exist
if [[ ! -f ~/podman_data/cloudflare-custom/Dockerfile ]]; then
    echo "📄 Creating custom Dockerfile..."
    cat > ~/podman_data/cloudflare-custom/Dockerfile << 'EOF'
FROM alpine:latest

# Install dependencies
RUN apk add --no-cache \
    curl \
    ca-certificates \
    wget

# Download and install cloudflared
RUN case $(uname -m) in \
        x86_64) ARCH="amd64" ;; \
        aarch64) ARCH="arm64" ;; \
        *) echo "Unsupported architecture: $(uname -m)" && exit 1 ;; \
    esac && \
    wget -q "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}" -O /usr/local/bin/cloudflared && \
    chmod +x /usr/local/bin/cloudflared

# Create non-root user
RUN addgroup -g 1000 cloudflared && \
    adduser -u 1000 -G cloudflared -s /bin/sh -D cloudflared

# Create config directory
RUN mkdir -p /home/cloudflared/.cloudflared && \
    chown -R cloudflared:cloudflared /home/cloudflared

USER cloudflared
WORKDIR /home/cloudflared

ENTRYPOINT ["cloudflared"]
EOF
fi

# Build custom image
echo "🔨 Building custom Cloudflared image..."
podman build -t localhost/cloudflared-custom:latest ~/podman_data/cloudflare-custom/

# Create environment file with actual token
cat > ~/podman_data/cloudflare/.env << EOF
TUNNEL_TOKEN=$CLOUDFLARE_TOKEN
EOF

# Clean up existing container
echo "🧹 Cleaning up existing deployment..."
systemctl --user stop container-cloudflare.service 2>/dev/null || true
podman rm -f cloudflare 2>/dev/null || true

# Deploy Cloudflare Tunnel with automatic IP assignment
echo "🚀 Deploying Cloudflare Tunnel with automatic IP assignment..."
podman run -d \
    --name cloudflare \
    --restart unless-stopped \
    --memory 256m \
    --cpu-shares 512 \
    --network "$NETWORK_NAME" \
    --env-file ~/podman_data/cloudflare/.env \
    --volume ~/podman_data/cloudflare:/home/cloudflared/.cloudflared:Z \
    --label homepage.group="Network" \
    --label homepage.name="Cloudflare Tunnel" \
    --label homepage.icon="cloudflare" \
    --label homepage.href="https://one.dash.cloudflare.com" \
    --label homepage.description="Secure tunnel to homelab services" \
    --health-cmd "curl -f http://localhost:2000/ready || exit 1" \
    --health-interval 60s \
    --health-timeout 10s \
    --health-retries 3 \
    localhost/cloudflared-custom:latest tunnel --metrics 0.0.0.0:2000 run

# Get the assigned IP address
echo "⏳ Waiting for container to start and get IP..."
sleep 10
ASSIGNED_IP=$(podman inspect cloudflare --format '{{.NetworkSettings.Networks.'"$NETWORK_NAME"'.IPAddress}}' 2>/dev/null || echo "IP not assigned yet")

# Generate systemd service
echo "⚙️ Creating systemd service..."
mkdir -p ~/.config/systemd/user
podman generate systemd --new --name cloudflare --files
mv container-cloudflare.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable container-cloudflare.service

echo ""
echo "🎉 Cloudflare Tunnel deployed with DHCP-style IP assignment!"
echo ""
echo "🌐 Network Configuration:"
echo "   Network: $NETWORK_NAME"
echo "   Subnet: $NETWORK_SUBNET"  
echo "   DHCP IP Range: $NETWORK_IP_RANGE"
echo "   Gateway: $NETWORK_GATEWAY"
echo "   Assigned IP: $ASSIGNED_IP"
echo ""
echo "📦 Features:"
echo "   ✅ Custom Alpine image with health checks"
echo "   ✅ Token saved securely (only asked once)"  
echo "   ✅ DHCP-style automatic IP assignment"
echo "   ✅ IP assigned from controlled range"
echo "   ✅ Homepage integration ready"
echo "   ✅ Systemd service enabled"
echo ""
echo "🔧 Management Commands:"
echo "  Start:    systemctl --user start container-cloudflare.service"
echo "  Stop:     systemctl --user stop container-cloudflare.service" 
echo "  Status:   systemctl --user status container-cloudflare.service"
echo "  Logs:     podman logs -f cloudflare"
echo "  Check IP: podman inspect cloudflare --format '{{.NetworkSettings.Networks.'"$NETWORK_NAME"'.IPAddress}}'"
echo ""
echo "🌐 Network Management:"
echo "  View IPs: podman network inspect $NETWORK_NAME | grep -A5 Containers"
echo "  List:     podman network ls"
echo ""
echo "🔑 Token Management:"
echo "  View:   cat ~/.cloudflare_token"
echo "  Reset:  rm ~/.cloudflare_token (will prompt on next run)"
echo ""
echo "🌐 Configure your tunnel at: https://one.dash.cloudflare.com/"
