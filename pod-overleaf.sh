#!/usr/bin/env bash
#────────────────────────────────────────────────────────────
#  📝 OVERLEAF POD WITH OAUTH PROXY
#────────────────────────────────────────────────────────────
# Author : Mohamed Zarka  
# Version: 2025-09-13
# Repo   : HOMELAB :: ZAP-VPS
#────────────────────────────────────────────────────────────
set -Eeuo pipefail

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  📦 OVERLEAF POD CONFIGURATION
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ── Basic Container Info
CONTAINER_NAME="overleaf"
CONTAINER_DESCRIPTION="Overleaf Collaborative LaTeX Editor with OAuth Protection"
CONTAINER_LOGO="https://images.ctfassets.net/nrgyaltdicpt/4hsPQm87zxC3pU76w964Vg/d4775f5d9cdbbf4b1c3c45a361949b24/overleaf-logo-mono.png"
IMAGE_NAME="sharelatex/sharelatex:latest"
IMAGE_NEEDS_BUILD=false                 # Use official Overleaf image
POD_MODE=true                           # Deploy as pod with OAuth proxy
POD_NAME="pod-overleaf"


# ── Network & Ports (Overleaf and OAuth proxy)
PUBLISHED_PORTS=(
    "8080:80"                           # Overleaf HTTP port
)
NETWORK_NAME="podman-network"           # Custom network for services


# ── Custom Image Parameters 
IMAGE_PARAMETERS=" "                     # Use default entrypoint


# ── Resource Limits (LaTeX compilation needs generous resources)
MEMORY_LIMIT="2048m"                    # 2GB RAM for LaTeX compilation
MEMORY_SWAP="3072m"                     # Allow 3GB swap for heavy documents
CPU_QUOTA="150000"                      # 1.5 CPU cores (150% of one core)
CPU_SHARES="2048"                       # High CPU priority for compilation
BLKIO_WEIGHT="750"                      # High I/O priority for file operations


# ── Volume Directories (data storage)
VOLUME_DIRS=(
    "data:/var/lib/overleaf:Z"          # Overleaf data and compiled documents
)


#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  🗄️ DATABASE & CACHE SERVICES (REQUIRED FOR OVERLEAF)
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ENABLE_REDIS=true                       # Required for Overleaf sessions
ENABLE_POSTGRESQL=false                 # Overleaf uses MongoDB
ENABLE_MONGODB=true                     # Required for Overleaf document storage

# ── Redis Configuration
REDIS_MEMORY="128m"
REDIS_CPU_QUOTA="25000"

# ── MongoDB Configuration  
MONGODB_MEMORY="512m"
MONGODB_CPU_QUOTA="50000"
MONGODB_DB="overleaf"
MONGODB_USER="overleaf"


#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  🔧 CUSTOM ADDITIONAL SERVICES (NONE BY DEFAULT)
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EXTRA_CONTAINERS=()                     # No additional containers by default


#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  🔐 ENVIRONMENT & AUTHENTICATION
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ── Environment Variables that need user input
ENV_VARS_REQUIRED=(
    "OVERLEAF_SITE_URL:Enter the public URL of your Overleaf instance (e.g., https://overleaf.example.com)"
    "OVERLEAF_ADMIN_EMAIL:Enter the email address for the first admin user"
)


# ── Optional Environment Variables (with Overleaf-specific defaults)
ENV_VARS_OPTIONAL=(
    "TZ:Europe/Paris"                                           # Timezone
    "OVERLEAF_APP_NAME:Overleaf LaTeX Editor"                  # Application name
    "ENABLED_LINKED_FILE_TYPES:project_file,project_output_file" # File types
    "ENABLE_CONVERSIONS:true"                                   # Enable file conversions
    "EMAIL_CONFIRMATION_DISABLED:true"                         # Disable email confirmation
    "OVERLEAF_DISABLE_SIGNUPS:true"                           # Admin-only user creation
)


# ── Google OAuth2 Proxy (ENABLED for secure access)
USE_OAUTH_PROXY=true
OAUTH_EXTERNAL_PORT="4185"              # External OAuth proxy port
OAUTH_INTERNAL_PORT="4185"              # Internal OAuth proxy port  
OAUTH_UPSTREAM_PORT="80"                # Overleaf HTTP port
OAUTH_ALLOWED_EMAILS_FILE="allowed_emails.txt"          # Allowed emails file


# ── OAuth Resource Limits (lightweight proxy)
OAUTH_MEMORY_LIMIT="256m"               # 256MB for OAuth proxy
OAUTH_MEMORY_SWAP="512m"                # 512MB swap for OAuth proxy
OAUTH_CPU_QUOTA="25000"                 # 0.25 CPU cores for OAuth
OAUTH_CPU_SHARES="512"                  # Lower CPU priority than Overleaf
OAUTH_BLKIO_WEIGHT="250"                # Lower I/O priority than Overleaf


