#!/usr/bin/env bash
set -Eeuo pipefail

QUADLET_DIR="${QUADLET_DIR:-$HOME/.config/containers/systemd}"
SHOW_INACTIVE="${SHOW_INACTIVE:-yes}"

log() {
  printf '[INFO] %s\n' "$*"
}

is_no() {
  case "${1,,}" in
    no|false|0)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

service_field() {
  local svc="$1"
  local key="$2"
  systemctl --user show "$svc" --property "$key" --value 2>/dev/null || true
}

container_health() {
  local name="$1"
  local cid

  cid="$(podman ps -a --filter "name=^${name}$" --format '{{.ID}}' | head -n 1)"
  if [[ -z "$cid" ]]; then
    printf '%s' '-'
    return
  fi

  podman inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$cid" 2>/dev/null || printf '%s' 'unknown'
}

container_status() {
  local name="$1"
  local cid

  cid="$(podman ps -a --filter "name=^${name}$" --format '{{.ID}}' | head -n 1)"
  if [[ -z "$cid" ]]; then
    printf '%s' '-'
    return
  fi

  podman inspect --format '{{.State.Status}}' "$cid" 2>/dev/null || printf '%s' 'unknown'
}

print_header() {
  printf '%-28s %-10s %-10s %-12s %-12s %-10s\n' 'SERVICE' 'ENABLED' 'ACTIVE' 'SUBSTATE' 'CONTAINER' 'HEALTH'
  printf '%-28s %-10s %-10s %-12s %-12s %-10s\n' '-------' '-------' '------' '--------' '---------' '------'
}

print_status_rows() {
  local found=0
  local file

  while IFS= read -r -d '' file; do
    local name
    local svc
    local enabled
    local active
    local substate
    local cstatus
    local chealth

    name="$(basename "$file" .container)"
    svc="${name}.service"
    enabled="$(systemctl --user is-enabled "$svc" 2>/dev/null || echo not-found)"
    active="$(systemctl --user is-active "$svc" 2>/dev/null || echo not-found)"
    substate="$(service_field "$svc" SubState)"
    cstatus="$(container_status "$name")"
    chealth="$(container_health "$name")"

    if is_no "$SHOW_INACTIVE" && [[ "$active" != "active" ]]; then
      continue
    fi

    printf '%-28s %-10s %-10s %-12s %-12s %-10s\n' "$svc" "$enabled" "$active" "${substate:--}" "$cstatus" "$chealth"
    found=1
  done < <(find "$QUADLET_DIR" -maxdepth 1 -type f -name '*.container' -print0 | sort -z)

  if [[ "$found" -eq 0 ]]; then
    log "No services to display. Check QUADLET_DIR=$QUADLET_DIR"
  fi
}

main() {
  command -v podman >/dev/null 2>&1 || { echo '[ERROR] Missing command: podman' >&2; exit 1; }
  command -v systemctl >/dev/null 2>&1 || { echo '[ERROR] Missing command: systemctl' >&2; exit 1; }

  if [[ ! -d "$QUADLET_DIR" ]]; then
    echo "[ERROR] Quadlet directory not found: $QUADLET_DIR" >&2
    exit 1
  fi

  systemctl --user daemon-reload >/dev/null 2>&1 || true

  print_header
  print_status_rows
}

main "$@"
