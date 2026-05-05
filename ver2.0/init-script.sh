#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ----------------------------------------------------------------------------
# Oracle Linux 10 post-install bootstrap
# ----------------------------------------------------------------------------
# This script is designed to be idempotent and safe on OL10 minimal installs.
# It applies a baseline for SSH hardening, package setup, firewalld, Cockpit,
# automatic updates, and journal retention.
# ----------------------------------------------------------------------------

ADMIN_USER="${ADMIN_USER:-mgrsys}"
ADMIN_PUBKEY="${ADMIN_PUBKEY:-}"
SSH_PORT="${SSH_PORT:-22}"
ALLOW_PASSWORD_AUTH="${ALLOW_PASSWORD_AUTH:-no}"
ALLOW_ROOT_LOGIN="${ALLOW_ROOT_LOGIN:-no}"
COCKPIT_ALLOWED_CIDR="${COCKPIT_ALLOWED_CIDR:-}"
OPEN_HTTP_PORTS="${OPEN_HTTP_PORTS:-yes}"
INSTALL_FAIL2BAN="${INSTALL_FAIL2BAN:-yes}"
JOURNAL_RETENTION_DAYS="${JOURNAL_RETENTION_DAYS:-30}"
JOURNAL_MAX_USE="${JOURNAL_MAX_USE:-512M}"

BASE_PACKAGES=(
  nano
  htop
  git
  curl
  wget
  zip
  unzip
  tmux
  rsync
  jq
  tree
  firewalld
  policycoreutils-python-utils
  dnf-automatic
  podman
  podman-plugins
  cockpit
  cockpit-podman
)

OPTIONAL_PACKAGES=(
  btop
  cockpit-files
  podman-compose
)

FAIL2BAN_PACKAGES=(
  fail2ban
  fail2ban-systemd
  fail2ban-firewalld
)

UNAVAILABLE_PACKAGES=()

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

on_error() {
  local line="$1"
  local cmd="$2"
  printf '[ERROR] Command failed at line %s: %s\n' "$line" "$cmd" >&2
}
trap 'on_error "${LINENO}" "${BASH_COMMAND}"' ERR

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "Run this script with sudo or as root."
  fi
}

require_commands() {
  local required=(dnf systemctl firewall-cmd sshd)
  local cmd
  for cmd in "${required[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Required command not found: $cmd"
  done
}

check_platform() {
  if [[ ! -f /etc/os-release ]]; then
    fail "Unsupported system: /etc/os-release not found."
  fi

  # shellcheck disable=SC1091
  source /etc/os-release

  if [[ "${ID:-}" != "ol" ]] || [[ "${VERSION_ID:-}" != "10"* ]]; then
    warn "This script targets Oracle Linux 10. Detected ${ID:-unknown} ${VERSION_ID:-unknown}."
  else
    log "Platform check: Oracle Linux ${VERSION_ID}"
  fi
}

package_available() {
  local pkg="$1"
  dnf -q list --available "$pkg" >/dev/null 2>&1
}

package_installed() {
  local pkg="$1"
  rpm -q "$pkg" >/dev/null 2>&1
}

install_if_available() {
  local pkg="$1"

  if package_installed "$pkg"; then
    log "Package already installed: $pkg"
    return 0
  fi

  if package_available "$pkg"; then
    dnf -y install "$pkg" >/dev/null
    log "Installed package: $pkg"
  else
    warn "Package unavailable in enabled repos: $pkg"
    UNAVAILABLE_PACKAGES+=("$pkg")
  fi
}

enable_epel() {
  if package_installed oracle-epel-release-el10; then
    log "oracle-epel-release-el10 already installed."
    return
  fi

  if package_available oracle-epel-release-el10; then
    dnf -y install oracle-epel-release-el10 >/dev/null
    log "Installed oracle-epel-release-el10."
  else
    warn "oracle-epel-release-el10 not available. Continuing without EPEL."
  fi
}

