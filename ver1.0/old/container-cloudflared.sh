#!/usr/bin/env bash
#────────────────────────────────────────────────────────────
#  🌐 CLOUDFLARE TUNNEL CONTAINER
#────────────────────────────────────────────────────────────
# Author : Mohamed Zarka  
# Version: 2025-09-12
# Repo   : HOMELAB :: ZAP-VPS
#────────────────────────────────────────────────────────────
set -Eeuo pipefail

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  📦 CLOUDFLARE TUNNEL CONFIGURATION
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ── Basic Container Info
CONTAINER_NAME="cloudflare-tunnel"
CONTAINER_DESCRIPTION="Cloudflare Tunnel (cloudflared)"
IMAGE_NAME="localhost/cloudflare-tunnel:latest" #"cloudflare/cloudflared:latest"
IMAGE_NEEDS_BUILD=true                   # Build custom image with proper entrypoint
POD_MODE=false                           # Simple standalone container
POD_NAME=""                              # Not used for standalone containers

# ── Network & Ports (outbound only - no published ports needed)
PUBLISHED_PORTS=()                       # Tunnel connects outbound to Cloudflare
NETWORK_NAME="podman-network"            # Use default bridge network

# ── Custom Image Parameters 
IMAGE_PARAMETERS="tunnel --metrics localhost:8081 --no-autoupdate run"

# ── Resource Limits (optimized for tunnel)
MEMORY_LIMIT="512m"                      # 512MB RAM (Cloudflare recommended)
MEMORY_SWAP="1024m"                      # Allow 1GB swap if needed
CPU_QUOTA="50000"                        # 0.5 CPU cores (50% of one core)
CPU_SHARES="1024"                        # Default CPU priority
BLKIO_WEIGHT="500"                       # Medium I/O priority

# ── Volume Directories (config and logs storage)
VOLUME_DIRS=(
    "config:/etc/cloudflared:Z"         # Configuration files
    "logs:/var/log:Z"                    # Log files
)

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  🗄️ DATABASE & CACHE SERVICES (DISABLED FOR TUNNEL)
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ENABLE_REDIS=false                       # No database services needed
ENABLE_POSTGRESQL=false
ENABLE_MONGODB=false

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  🔧 CUSTOM ADDITIONAL SERVICES (NONE NEEDED)
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EXTRA_CONTAINERS=()                      # No additional containers

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  🔐 ENVIRONMENT & AUTHENTICATION
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ── Environment Variables that need user input
ENV_VARS_REQUIRED=(
    "TUNNEL_TOKEN:Enter your Cloudflare tunnel token"
)

# ── Optional Environment Variables (with defaults)
ENV_VARS_OPTIONAL=(
    "TZ:Europe/Paris"
)

# ── Google OAuth2 Proxy (DISABLED - tunnel doesn't need web interface)
USE_OAUTH_PROXY=false

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ⚙️ CONTAINER OPTIONS & HEALTH CHECKS
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ── Container Options
EXTRA_OPTIONS=(
    "--security-opt=label=disable"      # Disable SELinux labeling for simplicity
    "--restart=unless-stopped"          # Auto-restart unless manually stopped
)

# ── Health Check (process-based check)
HEALTH_CHECK_ENABLED=true
HEALTH_CHECK_CMD="curl -f http://localhost:8081/ready || exit 1" # "pgrep cloudflared || exit 1"  # Check if cloudflared process is running
HEALTH_CHECK_INTERVAL="60s"             # Check every minute
HEALTH_CHECK_TIMEOUT="30s"              # 30 second timeout
HEALTH_CHECK_RETRIES=3                  # Retry 3 times before marking unhealthy

# ── Custom Containerfile (sets proper entrypoint for tunnel)
CONTAINERFILE_CONTENT='
FROM alpine:latest

# --- Packages ---------------------------------------------------------------
RUN set -e \
 && apk add --no-cache curl ca-certificates wget

# --- Download architecture-matched cloudflared ------------------------------
ARG CF_URL
RUN set -e \
 && case "$(uname -m)" in \
      x86_64)  CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" ;; \
      aarch64) CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" ;; \
      *) echo "Unsupported arch: $(uname -m)" && exit 1 ;; \
    esac \
 && wget -qO /usr/bin/cloudflared "${CF_URL}" \
 && chmod +x /usr/bin/cloudflared

ENTRYPOINT ["/usr/bin/cloudflared"]
'

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
