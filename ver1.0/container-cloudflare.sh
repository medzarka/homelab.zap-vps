#!/usr/bin/env bash
set -Eeuo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-cloudflare}"
SECRET_NAME="${SECRET_NAME:-cloudflare_tunnel_token}"
NETWORK_NAME="${NETWORK_NAME:-zap-vps-podman-network}"
IMAGE="${IMAGE:-docker.io/cloudflare/cloudflared:latest}"
METRICS_BIND="${METRICS_BIND:-0.0.0.0:2000}"
DATA_DIR="${DATA_DIR:-$HOME/podman_data/cloudflare}"
SERVICE_DIR="${SERVICE_DIR:-$HOME/.config/systemd/user}"

log() {
    printf '[INFO] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*"
}

fail() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

ensure_secret() {
    if podman secret exists "$SECRET_NAME"; then
        log "Using existing Podman secret: $SECRET_NAME"
        return
    fi

    printf 'Enter your Cloudflare tunnel token: '
    read -r -s tunnel_token
    printf '\n'

    [[ -n "$tunnel_token" ]] || fail "Token cannot be empty."
    printf '%s' "$tunnel_token" | podman secret create "$SECRET_NAME" - >/dev/null
    log "Created Podman secret: $SECRET_NAME"
}

ensure_network() {
    if ! podman network exists "$NETWORK_NAME"; then
        log "Creating Podman network: $NETWORK_NAME"
        podman network create "$NETWORK_NAME" >/dev/null
    fi
}

deploy_container() {
    log "Removing previous container if present."
    systemctl --user disable --now "container-${CONTAINER_NAME}.service" >/dev/null 2>&1 || true
    podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

    log "Starting cloudflared container."
    podman run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        --pull always \
        --network "$NETWORK_NAME" \
        --read-only \
        --tmpfs /tmp:rw,size=32m,nodev,nosuid \
        --cap-drop all \
        --security-opt no-new-privileges \
        --memory 256m \
        --cpu-shares 512 \
        --secret "${SECRET_NAME},type=env,target=TUNNEL_TOKEN" \
        --label homepage.group="Network" \
        --label homepage.name="Cloudflare Tunnel" \
        --label homepage.icon="cloudflare" \
        --label homepage.href="https://one.dash.cloudflare.com" \
        --label homepage.description="Outbound zero-trust tunnel" \
        "$IMAGE" tunnel --no-autoupdate --metrics "$METRICS_BIND" run >/dev/null
}

enable_user_service() {
    local service_file="container-${CONTAINER_NAME}.service"

    mkdir -p "$SERVICE_DIR"
    podman generate systemd --new --name "$CONTAINER_NAME" --files >/dev/null
    mv -f "$service_file" "$SERVICE_DIR/$service_file"

    systemctl --user daemon-reload
    systemctl --user enable --now "$service_file"
}

print_summary() {
    local container_id
    container_id="$(podman ps --filter "name=^${CONTAINER_NAME}$" --format '{{.ID}}')"

    printf '\nCloudflare tunnel is deployed.\n'
    printf 'Container name: %s\n' "$CONTAINER_NAME"
    printf 'Container id  : %s\n' "${container_id:-not-running}"
    printf 'Secret name   : %s\n' "$SECRET_NAME"
    printf 'Network       : %s\n' "$NETWORK_NAME"
    printf 'Metrics bind  : %s\n' "$METRICS_BIND"

    printf '\nUseful commands:\n'
    printf '  systemctl --user status container-%s.service\n' "$CONTAINER_NAME"
    printf '  podman logs -f %s\n' "$CONTAINER_NAME"
    printf '  podman secret inspect %s\n' "$SECRET_NAME"

    if ! loginctl show-user "$USER" 2>/dev/null | grep -q 'Linger=yes'; then
        warn "User lingering is not enabled. Services may stop after logout."
        warn "Run as root once: loginctl enable-linger $USER"
    fi
}

main() {
    require_command podman
    require_command systemctl
    require_command loginctl

    mkdir -p "$DATA_DIR"
    chmod 700 "$DATA_DIR"

    ensure_secret
    ensure_network
    deploy_container
    enable_user_service
    print_summary
}

main "$@"
