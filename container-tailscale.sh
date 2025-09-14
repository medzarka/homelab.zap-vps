#!/bin/bash
#────────────────────────────────────────────────────────────
#  🌐 SIMPLE TAILSCALE EXIT NODE WITH GATEWAY
#────────────────────────────────────────────────────────────

set -e

echo "🌐 Starting Tailscale exit node deployment..."

# Check if network exists (created by cloudflare script)
if ! podman network exists zap-vps-network; then
    echo "❌ Error: Network 'zap-vps-network' does not exist."
    echo "Please run the Cloudflare script first to create the network."
    exit 1
fi

echo "✅ Network 'zap-vps-network' found"

# Handle Tailscale auth key (ask once, save securely, reuse)
if [[ ! -f ~/.tailscale_authkey ]]; then
    echo "🔑 First time setup - Tailscale auth key required"
    echo "Get your auth key from: https://login.tailscale.com/admin/settings/keys"
    echo "Create a reusable auth key with 'Exit node' tag if needed"
    echo ""
    read -rsp "Enter your Tailscale auth key: " TAILSCALE_AUTHKEY
    echo
    
    # Validate auth key is not empty
    if [[ -z "$TAILSCALE_AUTHKEY" ]]; then
        echo "❌ Auth key cannot be empty!"
        exit 1
    fi
    
    # Save auth key securely
    echo "$TAILSCALE_AUTHKEY" > ~/.tailscale_authkey
    chmod 600 ~/.tailscale_authkey
    echo "✅ Auth key saved securely to ~/.tailscale_authkey"
else
    echo "✅ Using saved Tailscale auth key"
fi

# Read auth key from secure file
TAILSCALE_AUTHKEY=$(cat ~/.tailscale_authkey)

# Enable IP forwarding on host (required for exit node)
echo "🌍 Enabling IP forwarding for exit node functionality..."
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-tailscale.conf > /dev/null
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf > /dev/null
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

# Create tailscale state directory
mkdir -p ~/podman_data/tailscale

# Clean up existing container
echo "🧹 Cleaning up existing deployment..."
systemctl --user stop container-tailscale.service 2>/dev/null || true
podman rm -f tailscale 2>/dev/null || true

# Deploy Tailscale with exit node and gateway capabilities
echo "🚀 Deploying Tailscale exit node and gateway..."
podman run -d \
    --name tailscale \
    --restart unless-stopped \
    --memory 256m \
    --cpu-shares 512 \
    --network zap-vps-network \
    --privileged \
    --volume /dev/net/tun:/dev/net/tun:rw \
    --volume ~/podman_data/tailscale:/var/lib/tailscale:Z \
    --env TS_AUTHKEY="$TAILSCALE_AUTHKEY" \
    --env TS_STATE_DIR=/var/lib/tailscale \
    --env TS_EXTRA_ARGS="--advertise-exit-node --accept-routes --advertise-routes=10.88.1.0/24 --ssh" \
    --env TS_HOSTNAME=zap-vps-gateway \
    --label homepage.group="Network" \
    --label homepage.name="Tailscale Exit Node" \
    --label homepage.icon="tailscale" \
    --label homepage.href="https://login.tailscale.com/admin/machines" \
    --label homepage.description="VPN exit node and network gateway" \
    --health-cmd "tailscale status >/dev/null 2>&1" \
    --health-interval 60s \
    --health-timeout 10s \
    --health-retries 3 \
    tailscale/tailscale:latest

# Wait for container to start and get IP
echo "⏳ Waiting for Tailscale to initialize..."
sleep 15
ASSIGNED_IP=$(podman inspect tailscale --format '{{.NetworkSettings.Networks.zap-vps-network.IPAddress}}' 2>/dev/null || echo "IP not assigned yet")

# Generate systemd service
echo "⚙️ Creating systemd service..."
mkdir -p ~/.config/systemd/user
podman generate systemd --new --name tailscale --files
mv container-tailscale.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable container-tailscale.service

echo ""
echo "🎉 Tailscale exit node and gateway deployed successfully!"
echo ""
echo "🌐 Network Configuration:"
echo "   Network: zap-vps-network (existing)"
echo "   Subnet: 10.88.1.0/24"
echo "   Assigned IP: $ASSIGNED_IP"
echo ""
echo "🚀 Exit Node Features:"
echo "   ✅ Exit node advertised (route all internet traffic)"
echo "   ✅ Subnet router for 10.88.1.0/24"
echo "   ✅ SSH access enabled"
echo "   ✅ Accept routes from other nodes"
echo "   ✅ Gateway to zap-vps-network containers"
echo ""
echo "📦 Container Features:"
echo "   ✅ Official Tailscale image (no custom build needed)"
echo "   ✅ Auth key saved securely (only asked once)"
echo "   ✅ DHCP-style automatic IP assignment"
echo "   ✅ Homepage integration ready"
echo "   ✅ Systemd service enabled"
echo ""
echo "🔧 Management Commands:"
echo "  Start:     systemctl --user start container-tailscale.service"
echo "  Stop:      systemctl --user stop container-tailscale.service"
echo "  Status:    systemctl --user status container-tailscale.service"
echo "  Logs:      podman logs -f tailscale"
echo "  TS Status: podman exec tailscale tailscale status"
echo "  Check IP:  podman inspect tailscale --format '{{.NetworkSettings.Networks.zap-vps-network.IPAddress}}'"
echo ""
echo "🔑 Auth Key Management:"
echo "  View:   cat ~/.tailscale_authkey"
echo "  Reset:  rm ~/.tailscale_authkey (will prompt on next run)"
echo ""
echo "⚠️  Important Next Steps:"
echo "1. Go to https://login.tailscale.com/admin/machines"
echo "2. Find your 'zap-vps-gateway' machine"
echo "3. Enable 'Use as exit node' in machine settings"
echo "4. Enable 'Subnet routes' for 10.88.1.0/24"
echo ""
echo "🌍 Your VPS is now a Tailscale exit node and gateway to your container network!"