#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ⚙️ CONTAINER OPTIONS & HEALTH CHECKS
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ── Container Options
EXTRA_OPTIONS=(
    "--security-opt=label=disable"      # Disable SELinux labeling
    "--restart=unless-stopped"          # Auto-restart unless manually stopped
    "--label=homepage.group=Production" # Homepage integration labels
    "--label=homepage.name=Overleaf"
    "--label=homepage.icon=overleaf"
    "--label=homepage.description=Collaborative LaTeX Editor"
)


# ── Health Check (HTTP check for Overleaf availability)
HEALTH_CHECK_ENABLED=true
HEALTH_CHECK_CMD="curl -f http://localhost:80/healthz || exit 1"  # Check Overleaf health endpoint
HEALTH_CHECK_INTERVAL="60s"             # Check every minute
HEALTH_CHECK_TIMEOUT="15s"              # 15 second timeout
HEALTH_CHECK_RETRIES=3                  # Retry 3 times before marking unhealthy


# ── No custom image needed (using official Overleaf image)
CONTAINERFILE_CONTENT=''


#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  📝 OVERLEAF-SPECIFIC MONGODB INITIALIZATION
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ── Override setup_service_env_vars to add Overleaf-specific MongoDB configuration
setup_service_env_vars() {
    info "Setting up Overleaf service credentials..."
    
    # Standard Redis configuration
    if $ENABLE_REDIS; then
        if [[ -z "${REDIS_PASSWORD:-}" ]]; then
            REDIS_PASSWORD=$(generate_password)
        fi
        grep -q "^REDIS_PASSWORD=" "$ENV_FILE" || echo "REDIS_PASSWORD=${REDIS_PASSWORD}" >> "$ENV_FILE"
        REDIS_URL="redis://:${REDIS_PASSWORD}@localhost:6379"
        grep -q "^REDIS_URL=" "$ENV_FILE" || echo "REDIS_URL=${REDIS_URL}" >> "$ENV_FILE"
        
        # Overleaf Redis configuration
        grep -q "^OVERLEAF_REDIS_HOST=" "$ENV_FILE" || echo "OVERLEAF_REDIS_HOST=localhost" >> "$ENV_FILE"
        grep -q "^OVERLEAF_REDIS_PORT=" "$ENV_FILE" || echo "OVERLEAF_REDIS_PORT=6379" >> "$ENV_FILE"
        grep -q "^OVERLEAF_REDIS_PASSWORD=" "$ENV_FILE" || echo "OVERLEAF_REDIS_PASSWORD=${REDIS_PASSWORD}" >> "$ENV_FILE"
    fi
    
    # MongoDB configuration for Overleaf
    if $ENABLE_MONGODB; then
        if [[ -z "${MONGODB_PASSWORD:-}" ]]; then
            MONGODB_PASSWORD=$(generate_password)
        fi
        grep -q "^MONGO_INITDB_ROOT_USERNAME=" "$ENV_FILE" || echo "MONGO_INITDB_ROOT_USERNAME=${MONGODB_USER:-overleaf}" >> "$ENV_FILE"
        grep -q "^MONGO_INITDB_ROOT_PASSWORD=" "$ENV_FILE" || echo "MONGO_INITDB_ROOT_PASSWORD=${MONGODB_PASSWORD}" >> "$ENV_FILE"
        grep -q "^MONGO_INITDB_DATABASE=" "$ENV_FILE" || echo "MONGO_INITDB_DATABASE=${MONGODB_DB:-overleaf}" >> "$ENV_FILE"
        
        # ✅ CRITICAL: Add the OVERLEAF_MONGO_URL that the application actually uses
        OVERLEAF_MONGO_URL="mongodb://localhost:27017/${MONGODB_DB:-overleaf}?replicaSet=overleaf"
        grep -q "^OVERLEAF_MONGO_URL=" "$ENV_FILE" || echo "OVERLEAF_MONGO_URL=${OVERLEAF_MONGO_URL}" >> "$ENV_FILE"
        
        # Generic MongoDB URL for template compatibility
        MONGODB_URL="$OVERLEAF_MONGO_URL"
        grep -q "^MONGODB_URL=" "$ENV_FILE" || echo "MONGODB_URL=${MONGODB_URL}" >> "$ENV_FILE"
    fi
    
    # Create MongoDB initialization scripts
    create_mongo_replica_set_script
}

# ── Initialize MongoDB Replica Set for Overleaf
initialize_mongo_replica_set() {
    info "Initializing MongoDB replica set for Overleaf..."
    
    # Wait for MongoDB to be ready
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if podman exec "${CONTAINER_NAME}-mongodb" mongosh --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
            break
        fi
        info "Waiting for MongoDB to be ready... (attempt $attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        error "MongoDB failed to start within expected time"
    fi
    
    # Initialize replica set
    podman exec "${CONTAINER_NAME}-mongodb" mongosh --eval "
    try {
        rs.status();
        print('✅ Replica set already exists');
    } catch (e) {
        print('🔧 Initializing replica set for Overleaf...');
        rs.initiate({ 
            _id: 'overleaf', 
            members: [{ _id: 0, host: '127.0.0.1:27017' }] 
        });
        print('✅ Replica set initialized successfully');
    }
    " 2>/dev/null || warn "Replica set initialization may have failed"
    
    okay "MongoDB replica set ready for Overleaf"
}

