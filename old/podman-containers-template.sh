#!/usr/bin/env bash
#────────────────────────────────────────────────────────────
#  🐳 UNIVERSAL PODMAN CONTAINER TEMPLATE - CORE FUNCTIONS
#────────────────────────────────────────────────────────────
# Author : Mohamed Zarka
# Version: 2025-09-12
# Repo   : HOMELAB :: ZAP-VPS
#────────────────────────────────────────────────────────────
#  ⚠️  DO NOT RUN THIS SCRIPT DIRECTLY
#  This script contains only the core functions.
#  Use individual container scripts that source this template.
#────────────────────────────────────────────────────────────
set -Eeuo pipefail

# Check if script is being sourced (not executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a template script. Use individual container scripts instead."
    echo "📁 Available scripts: container-*.sh, pod-*.sh"
    exit 1
fi

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  🔧 CORE CONSTANTS AND VALIDATION
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ── System Constants
MGRSYS_UID=1000
MGRSYS_GID=1000
MGRSYS_USER="mgrsys"

# ── Global Variables (initialized in initialize_paths)
DATA_ROOT=""
CONFIG_DIR=""
DATA_DIR=""
ENV_FILE=""
OAUTH_EMAILS_FILE=""
REDIS_URL=""
POSTGRESQL_URL=""
MONGODB_URL=""

# ── Validate Required Variables from Container Scripts
validate_configuration() {
    local required_vars=(
        "CONTAINER_NAME" "CONTAINER_DESCRIPTION" "IMAGE_NAME" "IMAGE_NEEDS_BUILD"
        "MEMORY_LIMIT" "CPU_QUOTA" "CPU_SHARES" "BLKIO_WEIGHT" "CONTAINER_LOGO"
        "ENABLE_REDIS" "ENABLE_POSTGRESQL" "ENABLE_MONGODB" "USE_OAUTH_PROXY"
        "HEALTH_CHECK_ENABLED" "IMAGE_PARAMETERS"
    )
    
    info "🔍 Validating configuration variables..."
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required variable '$var' is not set in container script"
        fi
    done
    
    # Validate arrays exist (even if empty)
    declare -p PUBLISHED_PORTS VOLUME_DIRS EXTRA_CONTAINERS ENV_VARS_REQUIRED ENV_VARS_OPTIONAL EXTRA_OPTIONS >/dev/null 2>&1 || {
        error "One or more required arrays are not properly declared"
    }
    
    okay "Configuration validation passed"
}

# ── Initialize Paths
initialize_paths() {
    DATA_ROOT="${HOME}/podman_data/${CONTAINER_NAME}"
    CONFIG_DIR="${DATA_ROOT}/config"
    DATA_DIR="${DATA_ROOT}/data"
    ENV_FILE="${DATA_ROOT}/.env"
    OAUTH_EMAILS_FILE="${DATA_ROOT}/${OAUTH_ALLOWED_EMAILS_FILE:-allowed_emails.txt}"
    
    # Service Connection Strings (auto-generated)
    REDIS_URL=""
    POSTGRESQL_URL=""
    MONGODB_URL=""
}

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  🎨 LOGGING FUNCTIONS
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
info()  { echo -e "\e[34m[ℹ️]\e[0m $*"; }
okay()  { echo -e "\e[32m[✅]\e[0m $*"; }
warn()  { echo -e "\e[33m[⚠️]\e[0m $*"; }
error() { echo -e "\e[31m[❌]\e[0m $*"; exit 1; }

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  🔧 UTILITY FUNCTIONS
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ── Generate Random Password
generate_password() {
    openssl rand -base64 12 | tr -d "=+/" | cut -c1-16
}

# ── System Resource Check
check_system_resources() {
    local available_mem=$(free -m | awk '/^Mem:/{print $7}')
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    local mem_usage=$((($total_mem - $available_mem) * 100 / $total_mem))
    
    info "System memory usage: ${mem_usage}%"
    
    # Calculate total memory requirements
    local required_mem=0
    [[ "$MEMORY_LIMIT" =~ ([0-9]+) ]] && required_mem=$((required_mem + ${BASH_REMATCH[1]}))
    $ENABLE_REDIS && [[ "${REDIS_MEMORY:-64m}" =~ ([0-9]+) ]] && required_mem=$((required_mem + ${BASH_REMATCH[1]}))
    $ENABLE_POSTGRESQL && [[ "${POSTGRESQL_MEMORY:-256m}" =~ ([0-9]+) ]] && required_mem=$((required_mem + ${BASH_REMATCH[1]}))
    $ENABLE_MONGODB && [[ "${MONGODB_MEMORY:-512m}" =~ ([0-9]+) ]] && required_mem=$((required_mem + ${BASH_REMATCH[1]}))
    $USE_OAUTH_PROXY && [[ "${OAUTH_MEMORY_LIMIT:-128m}" =~ ([0-9]+) ]] && required_mem=$((required_mem + ${BASH_REMATCH[1]}))
    
    info "Estimated memory requirement: ${required_mem}MB"
    
    if [[ $mem_usage -gt 85 ]] || [[ $required_mem -gt $available_mem ]]; then
        warn "High memory usage or insufficient memory for deployment!"
        warn "Available: ${available_mem}MB, Required: ${required_mem}MB"
    fi
}

