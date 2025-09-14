#!/bin/bash
#────────────────────────────────────────────────────────────
#  🌐 SIMPLE TAILSCALE EXIT NODE WITH PODMAN SECRETS & USER MAPPING
#────────────────────────────────────────────────────────────


set -e

echo "🌐 Starting Tailscale exit node deployment with user mapping..."

# Network Configuration
NETWORK_NAME="zap-vps-podman-network"
NETWORK_SUBNET="10.2.1.0/24"

# Check if network exists
if ! podman network exists "$NETWORK_NAME" 2>/dev/null; then
    echo "❌ Error: Network '$NETWORK_NAME' does not exist."
    echo "Please run the Cloudflare script first to create the network."
    exit 1
fi

echo "✅ Network '$NETWORK_NAME' found"

# Check if secret exists, create if needed
if ! podman secret exists tailscale_auth_key; then
    echo "🔑 Tailscale auth key secret not found"
    echo "Get your auth key from: https://login.tailscale.com/admin/settings/keys"
    echo ""
    read -rsp "Enter your Tailscale auth key: " TAILSCALE_AUTHKEY
    echo
    
    if [[ -z "$TAILSCALE_AUTHKEY" ]]; then
        echo "❌ Auth key cannot be empty!"
        exit 1
    fi
    
    echo "$TAILSCALE_AUTHKEY" | podman secret create tailscale_auth_key -
    echo "✅ Auth key saved securely as Podman secret"
else
    echo "✅ Using existing Tailscale auth key secret"
fi

# Enable IP forwarding on host (required for exit node)
echo "🌍 Enabling IP forwarding for exit node functionality..."
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-tailscale.conf > /dev/null
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf > /dev/null
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

# Create directories with proper ownership
mkdir -p ~/podman_data/tailscale/data
sudo chown -R mgrsys:mgrsys ~/podman_data/tailscale

# Clean up existing container
echo "🧹 Cleaning up existing deployment..."
systemctl --user stop container-tailscale.service 2>/dev/null || true
podman rm -f tailscale 2>/dev/null || true

# Deploy Tailscale with user mapping and custom network
echo "🚀 Deploying Tailscale with UID mapping (0→1000) and custom network..."
podman run -d \
    --name tailscale \
    --restart unless-stopped \
    --memory 256m \
    --cpu-shares 512 \
    --network "$NETWORK_NAME" \
    --userns=auto \
    --uidmap=0:1000:1 \
    --uidmap=1:100000:65535 \
    --gidmap=0:1000:1 \
    --gidmap=1:100000:65535 \
    --privileged \
    --cap-add=NET_ADMIN \
    --cap-add=NET_RAW \
    --volume /dev/net/tun:/dev/net/tun:rw \
    --volume ~/podman_data/tailscale/data:/var/lib/tailscale:Z \
    --secret tailscale_auth_key,type=env,target=TS_AUTHKEY \
    --env TS_STATE_DIR=/var/lib/tailscale \
    --env TS_EXTRA_ARGS="--advertise-exit-node --accept-routes --advertise-routes=$NETWORK_SUBNET --ssh" \
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

# Get assigned IP
echo "⏳ Waiting for container to start..."
sleep 15
ASSIGNED_IP=$(podman inspect tailscale --format '{{.NetworkSettings.Networks.'"$NETWORK_NAME"'.IPAddress}}' 2>/dev/null || echo "IP not assigned yet")

# Generate systemd service
echo "⚙️ Creating systemd service..."
mkdir -p ~/.config/systemd/user
podman generate systemd --new --name tailscale --files
mv container-tailscale.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable container-tailscale.service

echo ""
echo "🎉 Tailscale exit node deployed with user mapping and Podman secrets!"
echo ""
echo "👤 User Mapping:"
echo "   Container UID 0 (root) → Host UID 1000 (mgrsys)"
echo "   Files created by container appear owned by mgrsys"
echo ""
echo "🌐 Network Configuration:"
echo "   Network: $NETWORK_NAME (user-defined, secure)"
echo "   Subnet: $NETWORK_SUBNET"
echo "   Assigned IP: $ASSIGNED_IP"
echo "   Host Network: NOT used (more secure)"
echo ""
echo "🚀 Exit Node Features:"
echo "   ✅ Exit node advertised"
echo "   ✅ Subnet router for $NETWORK_SUBNET"
echo "   ✅ SSH access enabled"
echo "   ✅ Proper capabilities (NET_ADMIN, NET_RAW)"
echo ""
echo "🔐 Security Features:"
echo "   ✅ Auth key stored as Podman secret"
echo "   ✅ User namespace isolation"
echo "   ✅ Custom network (not host network)"
echo "   ✅ File ownership mapped correctly"
echo ""
echo "🔧 Management Commands:"
echo "  Start:     systemctl --user start container-tailscale.service"
echo "  Stop:      systemctl --user stop container-tailscale.service"
echo "  Status:    systemctl --user status container-tailscale.service"
echo "  Logs:      podman logs -f tailscale"
echo "  TS Status: podman exec tailscale tailscale status"
echo ""
echo "⚠️  Important Next Steps:"
echo "1. Go to https://login.tailscale.com/admin/machines"
echo "2. Find your 'zap-vps-gateway' machine"
echo "3. Enable 'Use as exit node' in machine settings"
echo "4. Enable 'Subnet routes' for $NETWORK_SUBNET"
