#!/bin/bash
#────────────────────────────────────────────────────────────
#  ☁️ SIMPLE CLOUDFLARE TUNNEL CONTAINER
#────────────────────────────────────────────────────────────

# TODO work with container permission (--userns keep-id:uid=33,gid=33)
# DONE labels and CPU sharing

set -e

echo "Starting Cloudflare Tunnel deployment..."

# Create directory
mkdir -p ~/podman_data/cloudflare

# Create environment file
cat > ~/podman_data/cloudflare/app.env << 'EOF'
TUNNEL_TOKEN=your-cloudflare-tunnel-token-here
EOF

# Clean up existing container
echo "Cleaning up existing deployment..."
systemctl --user stop container-cloudflare.service 2>/dev/null || true
podman rm -f cloudflare 2>/dev/null || true

# Deploy Cloudflare Tunnel
echo "Deploying Cloudflare Tunnel..."
podman run -d \
    --name cloudflare \
    --restart unless-stopped \
    --memory 256m \
    --network host \
    --env-file ~/podman_data/cloudflare/.env \
    --volume ~/podman_data/cloudflare:/home/nonroot/.cloudflared:Z \
    --health-cmd "cloudflared tunnel info || exit 1" \
    --health-interval 60s \
    --health-timeout 10s \
    --health-retries 3 \
    cloudflare/cloudflared:latest tunnel run

# Wait for service to start
echo "Waiting for tunnel to start..."
sleep 10

# Generate systemd service
echo "Creating systemd service..."
mkdir -p ~/.config/systemd/user
podman generate systemd --new --name cloudflare --files
mv container-cloudflare.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable container-cloudflare.service

echo ""
echo "🎉 Cloudflare Tunnel deployment completed!"
echo ""
echo "📋 Next Steps:"
echo "1. Get your tunnel token from Cloudflare Zero Trust dashboard:"
echo "   https://one.dash.cloudflare.com/"
echo ""
echo "2. Edit ~/podman_data/cloudflare/app.env and replace:"
echo "   TUNNEL_TOKEN=your-actual-tunnel-token"
echo ""
echo "3. Restart the service:"
echo "   systemctl --user restart container-cloudflare.service"
echo ""
echo "🔧 Management Commands:"
echo "  Start:  systemctl --user start container-cloudflare.service"
echo "  Stop:   systemctl --user stop container-cloudflare.service"
echo "  Status: systemctl --user status container-cloudflare.service"
echo "  Logs:   podman logs -f cloudflare"
echo ""
echo "🌐 Your tunnel will expose services as configured in Cloudflare dashboard"