# ── Validate mgrsys User
validate_mgrsys_user() {
    info "Validating mgrsys user configuration..."
    
    if ! id "$MGRSYS_USER" &>/dev/null; then
        error "User '$MGRSYS_USER' does not exist. Please create it first:"
        error "  sudo useradd -u $MGRSYS_UID -g $MGRSYS_GID -m $MGRSYS_USER"
    fi
    
    local actual_uid=$(id -u "$MGRSYS_USER")
    local actual_gid=$(id -g "$MGRSYS_USER")
    
    if [[ "$actual_uid" != "$MGRSYS_UID" ]] || [[ "$actual_gid" != "$MGRSYS_GID" ]]; then
        error "User '$MGRSYS_USER' has UID:GID ${actual_uid}:${actual_gid}, expected ${MGRSYS_UID}:${MGRSYS_GID}"
    fi
    
    okay "User '$MGRSYS_USER' validated (${MGRSYS_UID}:${MGRSYS_GID})"
}

# ── Directory Setup with Permission Management
ensure_directories() {
    info "Setting up directory structure for ${CONTAINER_NAME}..."
    
    # Create base directories
    mkdir -p "$DATA_ROOT" "$CONFIG_DIR" "$DATA_DIR"
    
    # Create service-specific directories
    $ENABLE_REDIS && mkdir -p "${DATA_ROOT}/redis-data"
    $ENABLE_POSTGRESQL && mkdir -p "${DATA_ROOT}/postgresql-data"
    $ENABLE_MONGODB && mkdir -p "${DATA_ROOT}/mongodb-data"
    
    # Process volume directories
    local created_dirs=()
    for volume in "${VOLUME_DIRS[@]}"; do
        local host_path=$(echo "$volume" | cut -d':' -f1)
        
        if [[ ! "$host_path" =~ ^/ ]]; then
            host_path="${DATA_ROOT}/${host_path}"
        fi
        
        if [[ ! -d "$host_path" ]]; then
            mkdir -p "$host_path"
            created_dirs+=("$host_path")
            info "Created directory: ${host_path}"
        fi
    done
    
    # Process extra container volumes
    for container_spec in "${EXTRA_CONTAINERS[@]}"; do
        if [[ -n "$container_spec" ]]; then
            IFS=':' read -r name image tag port memory cpu envs volumes health <<< "$container_spec"
            if [[ "$volumes" != "none" ]]; then
                IFS=',' read -ra VOLUME_LIST <<< "$volumes"
                for vol in "${VOLUME_LIST[@]}"; do
                    local vol_host_path=$(echo "$vol" | cut -d':' -f1)
                    vol_host_path="${DATA_ROOT}/${vol_host_path}"
                    mkdir -p "$vol_host_path"
                    info "Created extra container directory: ${vol_host_path}"
                done
            fi
        fi
    done
    
    # Fix ownership and permissions
    sudo chown -R "${MGRSYS_UID}:${MGRSYS_GID}" "$DATA_ROOT"
    sudo find "$DATA_ROOT" -type d -exec chmod 755 {} \;
    sudo find "$DATA_ROOT" -type f -exec chmod 644 {} \; 2>/dev/null || true
    
    okay "Directory structure ready with proper permissions"
}

