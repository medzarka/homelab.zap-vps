#!/usr/bin/env bash
set -Eeuo pipefail

# Reusable template for rootless Podman service deployment.
# Copy this file and adjust variables per container.

APP_NAME="${APP_NAME:-sample-app}"
IMAGE="${IMAGE:-docker.io/library/nginx:stable-alpine}"
NETWORK_NAME="${NETWORK_NAME:-zap-vps-podman-network}"
PUBLISH_PORT="${PUBLISH_PORT:-8080:80}"
HOST_DATA_DIR="${HOST_DATA_DIR:-$HOME/podman_data/${APP_NAME}/data}"
CONTAINER_DATA_DIR="${CONTAINER_DATA_DIR:-/var/lib/app}"
MEMORY_LIMIT="${MEMORY_LIMIT:-512m}"
CPU_QUOTA="${CPU_QUOTA:-50000}"
ENABLE_HARDENING="${ENABLE_HARDENING:-yes}"

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '[ERROR] Missing command: %s\n' "$1" >&2
    exit 1
  }
}

ensure_network() {
  if ! podman network exists "${NETWORK_NAME}"; then
    log "Creating Podman network ${NETWORK_NAME}."
    podman network create "${NETWORK_NAME}"
  fi
}

create_directories() {
  install -d -m 755 "${HOST_DATA_DIR}"
}

remove_existing_container() {
  podman rm -f "${APP_NAME}" >/dev/null 2>&1 || true
}

run_container() {
  local run_args=(
    -d
    --name "${APP_NAME}"
    --network "${NETWORK_NAME}"
    --restart unless-stopped
    --userns keep-id
    --memory "${MEMORY_LIMIT}"
    --cpu-quota "${CPU_QUOTA}"
    -p "${PUBLISH_PORT}"
    -v "${HOST_DATA_DIR}:${CONTAINER_DATA_DIR}:Z"
  )

  if [[ "${ENABLE_HARDENING}" == "yes" ]]; then
    run_args+=(
      --read-only
      --tmpfs /tmp:rw,size=64m,nodev,nosuid
      --cap-drop all
      --security-opt no-new-privileges
    )
  fi

  log "Starting container ${APP_NAME} from ${IMAGE}."
  podman run "${run_args[@]}" "${IMAGE}"
}

generate_user_service() {
  local service_file="container-${APP_NAME}.service"

  mkdir -p "$HOME/.config/systemd/user"
  podman generate systemd --new --name "${APP_NAME}" --files >/dev/null
  mv -f "${service_file}" "$HOME/.config/systemd/user/${service_file}"

  systemctl --user daemon-reload
  systemctl --user enable --now "${service_file}"
}

print_troubleshooting() {
  cat <<'EOF'

Troubleshooting hints:
1. SELinux volume denial:
   - Use :Z or :z on bind mounts.
   - Run: sudo restorecon -Rv "$HOME/podman_data"

2. Rootless permission errors (UID/GID mismatch):
   - Run: podman unshare chown -R 1000:1000 "$HOME/podman_data/<app>"
   - Keep --userns keep-id in podman run.

3. Port binding errors on ports below 1024:
   - Run: sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80
   - Persist it in /etc/sysctl.d/99-rootless-ports.conf

4. systemctl --user service does not start on boot:
   - Run once as root: sudo loginctl enable-linger <user>

5. Reset only this deployment:
   - systemctl --user disable --now container-<app>.service
   - podman rm -f <app>
EOF
}

main() {
  require_command podman
  require_command systemctl

  create_directories
  ensure_network
  remove_existing_container
  run_container
  generate_user_service

  podman ps --filter "name=${APP_NAME}"
  print_troubleshooting
}

main "$@"
