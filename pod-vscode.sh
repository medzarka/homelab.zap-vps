#!/bin/bash
#────────────────────────────────────────────────────────────
#  🎛️ SIMPLE VSCODE POD WITH CUSTOM IMAGE + OAUTH (ALL-IN-ONE)
#────────────────────────────────────────────────────────────
# Builds custom image and deploys pod with VSCode + OAuth
# Includes your custom Dockerfile with fonts, SSH, and development tools
#────────────────────────────────────────────────────────────

set -e

echo "🎛️ Starting VSCode pod deployment with custom image..."

# Configuration
NETWORK_NAME="zap-vps-podman-network"
POD_NAME="pod-vscode"
CUSTOM_IMAGE="localhost/vscode-custom:latest"
HOST_UID=1000
HOST_GID=1000

# Your custom Dockerfile content
CONTAINERFILE_CONTENT='
FROM lscr.io/linuxserver/code-server:latest

USER root

# Install development tools, dependencies, and available fonts
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv \
        htop git curl wget neofetch unzip zip \
        build-essential gdb default-jdk \
        shellcheck openssh-client make \
        pandoc \
        texlive-latex-base texlive-fonts-recommended \
        texlive-latex-extra texlive-lang-arabic \
        texlive-fonts-recommended texlive-fonts-extra texlive-xetex \
        lmodern fonts-noto fonts-firacode && \
    echo "abc ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-abc-nopasswd && \
    chmod 440 /etc/sudoers.d/90-abc-nopasswd && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Manually install Source Code Pro fonts