# ── Setup Service Environment Variables
setup_service_env_vars() {
    info "Setting up service credentials..."
    
    # Redis configuration
    if $ENABLE_REDIS; then
        if [[ -z "${REDIS_PASSWORD:-}" ]]; then
            REDIS_PASSWORD=$(generate_password)
        fi
        grep -q "^REDIS_PASSWORD=" "$ENV_FILE" || echo "REDIS_PASSWORD=${REDIS_PASSWORD}" >> "$ENV_FILE"
        REDIS_URL="redis://:${REDIS_PASSWORD}@localhost:6379"
        grep -q "^REDIS_URL=" "$ENV_FILE" || echo "REDIS_URL=${REDIS_URL}" >> "$ENV_FILE"
    fi
    
    # PostgreSQL configuration
    if $ENABLE_POSTGRESQL; then
        if [[ -z "${POSTGRESQL_PASSWORD:-}" ]]; then
            POSTGRESQL_PASSWORD=$(generate_password)
        fi
        grep -q "^POSTGRES_DB=" "$ENV_FILE" || echo "POSTGRES_DB=${POSTGRESQL_DB:-appdb}" >> "$ENV_FILE"
        grep -q "^POSTGRES_USER=" "$ENV_FILE" || echo "POSTGRES_USER=${POSTGRESQL_USER:-appuser}" >> "$ENV_FILE"
        grep -q "^POSTGRES_PASSWORD=" "$ENV_FILE" || echo "POSTGRES_PASSWORD=${POSTGRESQL_PASSWORD}" >> "$ENV_FILE"
        POSTGRESQL_URL="postgresql://${POSTGRESQL_USER:-appuser}:${POSTGRESQL_PASSWORD}@localhost:5432/${POSTGRESQL_DB:-appdb}"
        grep -q "^DATABASE_URL=" "$ENV_FILE" || echo "DATABASE_URL=${POSTGRESQL_URL}" >> "$ENV_FILE"
    fi
    
    # MongoDB configuration
    if $ENABLE_MONGODB; then
        if [[ -z "${MONGODB_PASSWORD:-}" ]]; then
            MONGODB_PASSWORD=$(generate_password)
        fi
        grep -q "^MONGO_INITDB_ROOT_USERNAME=" "$ENV_FILE" || echo "MONGO_INITDB_ROOT_USERNAME=${MONGODB_USER:-appuser}" >> "$ENV_FILE"
        grep -q "^MONGO_INITDB_ROOT_PASSWORD=" "$ENV_FILE" || echo "MONGO_INITDB_ROOT_PASSWORD=${MONGODB_PASSWORD}" >> "$ENV_FILE"
        MONGODB_URL="mongodb://${MONGODB_USER:-appuser}:${MONGODB_PASSWORD}@localhost:27017/${MONGODB_DB:-appdb}"
        grep -q "^MONGODB_URL=" "$ENV_FILE" || echo "MONGODB_URL=${MONGODB_URL}" >> "$ENV_FILE"
    fi
}

# ── Interactive Environment Setup
setup_env_file() {
    info "Setting up environment file..."
    
    touch "$ENV_FILE"
    
    # Always set user mapping variables
    grep -q "^PUID=" "$ENV_FILE" || echo "PUID=${MGRSYS_UID}" >> "$ENV_FILE"
    grep -q "^PGID=" "$ENV_FILE" || echo "PGID=${MGRSYS_GID}" >> "$ENV_FILE"
    
    # Handle required environment variables
    for env_var in "${ENV_VARS_REQUIRED[@]}"; do
        local var_name=$(echo "$env_var" | cut -d':' -f1)
        local var_prompt=$(echo "$env_var" | cut -d':' -f2-)
        
        if ! grep -q "^${var_name}=" "$ENV_FILE"; then
            echo ""
            read -p "🔐 ${var_prompt}: " -s var_value
            echo ""
            if [[ -z "$var_value" ]]; then
                error "Value cannot be empty for ${var_name}"
            fi
            echo "${var_name}=${var_value}" >> "$ENV_FILE"
            okay "Set ${var_name}"
        fi
    done
    
    # Handle optional environment variables
    for env_var in "${ENV_VARS_OPTIONAL[@]}"; do
        local var_name=$(echo "$env_var" | cut -d':' -f1)
        local var_default=$(echo "$env_var" | cut -d':' -f2-)
        
        if ! grep -q "^${var_name}=" "$ENV_FILE"; then
            echo "${var_name}=${var_default}" >> "$ENV_FILE"
        fi
    done
    
    # Setup service credentials
    setup_service_env_vars
    
    # Handle extra container environment variables
    for container_spec in "${EXTRA_CONTAINERS[@]}"; do
        if [[ -n "$container_spec" ]]; then
            IFS=':' read -r name image tag port memory cpu envs volumes health <<< "$container_spec"
            if [[ "$envs" != "none" ]]; then
                IFS=',' read -ra ENV_LIST <<< "$envs"
                for env_var in "${ENV_LIST[@]}"; do
                    if ! grep -q "^${env_var}=" "$ENV_FILE"; then
                        echo ""
                        read -p "🔐 Enter ${env_var} for ${name}: " -s var_value
                        echo ""
                        echo "${env_var}=${var_value}" >> "$ENV_FILE"
                        okay "Set ${env_var}"
                    fi
                done
            fi
        fi
    done
    
    # Handle OAuth environment variables if enabled
    if $USE_OAUTH_PROXY; then
        setup_oauth_env
    fi
    
    okay "Environment file configured"
}

