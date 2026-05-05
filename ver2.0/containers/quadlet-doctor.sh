#!/usr/bin/env bash
set -Eeuo pipefail

QUADLET_DIR="${QUADLET_DIR:-$HOME/.config/containers/systemd}"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

log() {
  printf '[INFO] %s\n' "$*"
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[PASS] %s\n' "$*"
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf '[WARN] %s\n' "$*"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[FAIL] %s\n' "$*"
}

check_command() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "Command available: $cmd"
  else
    fail "Missing command: $cmd"
  fi
}

check_cgroup_v2() {
  local version
  version="$(podman info --format '{{.Host.CgroupsVersion}}' 2>/dev/null || true)"

  if [[ "$version" == "v2" ]]; then
    pass "Podman is using cgroup v2"
  elif [[ -n "$version" ]]; then
    fail "Podman is using $version (Quadlet requires cgroup v2)"
  else
    warn "Could not read cgroup version from podman info"
  fi
}

check_linger_status() {
  local linger
  linger="$(loginctl show-user "$USER" -p Linger --value 2>/dev/null || true)"

  if [[ "$linger" == "yes" ]]; then
    pass "User linger is enabled"
  elif [[ "$linger" == "no" ]]; then
    warn "User linger is disabled (enable with: sudo loginctl enable-linger $USER)"
  else
    warn "Could not read linger status (this can happen on minimal systems)"
  fi
}

verify_service() {
  local svc="$1"

  if ! systemctl --user cat "$svc" >/dev/null 2>&1; then
    fail "Service not generated: $svc"
    return
  fi
  pass "Service generated: $svc"

  if systemd-analyze --user --generators=true verify "$svc" >/dev/null 2>&1; then
    pass "systemd-analyze verify passed: $svc"
  else
    warn "systemd-analyze verify reported issues: $svc"
  fi

  case "$(systemctl --user is-enabled "$svc" 2>/dev/null || true)" in
    enabled)
      pass "Service enabled: $svc"
      ;;
    generated)
      pass "Service is generated (expected for Quadlet): $svc"
      ;;
    disabled|masked|static)
      warn "Service not enabled ($svc): $(systemctl --user is-enabled "$svc" 2>/dev/null || true)"
      ;;
    *)
      warn "Service enablement unknown: $svc"
      ;;
  esac

  case "$(systemctl --user is-active "$svc" 2>/dev/null || true)" in
    active)
      pass "Service active: $svc"
      ;;
    inactive|failed|activating|deactivating)
      warn "Service state is not active ($svc): $(systemctl --user is-active "$svc" 2>/dev/null || true)"
      ;;
    *)
      warn "Service activity unknown: $svc"
      ;;
  esac
}

validate_quadlet_files() {
  local found=0
  local file

  if [[ ! -d "$QUADLET_DIR" ]]; then
    fail "Quadlet directory not found: $QUADLET_DIR"
    return
  fi

  while IFS= read -r -d '' file; do
    local name
    local svc

    name="$(basename "$file" .container)"
    svc="${name}.service"
    found=1

    log "Validating $file"
    verify_service "$svc"
  done < <(find "$QUADLET_DIR" -maxdepth 1 -type f -name '*.container' -print0)

  if [[ "$found" -eq 0 ]]; then
    warn "No .container files found in $QUADLET_DIR"
  fi
}

print_summary() {
  printf '\n--- Quadlet Doctor Summary ---\n'
  printf 'PASS: %d\n' "$PASS_COUNT"
  printf 'WARN: %d\n' "$WARN_COUNT"
  printf 'FAIL: %d\n' "$FAIL_COUNT"

  if [[ "$FAIL_COUNT" -gt 0 ]]; then
    return 1
  fi

  return 0
}

main() {
  check_command podman
  check_command systemctl
  check_command systemd-analyze

  if [[ "$FAIL_COUNT" -gt 0 ]]; then
    print_summary
    exit 1
  fi

  check_cgroup_v2
  check_linger_status

  systemctl --user daemon-reload || fail "systemctl --user daemon-reload failed"

  validate_quadlet_files

  if print_summary; then
    exit 0
  fi

  exit 1
}

main "$@"
