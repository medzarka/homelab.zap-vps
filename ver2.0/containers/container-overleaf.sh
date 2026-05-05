#!/usr/bin/env bash
set -Eeuo pipefail

STACK_NAME="${STACK_NAME:-overleaf}"
APP_NAME="${APP_NAME:-${STACK_NAME}}"
MONGO_NAME="${MONGO_NAME:-${STACK_NAME}-mongo}"
REDIS_NAME="${REDIS_NAME:-${STACK_NAME}-redis}"

NETWORK_NAME="${NETWORK_NAME:-zap-vps-podman-network}"
OVERLEAF_IMAGE="${OVERLEAF_IMAGE:-docker.io/sharelatex/sharelatex:latest}"
MONGO_IMAGE="${MONGO_IMAGE:-docker.io/library/mongo:6}"
REDIS_IMAGE="${REDIS_IMAGE:-docker.io/library/redis:7-alpine}"

OVERLEAF_BIND="${OVERLEAF_BIND:-8081:80}"
SITE_URL="${SITE_URL:-http://localhost:8081}"
DISABLE_SIGNUPS="${DISABLE_SIGNUPS:-true}"

HOST_BASE_DIR="${HOST_BASE_DIR:-$HOME/podman_data/overleaf}"
HOST_OVERLEAF_DIR="${HOST_OVERLEAF_DIR:-$HOST_BASE_DIR/overleaf-data}"
HOST_MONGO_DIR="${HOST_MONGO_DIR:-$HOST_BASE_DIR/mongo-db}"
HOST_REDIS_DIR="${HOST_REDIS_DIR:-$HOST_BASE_DIR/redis-data}"

OVERLEAF_MEMORY_LIMIT="${OVERLEAF_MEMORY_LIMIT:-2g}"
OVERLEAF_CPU_SHARES="${OVERLEAF_CPU_SHARES:-1536}"
MONGO_MEMORY_LIMIT="${MONGO_MEMORY_LIMIT:-1g}"
MONGO_CPU_SHARES="${MONGO_CPU_SHARES:-768}"
REDIS_MEMORY_LIMIT="${REDIS_MEMORY_LIMIT:-256m}"
REDIS_CPU_SHARES="${REDIS_CPU_SHARES:-256}"

QUADLET_DIR="${QUADLET_DIR:-$HOME/.config/containers/systemd}"

log() {
  printf '[INFO] %s\n' "$*"
}

fail() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"
}

is_unlimited() {
  case "${1,,}" in
    ""|none|off|no|unlimited|0)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

append_resource_limits() {
  local file="$1"
  local memory_limit="$2"
  local cpu_shares="$3"

  if ! is_unlimited "$memory_limit"; then
    printf 'Memory=%s\n' "$memory_limit" >> "$file"
  fi

  if ! is_unlimited "$cpu_shares"; then
    printf 'PodmanArgs=--cpu-shares=%s\n' "$cpu_shares" >> "$file"
  fi
}

quadlet_file() {
  local name="$1"
  printf '%s/%s.container' "$QUADLET_DIR" "$name"
}

ensure_network() {
  if ! podman network exists "$NETWORK_NAME"; then
    log "Creating network: $NETWORK_NAME"
    podman network create "$NETWORK_NAME" >/dev/null
  fi
}

prepare_storage() {
  install -d -m 755 "$HOST_OVERLEAF_DIR" "$HOST_MONGO_DIR" "$HOST_REDIS_DIR"
}

cleanup_legacy_deployments() {
  local name
  for name in "$APP_NAME" "$MONGO_NAME" "$REDIS_NAME"; do
    local legacy_service="container-${name}.service"

    systemctl --user disable --now "$legacy_service" >/dev/null 2>&1 || true
    rm -f "$HOME/.config/systemd/user/$legacy_service"
    systemctl --user disable --now "${name}.service" >/dev/null 2>&1 || true
    podman rm -f "$name" >/dev/null 2>&1 || true
  done
}