# ── OAuth Environment Setup
setup_oauth_env() {
    info "Setting up OAuth2 environment variables..."
    
    local oauth_vars=(
        "OAUTH_CLIENT_ID:Enter Google OAuth Client ID"
        "OAUTH_CLIENT_SECRET:Enter Google OAuth Client Secret"
    )
    
    for env_var in "${oauth_vars[@]}"; do
        local var_name=$(echo "$env_var" | cut -d':' -f1)
        local var_prompt=$(echo "$env_var" | cut -d':' -f2-)
        
        if ! grep -q "^${var_name}=" "$ENV_FILE"; then
            echo ""
            read -p "🔐 ${var_prompt}: " -s var_value
            echo ""
            if [[ -z "$var_value" ]]; then
                error "OAuth enabled but ${var_name} cannot be empty"
            fi
            echo "${var_name}=${var_value}" >> "$ENV_FILE"
            okay "Set ${var_name}"
        fi
    done
    
    # Generate cookie secret if not exists
    if ! grep -q "^OAUTH_COOKIE_SECRET=" "$ENV_FILE"; then
        local cookie_secret=$(openssl rand -hex 16)
        echo "OAUTH_COOKIE_SECRET=${cookie_secret}" >> "$ENV_FILE"
        okay "Generated OAuth cookie secret"
    fi
    
    # Create allowed emails file
    setup_oauth_emails_file
}

# ── OAuth Emails File Setup
setup_oauth_emails_file() {
    if [[ ! -f "$OAUTH_EMAILS_FILE" ]]; then
        cat > "$OAUTH_EMAILS_FILE" <<EOF
# Allowed email addresses for OAuth authentication
# Add one email per line, comments start with #
#
# Examples:
# admin@yourdomain.com
# user@company.org
#
# Add your emails below:

EOF
        warn "Created ${OAUTH_EMAILS_FILE}"
        warn "Please add allowed email addresses to this file before accessing the service"
    fi
    
    # Fix permissions
    chown "${MGRSYS_UID}:${MGRSYS_GID}" "$OAUTH_EMAILS_FILE"
    chmod 644 "$OAUTH_EMAILS_FILE"
}

# ── Load Environment
load_environment() {
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        source "$ENV_FILE"
        set +a
        info "Environment variables loaded"
    else
        error "Environment file not found: ${ENV_FILE}"
    fi
}

# ── Build Custom Image
build_image() {
    if ! $IMAGE_NEEDS_BUILD; then
        return 0
    fi
    
    info "Building custom image for ${CONTAINER_NAME}..."
    
    if [[ -z "${CONTAINERFILE_CONTENT:-}" ]]; then
        error "IMAGE_NEEDS_BUILD=true but CONTAINERFILE_CONTENT is empty"
    fi
    
    local custom_image="${CONTAINER_NAME}:latest"
    echo "$CONTAINERFILE_CONTENT" | podman build -t "$custom_image" -
    
    # Update IMAGE_NAME to use custom built image
    IMAGE_NAME="$custom_image"
    
    okay "Custom image built: ${custom_image}"
}

# ── Network Management
setup_network() {
    if [[ -z "${NETWORK_NAME:-}" ]]; then
        return 0
    fi
    
    info "Setting up network: ${NETWORK_NAME}..."
    
    if ! podman network exists "$NETWORK_NAME"; then
        podman network create "$NETWORK_NAME"
        okay "Network created: ${NETWORK_NAME}"
    else
        info "Network already exists: ${NETWORK_NAME}"
    fi
}

# ── Pod Management
setup_pod() {
    if ! ${POD_MODE:-false}; then
        return 0
    fi
    
    info "Setting up pod: ${POD_NAME}..."
    
    # Remove existing pod
    systemctl --user stop "pod-${POD_NAME}.service" 2>/dev/null || true
    podman pod exists "$POD_NAME" && podman pod rm -f "$POD_NAME"
    
    # Build port mapping arguments - UPDATED LOGIC
    local port_args=()
    
    # Add network if specified
    if [[ -n "${NETWORK_NAME:-}" ]]; then
        port_args+=("--network" "$NETWORK_NAME")
    fi
    
    # Conditional port publishing based on OAuth usage
    if $USE_OAUTH_PROXY; then
        # Only publish OAuth port when OAuth is enabled
        port_args+=("--publish" "${OAUTH_EXTERNAL_PORT:-8080}:${OAUTH_INTERNAL_PORT:-8080}")
    else
        # Only publish main application ports when OAuth is disabled
        for port in "${PUBLISHED_PORTS[@]}"; do
            port_args+=("--publish" "$port")
        done
        
        # Add service ports
        $ENABLE_REDIS && port_args+=("--publish" "6379:6379")
        $ENABLE_POSTGRESQL && port_args+=("--publish" "5432:5432")
        $ENABLE_MONGODB && port_args+=("--publish" "27017:27017")
        
        # Add extra container ports
        for container_spec in "${EXTRA_CONTAINERS[@]}"; do
            if [[ -n "$container_spec" ]]; then
                IFS=':' read -r name image tag port memory cpu envs volumes health <<< "$container_spec"
                if [[ "$port" != "0" ]]; then
                    port_args+=("--publish" "${port}:${port}")
                fi
            fi
        done
    fi
    
    # Create new pod
    podman pod create \
        --name "$POD_NAME" \
        "${port_args[@]}"
    
    okay "Pod ready: ${POD_NAME}"
}