ensure_admin_user() {
  if ! id "${ADMIN_USER}" >/dev/null 2>&1; then
    log "Creating admin user ${ADMIN_USER}."
    useradd -m -G wheel -s /bin/bash "${ADMIN_USER}"
  fi

  install -d -m 700 -o "${ADMIN_USER}" -g "${ADMIN_USER}" "/home/${ADMIN_USER}/.ssh"
  touch "/home/${ADMIN_USER}/.ssh/authorized_keys"
  chown "${ADMIN_USER}:${ADMIN_USER}" "/home/${ADMIN_USER}/.ssh/authorized_keys"
  chmod 600 "/home/${ADMIN_USER}/.ssh/authorized_keys"

  if [[ -n "${ADMIN_PUBKEY}" ]] && ! grep -Fq "${ADMIN_PUBKEY}" "/home/${ADMIN_USER}/.ssh/authorized_keys"; then
    printf '%s\n' "${ADMIN_PUBKEY}" >> "/home/${ADMIN_USER}/.ssh/authorized_keys"
    log "SSH public key installed for ${ADMIN_USER}."
  fi

  if [[ "${ALLOW_PASSWORD_AUTH}" == "no" ]] && [[ ! -s "/home/${ADMIN_USER}/.ssh/authorized_keys" ]]; then
    fail "Password auth is disabled but no SSH key is configured for ${ADMIN_USER}."
  fi

  cat > "/etc/sudoers.d/${ADMIN_USER}" <<EOF
${ADMIN_USER} ALL=(ALL) NOPASSWD: ALL
EOF
  chmod 440 "/etc/sudoers.d/${ADMIN_USER}"
  visudo -c >/dev/null
}

install_packages() {
  local pkg

  log "Updating system metadata and packages."
  dnf -y update >/dev/null

  enable_epel
  dnf -y makecache >/dev/null

  log "Installing baseline packages."
  for pkg in "${BASE_PACKAGES[@]}"; do
    install_if_available "$pkg"
  done

  log "Installing optional packages when available."
  for pkg in "${OPTIONAL_PACKAGES[@]}"; do
    install_if_available "$pkg"
  done
}

configure_selinux() {
  log "Ensuring SELinux is enforcing."
  sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
  setenforce 1 || warn "setenforce failed (may require reboot)."
}

harden_ssh() {
  local hardening_file="/etc/ssh/sshd_config.d/10-hardening.conf"

  log "Applying SSH hardening."
  cat > "$hardening_file" <<EOF
Port ${SSH_PORT}
Protocol 2
PermitRootLogin ${ALLOW_ROOT_LOGIN}
PasswordAuthentication ${ALLOW_PASSWORD_AUTH}
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
UsePAM yes
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 30
MaxAuthTries 3
AllowUsers ${ADMIN_USER}
EOF

  sshd -t
  systemctl enable --now sshd
  systemctl reload sshd
}

configure_firewalld() {
  log "Configuring firewalld rules."
  systemctl enable --now firewalld

  if [[ "${SSH_PORT}" == "22" ]]; then
    firewall-cmd --permanent --add-service=ssh >/dev/null
  else
    firewall-cmd --permanent --remove-service=ssh >/dev/null || true
    firewall-cmd --permanent --add-port="${SSH_PORT}/tcp" >/dev/null
  fi

  if [[ -n "${COCKPIT_ALLOWED_CIDR}" ]]; then
    firewall-cmd --permanent --remove-service=cockpit >/dev/null || true
    firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${COCKPIT_ALLOWED_CIDR} port protocol=tcp port=9090 accept" >/dev/null
  else
    warn "COCKPIT_ALLOWED_CIDR is empty. Cockpit will be exposed on 9090/tcp."
    firewall-cmd --permanent --add-service=cockpit >/dev/null
  fi

  if [[ "${OPEN_HTTP_PORTS}" == "yes" ]]; then
    firewall-cmd --permanent --add-service=http >/dev/null
    firewall-cmd --permanent --add-service=https >/dev/null
  fi

  firewall-cmd --reload >/dev/null
}

configure_automatic_updates() {
  log "Enabling automatic security updates."
  systemctl enable --now dnf-automatic.timer
  sed -ri 's/^apply_updates.*/apply_updates = yes/' /etc/dnf/automatic.conf
  systemctl restart dnf-automatic.timer
}