# ── Create MongoDB replica set initialization for Overleaf
create_mongo_replica_set_script() {
    local mongo_init_dir="${DATA_ROOT}/mongodb-init"
    mkdir -p "$mongo_init_dir"
    
    # MongoDB replica set initialization script
    cat > "${mongo_init_dir}/mongo-init.js" <<'EOC'
try {
  rs.status();
  console.log("Replica set already exists, skipping initialization.");
} catch (e) {
  console.log("Initializing new replica set for Overleaf...");
  rs.initiate({ 
    _id: "overleaf", 
    members: [{ _id: 0, host: "127.0.0.1:27017" }] 
  });
}
EOC

    # MongoDB health check script
    cat > "${mongo_init_dir}/healthcheck.js" <<'EOC'
const result = db.adminCommand({ ping: 1 });
if (result.ok === 1) {
  quit(0); // Success
} else {
  quit(1); // Failure  
}
EOC

    chown -R "${MGRSYS_UID}:${MGRSYS_GID}" "$mongo_init_dir"
    info "MongoDB replica set scripts created"
}

# ── Override deploy_service_containers to add MongoDB replica set initialization
deploy_service_containers() {
    # Deploy Redis for Overleaf sessions
    if $ENABLE_REDIS; then
        info "Deploying Redis for Overleaf sessions..."
        systemctl --user stop "container-${CONTAINER_NAME}-redis.service" 2>/dev/null || true
        podman rm -f "${CONTAINER_NAME}-redis" 2>/dev/null || true

        podman run -d \
            --name "${CONTAINER_NAME}-redis" \
            $(if ${POD_MODE:-false}; then echo "--pod $POD_NAME"; else echo "--publish 6379:6379"; fi) \
            $(if [[ ${POD_MODE:-false} == false && -n "${NETWORK_NAME:-}" ]]; then echo "--network" "$NETWORK_NAME"; fi) \
            --restart unless-stopped \
            --memory "${REDIS_MEMORY:-128m}" \
            --cpu-period 100000 \
            --cpu-quota "${REDIS_CPU_QUOTA:-25000}" \
            --volume "${DATA_ROOT}/redis-data:/data:Z" \
            --env "REDIS_PASSWORD=${REDIS_PASSWORD}" \
            --health-cmd "redis-cli --no-auth-warning -a \$REDIS_PASSWORD ping" \
            --health-interval 30s \
            --health-timeout 10s \
            --health-retries 3 \
            redis:alpine redis-server --requirepass "$REDIS_PASSWORD" --save 60 1 --loglevel warning
        
        okay "Redis deployed for Overleaf"
    fi
    
    # Deploy MongoDB with Overleaf replica set
    if $ENABLE_MONGODB; then
        info "Deploying MongoDB with Overleaf replica set..."
        systemctl --user stop "container-${CONTAINER_NAME}-mongodb.service" 2>/dev/null || true
        podman rm -f "${CONTAINER_NAME}-mongodb" 2>/dev/null || true
        
        podman run -d \
            --name "${CONTAINER_NAME}-mongodb" \
            $(if ${POD_MODE:-false}; then echo "--pod $POD_NAME"; else echo "--publish 27017:27017"; fi) \
            $(if [[ ${POD_MODE:-false} == false && -n "${NETWORK_NAME:-}" ]]; then echo "--network" "$NETWORK_NAME"; fi) \
            --restart unless-stopped \
            --memory "${MONGODB_MEMORY:-512m}" \
            --cpu-period 100000 \
            --cpu-quota "${MONGODB_CPU_QUOTA:-50000}" \
            --volume "${DATA_ROOT}/mongodb-data:/data/db:Z" \
            --volume "${DATA_ROOT}/mongodb-init/mongo-init.js:/docker-entrypoint-initdb.d/init.js:ro,Z" \
            --volume "${DATA_ROOT}/mongodb-init/healthcheck.js:/healthcheck.js:ro,Z" \
            --env "MONGO_INITDB_ROOT_USERNAME=${MONGODB_USER:-overleaf}" \
            --env "MONGO_INITDB_ROOT_PASSWORD=${MONGODB_PASSWORD}" \
            --env "MONGO_INITDB_DATABASE=${MONGODB_DB:-overleaf}" \
            --health-cmd "mongosh --norc --quiet --file /healthcheck.js" \
            --health-interval 30s \
            --health-timeout 10s \
            --health-retries 3 \
            mongo:6.0 --replSet overleaf
        
        okay "MongoDB with replica set deployed for Overleaf"
        
        # ✅ CRITICAL: Initialize the replica set after MongoDB starts
        initialize_mongo_replica_set
    fi
}


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