# ── Deploy Service Containers
deploy_service_containers() {
    # Deploy Redis
    if $ENABLE_REDIS; then
        info "Deploying Redis..."
        systemctl --user stop "container-${CONTAINER_NAME}-redis.service" 2>/dev/null || true
        podman rm -f "${CONTAINER_NAME}-redis" 2>/dev/null || true

        podman run -d \
            --name "${CONTAINER_NAME}-redis" \
            $(if ${POD_MODE:-false}; then echo "--pod $POD_NAME"; else echo "--publish 6379:6379"; fi) \
            $(if [[ ${POD_MODE:-false} == false && -n "${NETWORK_NAME:-}" ]]; then echo "--network" "$NETWORK_NAME"; fi) \
            --restart unless-stopped \
            --memory "${REDIS_MEMORY:-64m}" \
            --cpu-period 100000 \
            --cpu-quota "${REDIS_CPU_QUOTA:-10000}" \
            --volume "${DATA_ROOT}/redis-data:/data:Z" \
            --env "REDIS_PASSWORD=${REDIS_PASSWORD}" \
            --health-cmd "redis-cli --no-auth-warning -a \$REDIS_PASSWORD ping" \
            --health-interval 30s \
            --health-timeout 10s \
            --health-retries 3 \
            redis:alpine redis-server --requirepass "$REDIS_PASSWORD"
        
        okay "Redis deployed"
    fi
    
    # Deploy PostgreSQL
    if $ENABLE_POSTGRESQL; then
        info "Deploying PostgreSQL..."
        systemctl --user stop "container-${CONTAINER_NAME}-postgres.service" 2>/dev/null || true
        podman rm -f "${CONTAINER_NAME}-postgres" 2>/dev/null || true
        
        podman run -d \
            --name "${CONTAINER_NAME}-postgres" \
            $(if ${POD_MODE:-false}; then echo "--pod $POD_NAME"; else echo "--publish 5432:5432"; fi) \
            $(if [[ ${POD_MODE:-false} == false && -n "${NETWORK_NAME:-}" ]]; then echo "--network" "$NETWORK_NAME"; fi) \
            --restart unless-stopped \
            --memory "${POSTGRESQL_MEMORY:-256m}" \
            --cpu-period 100000 \
            --cpu-quota "${POSTGRESQL_CPU_QUOTA:-30000}" \
            --volume "${DATA_ROOT}/postgresql-data:/var/lib/postgresql/data:Z" \
            --env "POSTGRES_DB=${POSTGRESQL_DB:-appdb}" \
            --env "POSTGRES_USER=${POSTGRESQL_USER:-appuser}" \
            --env "POSTGRES_PASSWORD=${POSTGRESQL_PASSWORD}" \
            --env "PGDATA=/var/lib/postgresql/data/pgdata" \
            --health-cmd "pg_isready -U \$POSTGRES_USER -d \$POSTGRES_DB" \
            --health-interval 30s \
            --health-timeout 10s \
            --health-retries 3 \
            postgres:alpine
        
        okay "PostgreSQL deployed"
    fi
    
    # Deploy MongoDB
    if $ENABLE_MONGODB; then
        info "Deploying MongoDB..."
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
            --env "MONGO_INITDB_ROOT_USERNAME=${MONGODB_USER:-appuser}" \
            --env "MONGO_INITDB_ROOT_PASSWORD=${MONGODB_PASSWORD}" \
            --health-cmd "mongosh --eval 'db.adminCommand(\"ping\")'" \
            --health-interval 30s \
            --health-timeout 10s \
            --health-retries 3 \
            mongo:latest
        
        okay "MongoDB deployed"
    fi
    
    # Deploy extra containers
    for container_spec in "${EXTRA_CONTAINERS[@]}"; do
        if [[ -n "$container_spec" ]]; then
            IFS=':' read -r name image tag port memory cpu envs volumes health <<< "$container_spec"
            info "Deploying extra container: ${name}..."

            systemctl --user stop "container-${CONTAINER_NAME}-${name}.service" 2>/dev/null || true
            podman rm -f "${CONTAINER_NAME}-${name}" 2>/dev/null || true
            
            local cmd=(
                "podman" "run" "-d"
                "--name" "${CONTAINER_NAME}-${name}"
                "--restart" "unless-stopped"
                "--memory" "$memory"
                "--cpu-period" "100000"
                "--cpu-quota" "$cpu"
            )
            
            # Add pod or port mapping
            if ${POD_MODE:-false}; then
                cmd+=("--pod" "$POD_NAME")
            elif [[ "$port" != "0" ]]; then
                cmd+=("--publish" "${port}:${port}")
            fi

            if [[ ${POD_MODE:-false} == false && -n "${NETWORK_NAME:-}" ]]; then cmd+=("--network" "$NETWORK_NAME"); fi
            
            # Add volumes
            if [[ "$volumes" != "none" ]]; then
                IFS=',' read -ra VOLUME_LIST <<< "$volumes"
                for vol in "${VOLUME_LIST[@]}"; do
                    local vol_host_path="${DATA_ROOT}/$(echo "$vol" | cut -d':' -f1)"
                    local vol_container_path=$(echo "$vol" | cut -d':' -f2)
                    cmd+=("--volume" "${vol_host_path}:${vol_container_path}:Z")
                done
            fi
            
            # Add environment variables
            if [[ "$envs" != "none" ]]; then
                cmd+=("--env-file" "$ENV_FILE")
            fi
            
            # Add health check
            if [[ "$health" != "none" ]]; then
                cmd+=(
                    "--health-cmd" "$health"
                    "--health-interval" "30s"
                    "--health-timeout" "10s"
                    "--health-retries" "3"
                )
            fi
            
            # Add image
            cmd+=("${image}:${tag}")
            
            # Execute command
            "${cmd[@]}"
            
            okay "Extra container ${name} deployed"
        fi
    done
}