configure_cockpit_and_podman() {
  log "Enabling Cockpit and Podman socket."
  systemctl enable --now cockpit.socket
  systemctl enable --now podman.socket
}

configure_intrusion_prevention() {
  local pkg
  local all_available=true

  if [[ "${INSTALL_FAIL2BAN}" != "yes" ]]; then
    log "Skipping Fail2ban installation by request."
    return
  fi

  for pkg in "${FAIL2BAN_PACKAGES[@]}"; do
    if ! package_available "$pkg" && ! package_installed "$pkg"; then
      all_available=false
      break
    fi
  done

  if [[ "$all_available" == "true" ]]; then
    log "Installing Fail2ban stack."
    for pkg in "${FAIL2BAN_PACKAGES[@]}"; do
      install_if_available "$pkg"
    done

    if command -v fail2ban-client >/dev/null 2>&1; then
      systemctl enable --now fail2ban
      log "Fail2ban enabled."
      return
    fi
  fi

  warn "Fail2ban packages are not fully available on current OL10 repos."
  warn "Trying sshguard fallback."

  if package_available sshguard || package_installed sshguard; then
    install_if_available sshguard
    systemctl enable --now sshguard || warn "Could not start sshguard."
  else
    warn "sshguard is also unavailable. Keep strict SSH key auth and firewall source restrictions."
  fi
}

configure_journald_retention() {
  local conf_file="/etc/systemd/journald.conf.d/99-retention-30days.conf"
  local service_file="/etc/systemd/system/journal-retention-check.service"
  local timer_file="/etc/systemd/system/journal-retention-check.timer"

  log "Configuring journald retention to last ${JOURNAL_RETENTION_DAYS} days."
  mkdir -p /etc/systemd/journald.conf.d

  cat > "$conf_file" <<EOF
[Journal]
SystemMaxUse=${JOURNAL_MAX_USE}
MaxRetentionSec=${JOURNAL_RETENTION_DAYS}day
EOF

  systemctl restart systemd-journald

  # Immediate one-time cleanup so policy is enforced now.
  journalctl --vacuum-time="${JOURNAL_RETENTION_DAYS}d" >/dev/null || warn "journalctl vacuum failed."

  # Daily check/enforcement timer to keep only the last month.
  cat > "$service_file" <<EOF
[Unit]
Description=Vacuum journal entries older than ${JOURNAL_RETENTION_DAYS} days

[Service]
Type=oneshot
ExecStart=/usr/bin/journalctl --vacuum-time=${JOURNAL_RETENTION_DAYS}d
EOF

  cat > "$timer_file" <<'EOF'
[Unit]
Description=Daily journal retention check

[Timer]
OnCalendar=daily
Persistent=true
Unit=journal-retention-check.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now journal-retention-check.timer
}

print_summary() {
  printf '\nDone. Post-install baseline is applied.\n'
  printf 'Admin user          : %s\n' "$ADMIN_USER"
  printf 'SSH port            : %s\n' "$SSH_PORT"
  printf 'Root login          : %s\n' "$ALLOW_ROOT_LOGIN"
  printf 'Password auth       : %s\n' "$ALLOW_PASSWORD_AUTH"
  printf 'Cockpit CIDR policy : %s\n' "${COCKPIT_ALLOWED_CIDR:-public}"
  printf 'Journal retention   : %s days\n' "$JOURNAL_RETENTION_DAYS"

  if [[ "${#UNAVAILABLE_PACKAGES[@]}" -gt 0 ]]; then
    warn "Unavailable packages: ${UNAVAILABLE_PACKAGES[*]}"
  fi

  if ! loginctl show-user "$ADMIN_USER" 2>/dev/null | grep -q 'Linger=yes'; then
    warn "Run this once for rootless Podman services: loginctl enable-linger ${ADMIN_USER}"
  fi

  log "Current journal disk usage: $(journalctl --disk-usage | sed 's/^Archived and active journals take up //')"
}

main() {
  require_root
  require_commands
  check_platform
  ensure_admin_user
  install_packages
  configure_selinux
  harden_ssh
  configure_firewalld
  configure_automatic_updates
  configure_cockpit_and_podman
  configure_intrusion_prevention
  configure_journald_retention
  print_summary
}

main "$@"