write_mongo_quadlet() {
  local file
  file="$(quadlet_file "$MONGO_NAME")"

  cat > "$file" <<EOF
[Unit]
Description=Overleaf MongoDB container managed by Quadlet
After=network-online.target
Wants=network-online.target

[Container]
Image=${MONGO_IMAGE}
ContainerName=${MONGO_NAME}
Pull=always
Network=${NETWORK_NAME}
Volume=${HOST_MONGO_DIR}:/data/db:Z
Exec=--bind_ip_all
EOF

  append_resource_limits "$file" "$MONGO_MEMORY_LIMIT" "$MONGO_CPU_SHARES"

  cat >> "$file" <<'EOF'

[Service]
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

  log "Quadlet file written: $file"
}

write_redis_quadlet() {
  local file
  file="$(quadlet_file "$REDIS_NAME")"

  cat > "$file" <<EOF
[Unit]
Description=Overleaf Redis container managed by Quadlet
After=network-online.target
Wants=network-online.target

[Container]
Image=${REDIS_IMAGE}
ContainerName=${REDIS_NAME}
Pull=always
Network=${NETWORK_NAME}
Volume=${HOST_REDIS_DIR}:/data:Z
Exec=redis-server --appendonly yes
EOF

  append_resource_limits "$file" "$REDIS_MEMORY_LIMIT" "$REDIS_CPU_SHARES"

  cat >> "$file" <<'EOF'

[Service]
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

  log "Quadlet file written: $file"
}

write_overleaf_quadlet() {
  local file
  file="$(quadlet_file "$APP_NAME")"

  cat > "$file" <<EOF
[Unit]
Description=Overleaf container managed by Quadlet
After=network-online.target ${MONGO_NAME}.service ${REDIS_NAME}.service
Wants=network-online.target
Requires=${MONGO_NAME}.service ${REDIS_NAME}.service

[Container]
Image=${OVERLEAF_IMAGE}
ContainerName=${APP_NAME}
Pull=always
Network=${NETWORK_NAME}
PublishPort=${OVERLEAF_BIND}
Volume=${HOST_OVERLEAF_DIR}:/var/lib/overleaf:Z
Environment=OVERLEAF_APP_NAME=Self Hosted Overleaf
Environment=OVERLEAF_MONGO_URL=mongodb://${MONGO_NAME}:27017/overleaf
Environment=OVERLEAF_REDIS_HOST=${REDIS_NAME}
Environment=OVERLEAF_SITE_URL=${SITE_URL}
Environment=OVERLEAF_DISABLE_SIGNUPS=${DISABLE_SIGNUPS}
EOF

  append_resource_limits "$file" "$OVERLEAF_MEMORY_LIMIT" "$OVERLEAF_CPU_SHARES"

  cat >> "$file" <<'EOF'

[Service]
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

  log "Quadlet file written: $file"
}

reload_and_start_quadlet() {
  systemctl --user daemon-reload

  for svc in "${MONGO_NAME}.service" "${REDIS_NAME}.service" "${APP_NAME}.service"; do
    if ! systemctl --user cat "$svc" >/dev/null 2>&1; then
      fail "Quadlet service was not generated by systemd: $svc"
    fi
  done

  systemctl --user start "${MONGO_NAME}.service"
  systemctl --user start "${REDIS_NAME}.service"
  systemctl --user start "${APP_NAME}.service"
}

print_summary() {
  printf '\nOverleaf stack is running.\n'
  printf 'App service  : %s.service\n' "$APP_NAME"
  printf 'Mongo service: %s.service\n' "$MONGO_NAME"
  printf 'Redis service: %s.service\n' "$REDIS_NAME"
  printf 'Network      : %s\n' "$NETWORK_NAME"
  printf '\nCommands:\n'
  printf '  systemctl --user status %s.service %s.service %s.service\n' "$APP_NAME" "$MONGO_NAME" "$REDIS_NAME"
  printf '  podman logs -f %s\n' "$APP_NAME"
}

main() {
  require_command podman
  require_command systemctl

  mkdir -p "$QUADLET_DIR"

  ensure_network
  prepare_storage
  cleanup_legacy_deployments
  write_mongo_quadlet
  write_redis_quadlet
  write_overleaf_quadlet
  reload_and_start_quadlet
  print_summary
}

main "$@"