# ── Main Container Deployment
deploy_container() {
    info "Deploying ${CONTAINER_DESCRIPTION}..."
    
    # Clean up existing container
    systemctl --user stop "container-${CONTAINER_NAME}.service" 2>/dev/null || true
    podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
    
    # Build base command
    local cmd=(
        "podman" "run" "-d"
        "--name" "$CONTAINER_NAME"
        "--restart" "unless-stopped"
        "--env-file" "$ENV_FILE"
    )
    
    # Add pod or network options 
    if ${POD_MODE:-false}; then
        # In pod mode, only attach to pod (no individual ports or networks)
        cmd+=("--pod" "$POD_NAME")
    else
        # In standalone mode, publish ports and connect to network
        for port in "${PUBLISHED_PORTS[@]}"; do
            cmd+=("--publish" "$port")
        done
        
        if [[ -n "${NETWORK_NAME:-}" ]]; then
            cmd+=("--network" "$NETWORK_NAME")
        fi
    fi
    
    # Add resource limits
    cmd+=(
        "--memory" "$MEMORY_LIMIT"
        "--memory-swap" "${MEMORY_SWAP:-$MEMORY_LIMIT}"
        "--cpu-period" "100000"
        "--cpu-quota" "$CPU_QUOTA"
        "--cpu-shares" "$CPU_SHARES"
        "--blkio-weight" "$BLKIO_WEIGHT"
    )
    
    # Add volume directories
    for volume in "${VOLUME_DIRS[@]}"; do
        local host_path=$(echo "$volume" | cut -d':' -f1)
        local container_path=$(echo "$volume" | cut -d':' -f2)
        local options=$(echo "$volume" | cut -d':' -f3)
        
        # Convert relative paths to full paths
        if [[ ! "$host_path" =~ ^/ ]]; then
            host_path="${DATA_ROOT}/${host_path}"
        fi
        
        cmd+=("--volume" "${host_path}:${container_path}:${options}")
    done
    
    # Add health check
    if $HEALTH_CHECK_ENABLED; then
        cmd+=(
            "--health-cmd" "${HEALTH_CHECK_CMD}"
            "--health-interval" "${HEALTH_CHECK_INTERVAL}"
            "--health-timeout" "${HEALTH_CHECK_TIMEOUT}"
            "--health-retries" "${HEALTH_CHECK_RETRIES}"
        )
    fi
    
    # Add extra options
    for option in "${EXTRA_OPTIONS[@]}"; do
        cmd+=("$option")
    done
    
    # Add image name
    cmd+=("$IMAGE_NAME")

    # ── Add custom image parameters if specified
    if [[ -n "${IMAGE_PARAMETERS:-}" ]]; then
        # shellcheck disable=SC2206
        cmd+=( $IMAGE_PARAMETERS )
    fi
    
    # Execute the command
    "${cmd[@]}"
    
    okay "${CONTAINER_DESCRIPTION} deployed successfully"
}

