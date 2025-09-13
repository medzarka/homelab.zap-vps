#!/usr/bin/env bash
#────────────────────────────────────────────────────────────
#  💻 VSCODE SERVER POD WITH OAUTH
#────────────────────────────────────────────────────────────
# Author : Mohamed Zarka  
# Version: 2025-09-12
# Repo   : HOMELAB :: ZAP-VPS
#────────────────────────────────────────────────────────────
set -Eeuo pipefail

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  📦 VSCODE SERVER POD CONFIGURATION
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ── Basic Container Info
CONTAINER_NAME="vscode-server"
CONTAINER_DESCRIPTION="VS Code Server with OAuth Protection"
CONTAINER_LOGO="https://code.visualstudio.com/assets/images/code-stable.png"
IMAGE_NAME="localhost/code-server:latest"
IMAGE_NEEDS_BUILD=true                  # Build custom image with dev tools
POD_MODE=true                           # Deploy as pod with OAuth proxy
POD_NAME="pod-vscode"

# ── Network & Ports (VS Code and OAuth proxy)
PUBLISHED_PORTS=(
    "8443:8443"                         # VS Code Server port
)
NETWORK_NAME="podman-network"           # Use default bridge network

# ── Custom Image Parameters 
IMAGE_PARAMETERS=" "

# ── Resource Limits (development environment needs more resources)
MEMORY_LIMIT="1536m"                    # 1.5GB RAM for VS Code
MEMORY_SWAP="2048m"                     # Allow 2GB swap for heavy development
CPU_QUOTA="150000"                      # 1.5 CPU cores (150% of one core)
CPU_SHARES="2048"                       # High CPU priority for development
BLKIO_WEIGHT="750"                      # High I/O priority for file operations

# ── Volume Directories (config and workspace storage)
VOLUME_DIRS=(
    "config:/config:Z"                  # VS Code configuration and settings
    "workspace:/config/workspace:Z"     # Development workspace
)

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  🗄️ DATABASE & CACHE SERVICES (OPTIONAL FOR DEVELOPMENT)
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ENABLE_REDIS=false                      # Can enable for development projects
ENABLE_POSTGRESQL=false                 # Can enable for database development
ENABLE_MONGODB=false                    # Can enable for NoSQL development

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  🔧 CUSTOM ADDITIONAL SERVICES (NONE BY DEFAULT)
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EXTRA_CONTAINERS=()                     # No additional containers by default

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  🔐 ENVIRONMENT & AUTHENTICATION
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ── Environment Variables that need user input
ENV_VARS_REQUIRED=(
    "PASSWORD:Enter VS Code access password"
)

# ── Optional Environment Variables (with defaults)
ENV_VARS_OPTIONAL=(
    "TZ:Africa/Tunis"                    # Timezone
    "SUDO_PASSWORD:vscode123"           # Password for sudo in VS Code terminal
)

# ── Google OAuth2 Proxy (ENABLED for secure access)
USE_OAUTH_PROXY=true
OAUTH_EXTERNAL_PORT="4180"              # External OAuth proxy port
OAUTH_INTERNAL_PORT="4180"              # Internal OAuth proxy port  
OAUTH_UPSTREAM_PORT="8443"              # VS Code Server port
OAUTH_ALLOWED_EMAILS_FILE="allowed_emails.txt"          # Allowed emails file


# ── OAuth Resource Limits (lightweight proxy)
OAUTH_MEMORY_LIMIT="128m"               # 128MB for OAuth proxy
OAUTH_MEMORY_SWAP="256m"                # 256MB swap for OAuth proxy
OAUTH_CPU_QUOTA="25000"                 # 0.25 CPU cores for OAuth
OAUTH_CPU_SHARES="512"                  # Lower CPU priority than VS Code
OAUTH_BLKIO_WEIGHT="250"                # Lower I/O priority than VS Code

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ⚙️ CONTAINER OPTIONS & HEALTH CHECKS
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ── Container Options
EXTRA_OPTIONS=(
    "--security-opt=label=disable"      # Disable SELinux labeling
    "--restart=unless-stopped"          # Auto-restart unless manually stopped
)

# ── Health Check (HTTP check for VS Code availability)
HEALTH_CHECK_ENABLED=true
HEALTH_CHECK_CMD="curl -f http://localhost:8443 || exit 1"  # Check VS Code web interface
HEALTH_CHECK_INTERVAL="30s"             # Check every 30 seconds
HEALTH_CHECK_TIMEOUT="10s"              # 10 second timeout
HEALTH_CHECK_RETRIES=3                  # Retry 3 times before marking unhealthy

# ── Custom Containerfile (adds development tools to LinuxServer image)
CONTAINERFILE_CONTENT='
FROM lscr.io/linuxserver/code-server:latest

USER root

# Install development tools and dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv \
        htop git curl wget neofetch \
        build-essential gdb default-jdk \
        shellcheck pandoc \
        texlive-latex-base texlive-fonts-recommended \
        texlive-latex-extra texlive-lang-arabic \
        lmodern fonts-noto && \
    echo "abc ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-abc-nopasswd && \
    chmod 0440 /etc/sudoers.d/90-abc-nopasswd && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create workspace with proper permissions
RUN mkdir -p /config/workspace && \
    chown -R abc:abc /config

USER abc

# Optional: Pre-install popular VS Code extensions
# RUN /app/code-server/bin/code-server --install-extension ms-python.python && \
#     /app/code-server/bin/code-server --install-extension ms-vscode.cpptools && \
#     /app/code-server/bin/code-server --install-extension yzhang.markdown-all-in-one

USER root
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