RUN mkdir -p /usr/local/share/fonts/source-code-pro && \
    curl -L "https://github.com/adobe-fonts/source-code-pro/releases/download/2.042R-u%2F1.062R-i%2F1.026R-vf/TTF-source-code-pro-2.042R-u_1.062R-i.zip" -o /tmp/source-code-pro.zip && \
    unzip /tmp/source-code-pro.zip -d /tmp/source-code-pro && \
    cp /tmp/source-code-pro/TTF/*.ttf /usr/local/share/fonts/source-code-pro/ && \
    rm -rf /tmp/source-code-pro*

# Manually install Fira Mono fonts
RUN mkdir -p /usr/local/share/fonts/fira-mono && \
    curl -L "https://github.com/mozilla/Fira/archive/4.202.zip" -o /tmp/fira.zip && \
    unzip /tmp/fira.zip -d /tmp/fira && \
    cp /tmp/fira/Fira-4.202/ttf/FiraMono*.ttf /usr/local/share/fonts/fira-mono/ && \
    rm -rf /tmp/fira*

# Update font cache
RUN fc-cache -f -v

# Generate SSH key pair for abc user (using /config as home directory)
RUN mkdir -p /config/.ssh && \
    if [ ! -f /config/.ssh/id_ed25519 ]; then \
        ssh-keygen -t ed25519 -N "" -f /config/.ssh/id_ed25519; \
    fi && \
    chmod 700 /config/.ssh && \
    chmod 600 /config/.ssh/id_ed25519* && \
    chown -R abc:abc /config

# Create workspace with proper permissions
RUN mkdir -p /config/workspace && \
    chown -R abc:abc /config

# Create init script for VSCode extensions
RUN cat > /init-dev-env.sh << "EOF"
#!/bin/bash
echo "🚀 Initializing VSCode development environment..."

# VSCode Extensions to install/update
EXTENSIONS=(
    ms-python.python
    ms-toolsai.jupyter
    redhat.java
    vscjava.vscode-java-pack
    ms-vscode.cpptools
    ms-vscode.cmake-tools
    James-Yu.latex-workshop
    yzhang.markdown-all-in-one
    ms-vscode.vscode-json
    esbenp.prettier-vscode
    bradlc.vscode-tailwindcss
)

# Install extensions (they will persist in mounted /config)
echo "📦 Installing/updating VSCode extensions..."
for ext in "${EXTENSIONS[@]}"; do
    if ! code-server --list-extensions | grep -q "^$ext\$"; then
        echo "  Installing: $ext"
        code-server --install-extension "$ext" || echo "  Failed to install: $ext"
    else
        echo "  Already installed: $ext"
    fi
    sleep 1
done

echo "✅ Extensions installation completed!"
echo "🎉 VSCode development environment ready!"
EOF

RUN chmod +x /init-dev-env.sh
'

# Check if network exists
if ! podman network exists "$NETWORK_NAME" 2>/dev/null; then
    echo "❌ Error: Network '$NETWORK_NAME' does not exist."
    echo "Please run the Cloudflare script first to create the network."
    exit 1
fi

echo "✅ Network '$NETWORK_NAME' found"

# Handle VSCode password secret
if ! podman secret exists vscode_password; then
    echo "🔑 VSCode password secret not found"
    echo "This will be the password to access your VSCode web interface"
    echo ""
    read -rsp "Enter your VSCode password: " VSCODE_PASSWORD
    echo
    
    if [[ -z "$VSCODE_PASSWORD" ]]; then
        echo "❌ Password cannot be empty!"
        exit 1
    fi
    
    echo "$VSCODE_PASSWORD" | podman secret create vscode_password -
    echo "✅ VSCode password saved securely as Podman secret"
else
    echo "✅ Using existing VSCode password secret"
fi

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

# Build custom image
echo "🔨 Building custom VSCode image..."
mkdir -p ~/podman_data/vscode/custom
echo "$CONTAINERFILE_CONTENT" > ~/podman_data/vscode/custom/Containerfile

echo "Building image: $CUSTOM_IMAGE"
podman build -t "$CUSTOM_IMAGE" ~/podman_data/vscode/custom/

echo "✅ Custom image built successfully!"

# Create directories for persistent storage
mkdir -p ~/podman_data/vscode/{config,workspace}
sudo chown -R mgrsys:mgrsys ~/podman_data/vscode

# Clean up existing pod
echo "🧹 Cleaning up existing deployment..."
systemctl --user stop "pod-$POD_NAME.service" 2>/dev/null || true
podman pod stop "$POD_NAME" 2>/dev/null || true
podman pod rm -f "$POD_NAME" 2>/dev/null || true

# Create the pod
echo "🎛️ Creating VSCode development pod..."
podman pod create \
    --name "$POD_NAME" \
    --network "$NETWORK_NAME" \
    --publish 4180:4180 \
    --label homepage.group="Development" \
    --label homepage.name="VSCode Dev Pod" \
    --label homepage.icon="vscode" \
    --label homepage.href="http://vscode-dev.local:4180" \
    --label homepage.description="Custom VSCode development environment"

# Deploy VSCode container with custom image
echo "💻 Deploying custom VSCode container..."
podman run -d \
    --pod "$POD_NAME" \
    --name vscode \
    --memory 3072m \
    --cpu-shares 3072 \
    --cpus 2.5 \
    --env PUID=$HOST_UID \
    --env PGID=$HOST_GID \
    --env TZ=Africa/Tunis \
    --env LANG=en_US.UTF-8 \
    --env LC_ALL=en_US.UTF-8 \
    --env PASSWORD=$(podman run --rm --secret vscode_password alpine cat "/run/secrets/vscode_password") \
    --env SUDO_PASSWORD=$(podman run --rm --secret vscode_password alpine cat "/run/secrets/vscode_password") \
    --env DEFAULT_WORKSPACE=/config/workspace \
    --volume ~/podman_data/vscode/config:/config:Z \
    --volume ~/podman_data/vscode/workspace:/config/workspace:Z \
    "$CUSTOM_IMAGE"

# Deploy OAuth2-Proxy container
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
sleep 20
podman exec vscode /init-dev-env.sh

# Get assigned IP
ASSIGNED_IP=$(podman pod inspect "$POD_NAME" --format '{{.InfraContainerID}}' | xargs podman inspect --format '{{.NetworkSettings.Networks.'"$NETWORK_NAME"'.IPAddress}}' 2>/dev/null || echo "IP not assigned yet")

# Generate systemd service
echo "⚙️ Creating systemd service..."
mkdir -p ~/.config/systemd/user
podman generate systemd --new --name "$POD_NAME" --files
mv "pod-$POD_NAME.service" ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable "pod-$POD_NAME.service"

echo ""
echo "🎉 VSCode development pod deployed successfully!"
echo ""
echo "🏗️ Custom Image Features:"
echo "   💻 LinuxServer code-server base"
echo "   🐍 Python 3 + development tools"
echo "   ☕ Java JDK + build tools"
echo "   🔨 C/C++ development (build-essential, gdb)"
echo "   📄 LaTeX + pandoc for document generation"
echo "   🔤 Premium fonts (Source Code Pro, Fira Mono, Noto)"
echo "   🔐 SSH key generation for abc user"
echo "   🛡️ Sudo access configured"
echo ""
echo "🎛️ Pod Configuration:"
echo "   Network: $NETWORK_NAME"
echo "   Assigned IP: $ASSIGNED_IP"
echo "   VSCode Port: 8443"
echo "   OAuth Port: 4180"
echo ""
echo "💾 Resource Allocation:"
echo "   VSCode: 3GB RAM, 2.5 CPU cores (enhanced for development)"
echo "   OAuth: 128MB RAM, 0.5 CPU cores (lightweight proxy)"
echo ""
echo "🌐 Access Points:"
echo "   OAuth Protected: http://$ASSIGNED_IP:4180 (Google login required)"
echo "   Direct VSCode: http://$ASSIGNED_IP:8443 (password required)"
echo "   Via Tailscale: Access from any Tailscale device"
echo ""
echo "📁 Persistent Storage:"
echo "  Config: ~/podman_data/vscode/config (VSCode settings & extensions)"
echo "  Workspace: ~/podman_data/vscode/workspace (your projects)"
echo "  SSH Keys: Available in /config/.ssh/ (ed25519 key pair)"
echo ""
echo "🔧 Management Commands:"
echo "  Start Pod:    systemctl --user start pod-$POD_NAME.service"
echo "  Stop Pod:     systemctl --user stop pod-$POD_NAME.service"
echo "  Status:       systemctl --user status pod-$POD_NAME.service"
echo "  VSCode Logs:  podman logs vscode"
echo "  OAuth Logs:   podman logs google-oauth"
echo "  Init Dev Env: podman exec vscode /config/init-dev-env.sh"
echo ""
echo "🔑 Secret Management:"
echo "  VSCode Password: podman secret inspect vscode_password"
echo "  OAuth Client ID: podman secret inspect google_oauth_client_id"
echo "  OAuth Secret: podman secret inspect google_oauth_client_secret"
echo ""
echo "🌟 Your custom development environment is ready!"
echo "🚀 Access via Google OAuth at: http://$ASSIGNED_IP:4180"