# ── OAuth Proxy Deployment
deploy_oauth_proxy() {
    if ! $USE_OAUTH_PROXY; then
        return 0
    fi
    
    info "Deploying OAuth2 proxy..."
    
    # Clean up existing OAuth container
    podman rm -f "${CONTAINER_NAME}-oauth" 2>/dev/null || true
    
    # Build OAuth command
    local oauth_cmd=(
        "podman" "run" "-d"
        "--name" "${CONTAINER_NAME}-oauth"
        "--restart" "unless-stopped"
    )
    
    # Add pod or network options - UPDATED LOGIC
    if ${POD_MODE:-false}; then
        # In pod mode, only attach to pod
        oauth_cmd+=("--pod" "$POD_NAME")
    else
        # In standalone mode, publish port and connect to network
        oauth_cmd+=("--publish" "${OAUTH_EXTERNAL_PORT:-8080}:${OAUTH_INTERNAL_PORT:-8080}")
        
        if [[ -n "${NETWORK_NAME:-}" ]]; then
            oauth_cmd+=("--network" "$NETWORK_NAME")
        fi
    fi
    
    # Add resource limits
    oauth_cmd+=(
        "--memory" "${OAUTH_MEMORY_LIMIT:-128m}"
        "--memory-swap" "${OAUTH_MEMORY_SWAP:-256m}"
        "--cpu-period" "100000"
        "--cpu-quota" "${OAUTH_CPU_QUOTA:-25000}"
        "--cpu-shares" "${OAUTH_CPU_SHARES:-512}"
        "--blkio-weight" "${OAUTH_BLKIO_WEIGHT:-250}"
    )
    
    # Add OAuth emails file
    oauth_cmd+=("--volume" "${OAUTH_EMAILS_FILE}:/etc/oauth2_proxy/emails.txt:ro,Z")
    
    # Add OAuth environment variables
    oauth_cmd+=(
        "--env" "OAUTH2_PROXY_PROVIDER=google"
        "--env" "OAUTH2_PROXY_EMAIL_DOMAINS=*"
        "--env" "OAUTH2_PROXY_HTTP_ADDRESS=0.0.0.0:${OAUTH_INTERNAL_PORT:-8080}"
        "--env" "OAUTH2_PROXY_UPSTREAMS=http://127.0.0.1:${OAUTH_UPSTREAM_PORT:-8443}"
        "--env" "OAUTH2_PROXY_COOKIE_SECURE=true"
        "--env" "OAUTH2_PROXY_CLIENT_ID=${OAUTH_CLIENT_ID}"
        "--env" "OAUTH2_PROXY_CLIENT_SECRET=${OAUTH_CLIENT_SECRET}"
        "--env" "OAUTH2_PROXY_COOKIE_SECRET=${OAUTH_COOKIE_SECRET}"
        "--env" "OAUTH2_PROXY_AUTHENTICATED_EMAILS_FILE=/etc/oauth2_proxy/emails.txt"
        "--env" "OAUTH2_PROXY_CUSTOM_SIGN_IN_LOGO=${CONTAINER_LOGO}"
        "--env" "OAUTH2_PROXY_TITLE=${CONTAINER_NAME}"
        "--env" "OAUTH2_PROXY_FOOTER=${CONTAINER_DESCRIPTION}"
    )
    
    # Add OAuth image
    oauth_cmd+=("quay.io/oauth2-proxy/oauth2-proxy:latest-alpine")
    
    # Execute OAuth command
    "${oauth_cmd[@]}"
    
    okay "OAuth2 proxy deployed successfully"
}

# ── Systemd Service Generation
generate_systemd_service() {
    info "Generating user systemd service..."

    # Ensure user systemd directory exists
    local user_systemd_dir="${HOME}/.config/systemd/user"
    mkdir -p "$user_systemd_dir"

    # Use subshell - directory change is automatically contained
    (
        # Change to user systemd directory for file generation
        cd "$user_systemd_dir"
        
        if ${POD_MODE:-false}; then
            # Generate systemd files for pod
            podman generate systemd \
                --name "$POD_NAME" \
                --files \
                --new \
                --restart-policy=always
            
            # Enable user lingering (allows services to start at boot)
            loginctl enable-linger "$USER" 2>/dev/null || true
            
            # Reload user daemon and enable service
            systemctl --user daemon-reload
            systemctl --user enable "pod-${POD_NAME}.service"
            systemctl --user start "pod-${POD_NAME}.service"
            
            okay "User systemd service installed: pod-${POD_NAME}.service"
            info "Service location: ${user_systemd_dir}/pod-${POD_NAME}.service"
        else
            # Generate systemd files for standalone container
            podman generate systemd \
                --name "$CONTAINER_NAME" \
                --files \
                --new \
                --restart-policy=always
            
            # Enable user lingering
            loginctl enable-linger "$USER" 2>/dev/null || true
            
            # Reload user daemon and enable service
            systemctl --user daemon-reload
            systemctl --user enable "container-${CONTAINER_NAME}.service"
            
            okay "User systemd service installed: container-${CONTAINER_NAME}.service"
            info "Service location: ${user_systemd_dir}/container-${CONTAINER_NAME}.service"
        fi
    )
    # Directory automatically restored after subshell

    info "Use 'systemctl --user start <service-name>' to start the service"
    info "Use 'systemctl --user status <service-name>' to check status"
}


