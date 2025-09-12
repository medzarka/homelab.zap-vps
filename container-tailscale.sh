#!/usr/bin/env bash
#────────────────────────────────────────────────────────────
#  🔒 TAILSCALE VPN CLIENT CONTAINER
#────────────────────────────────────────────────────────────
# Author : Mohamed Zarka  
# Version: 2025-09-12
# Repo   : HOMELAB :: ZAP-VPS
#────────────────────────────────────────────────────────────
set -Eeuo pipefail

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  📦 TAILSCALE VPN CONFIGURATION
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ── Basic Container Info
CONTAINER_NAME="tailscale-tunnel"
CONTAINER_DESCRIPTION="Tailscale VPN Client"
IMAGE_NAME="tailscale/tailscale:latest"
IMAGE_NEEDS_BUILD=false                 # Use official image directly
POD_MODE=false                          # Simple standalone container
POD_NAME=""                             # Not used for standalone containers

# ── Network & Ports (VPN client - no published ports needed)
PUBLISHED_PORTS=()                      # VPN operates at network layer
NETWORK_NAME="podman-network"           # Use default bridge network

# ── Custom Image Parameters 
IMAGE_PARAMETERS=" "


# ── Resource Limits (optimized for VPN client)
MEMORY_LIMIT="256m"                     # 256MB RAM (lightweight VPN client)
MEMORY_SWAP="512m"                      # Allow 512MB swap if needed
CPU_QUOTA="50000"                       # 0.5 CPU cores (50% of one core)
CPU_SHARES="512"                        # Lower CPU priority than main apps
BLKIO_WEIGHT="300"                      # Lower I/O priority

# ── Volume Directories (state and config storage)
VOLUME_DIRS=(
    "state:/var/lib/tailscale:Z"        # Tailscale state and keys
    "config:/etc/tailscale:Z"           # Configuration files
)

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  🗄️ DATABASE & CACHE SERVICES (DISABLED FOR VPN)
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ENABLE_REDIS=false                      # No database services needed
ENABLE_POSTGRESQL=false
ENABLE_MONGODB=false

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  🔧 CUSTOM ADDITIONAL SERVICES (NONE NEEDED)
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EXTRA_CONTAINERS=()                     # No additional containers

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  🔐 ENVIRONMENT & AUTHENTICATION
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ── Environment Variables that need user input
ENV_VARS_REQUIRED=(
    "TS_AUTHKEY:Enter your Tailscale auth key"
)

# ── Optional Environment Variables (with defaults)
ENV_VARS_OPTIONAL=(
    "TZ:Europe/Paris"                   # Timezone
    "TS_HOSTNAME:zap-vps"               # Hostname for this node
    "TS_ACCEPT_DNS:true"                # Accept DNS configuration from Tailscale
    "TS_EXTRA_ARGS:--advertise-exit-node" # Advertise as exit node
)

# ── Google OAuth2 Proxy (DISABLED - VPN doesn't need web interface)
USE_OAUTH_PROXY=false

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ⚙️ CONTAINER OPTIONS & HEALTH CHECKS
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ── Container Options (VPN requires special capabilities)
EXTRA_OPTIONS=(
    "--security-opt=label=disable"      # Disable SELinux labeling
    "--restart=unless-stopped"          # Auto-restart unless manually stopped
    "--cap-add=NET_ADMIN"               # Required for network administration
    "--cap-add=NET_RAW"                 # Required for raw network access
    "--device=/dev/net/tun"             # Required for TUN interface
    "--privileged"                      # Required for VPN functionality
)

# ── Health Check (Tailscale status check)
HEALTH_CHECK_ENABLED=true
HEALTH_CHECK_CMD="tailscale status --self=false || exit 1"  # Check VPN status
HEALTH_CHECK_INTERVAL="60s"             # Check every minute
HEALTH_CHECK_TIMEOUT="30s"              # 30 second timeout
HEALTH_CHECK_RETRIES=3                  # Retry 3 times before marking unhealthy

# ── Custom Containerfile (not needed - using official image)
CONTAINERFILE_CONTENT=''

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  🚀 EXECUTE DEPLOYMENT
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Get script directory to find template
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_SCRIPT="${SCRIPT_DIR}/podman-containers-template.sh"

# Source the template and execute deployment
if [[ -f "$TEMPLATE_SCRIPT" ]]; then
    source "$TEMPLATE_SCRIPT"
    deploy_container_stack
else
    echo "❌ Template script not found: $TEMPLATE_SCRIPT"
    echo "💡 Make sure 'podman-containers-template.sh' is in the same directory"
    echo "📁 Current directory: $SCRIPT_DIR"
    echo "📋 Available files:"
    ls -la "$SCRIPT_DIR"
    exit 1
fi