# ── Status Display
show_deployment_status() {
    info "Deployment Status for ${CONTAINER_DESCRIPTION}"
    echo "════════════════════════════════════════"
    echo "Container Name:  ${CONTAINER_NAME}"
    if ${POD_MODE:-false}; then
        echo "Pod Name:        ${POD_NAME}"
    fi
    echo "Image:           ${IMAGE_NAME}"
    echo "Data Directory:  ${DATA_ROOT}"
    echo "User Mapping:    ${MGRSYS_UID}:${MGRSYS_GID} (${MGRSYS_USER})"
    echo "Systemd Mode:    User services (--user)"
    
    if [[ ${#PUBLISHED_PORTS[@]} -gt 0 ]]; then
        echo "Published Ports:"
        for port in "${PUBLISHED_PORTS[@]}"; do
            echo "  - Main App: ${port}"
        done
    fi
    
    # Show service connections
    $ENABLE_REDIS && echo "  - Redis:    localhost:6379 (Password in .env)"
    $ENABLE_POSTGRESQL && echo "  - PostgreSQL: localhost:5432 (${POSTGRESQL_DB:-appdb}/${POSTGRESQL_USER:-appuser})"
    $ENABLE_MONGODB && echo "  - MongoDB:  localhost:27017 (${MONGODB_DB:-appdb}/${MONGODB_USER:-appuser})"
    
    # Show extra containers
    for container_spec in "${EXTRA_CONTAINERS[@]}"; do
        if [[ -n "$container_spec" ]]; then
            IFS=':' read -r name image tag port memory cpu envs volumes health <<< "$container_spec"
            if [[ "$port" != "0" ]]; then
                echo "  - ${name}: localhost:${port}"
            fi
        fi
    done
    
    if $USE_OAUTH_PROXY; then
        echo "  - OAuth:    localhost:${OAUTH_EXTERNAL_PORT:-8080}"
        echo "OAuth Config:    ${OAUTH_EMAILS_FILE}"
    fi
    
    echo "Environment:     ${ENV_FILE}"
    echo "════════════════════════════════════════"
    
    # Show container/pod status
    if ${POD_MODE:-false}; then
        podman pod ps --filter "name=${POD_NAME}" 2>/dev/null || true
        podman ps --filter "pod=${POD_NAME}" 2>/dev/null || true
    else
        podman ps --filter "name=${CONTAINER_NAME}" 2>/dev/null || true
    fi
    
    # Show connection strings
    if $ENABLE_REDIS || $ENABLE_POSTGRESQL || $ENABLE_MONGODB; then
        echo ""
        info "🔗 Service Connection Strings (also saved in .env):"
        $ENABLE_REDIS && echo "REDIS_URL=${REDIS_URL}"
        $ENABLE_POSTGRESQL && echo "DATABASE_URL=${POSTGRESQL_URL}"
        $ENABLE_MONGODB && echo "MONGODB_URL=${MONGODB_URL}"
    fi

    echo "════════════════════════════════════════"
    echo "Management Commands:"
    if ${POD_MODE:-false}; then
        echo "  Start:   systemctl --user start pod-${POD_NAME}.service"
        echo "  Stop:    systemctl --user stop pod-${POD_NAME}.service" 
        echo "  Status:  systemctl --user status pod-${POD_NAME}.service"
        echo "  Logs:    journalctl --user -u pod-${POD_NAME}.service -f"
    else
        echo "  Start:   systemctl --user start container-${CONTAINER_NAME}.service"
        echo "  Stop:    systemctl --user stop container-${CONTAINER_NAME}.service"
        echo "  Status:  systemctl --user status container-${CONTAINER_NAME}.service" 
        echo "  Logs:    journalctl --user -u container-${CONTAINER_NAME}.service -f"
    fi
}

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  🚀 MAIN DEPLOYMENT FUNCTION
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
deploy_container_stack() {
    info "🐳 Deploying ${CONTAINER_DESCRIPTION}..."
    
    # Validate configuration from container script
    validate_configuration
    initialize_paths
    
    # Pre-deployment checks
    check_system_resources
    validate_mgrsys_user
    
    # Setup phase
    ensure_directories
    setup_env_file
    load_environment
    
    # Build and deploy
    build_image
    setup_network
    setup_pod
    deploy_service_containers
    deploy_container
    deploy_oauth_proxy
    
    # Post-deployment
    generate_systemd_service
    show_deployment_status
    
    okay "🎊 ${CONTAINER_DESCRIPTION} is ready!"
    
    if $USE_OAUTH_PROXY; then
        warn "📝 Don't forget to add allowed emails to: ${OAUTH_EMAILS_FILE}"
        info "🔒 Access via OAuth: http://your-server:${OAUTH_EXTERNAL_PORT:-8080}"
    fi
}

# ── Cleanup Handler
cleanup() {
    trap - EXIT
    okay "Deployment completed! 🎉"
}
trap cleanup EXIT

# ── Template Version Info
template_info() {
    echo "📋 Universal Podman Container Template v2025-09-12"
    echo "🏠 HOMELAB :: ZAP-VPS"
    echo "👨‍💻 Author: Mohamed Zarka"
}

# Show template info when sourced
template_info
