#!/usr/bin/env bash
set -Eeuo pipefail

ADMIN_USER="${ADMIN_USER:-mgrsys}"
ADMIN_PUBKEY="${ADMIN_PUBKEY:-}"
SSH_PORT="${SSH_PORT:-22}"
ALLOW_ROOT_LOGIN="${ALLOW_ROOT_LOGIN:-no}"
ALLOW_PASSWORD_AUTH="${ALLOW_PASSWORD_AUTH:-no}"
COCKPIT_ALLOWED_CIDR="${COCKPIT_ALLOWED_CIDR:-}"
OPEN_WEB_PORTS="${OPEN_WEB_PORTS:-yes}"

PACKAGES=(
  nano
  htop
  btop
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
  podman
  podman-compose
  podman-plugins
  cockpit
  cockpit-podman
  cockpit-files
)

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

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "Run this script as root (sudo)."
  fi
}

check_platform() {
  if [[ ! -f /etc/os-release ]]; then
    fail "/etc/os-release not found. Unsupported system."
  fi

  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" != "ol" ]] || [[ "${VERSION_ID:-}" != "10"* ]]; then
    warn "This script was designed for Oracle Linux 10."
  fi
}

ensure_admin_user() {
  if ! id "${ADMIN_USER}" >/dev/null 2>&1; then
    log "Creating admin user ${ADMIN_USER}."
    useradd -m -G wheel -s /bin/bash "${ADMIN_USER}"
    passwd -l "${ADMIN_USER}" >/dev/null 2>&1 || true
  fi

  install -d -m 700 -o "${ADMIN_USER}" -g "${ADMIN_USER}" "/home/${ADMIN_USER}/.ssh"
  touch "/home/${ADMIN_USER}/.ssh/authorized_keys"
  chown "${ADMIN_USER}:${ADMIN_USER}" "/home/${ADMIN_USER}/.ssh/authorized_keys"
  chmod 600 "/home/${ADMIN_USER}/.ssh/authorized_keys"

  if [[ -n "${ADMIN_PUBKEY}" ]]; then
    if ! grep -Fq "${ADMIN_PUBKEY}" "/home/${ADMIN_USER}/.ssh/authorized_keys"; then
      log "Installing SSH public key for ${ADMIN_USER}."
      printf '%s\n' "${ADMIN_PUBKEY}" >> "/home/${ADMIN_USER}/.ssh/authorized_keys"
    fi
  fi

  if [[ "${ALLOW_PASSWORD_AUTH}" == "no" ]] && [[ ! -s "/home/${ADMIN_USER}/.ssh/authorized_keys" ]]; then
    fail "No SSH key found for ${ADMIN_USER}. Add ADMIN_PUBKEY or authorized_keys before disabling password auth."
  fi

  cat > "/etc/sudoers.d/${ADMIN_USER}" <<EOF
${ADMIN_USER} ALL=(ALL) NOPASSWD: ALL
EOF
  chmod 440 "/etc/sudoers.d/${ADMIN_USER}"

  visudo -c >/dev/null
}

install_packages() {
  log "Updating system packages."
  dnf -y update

  if ! rpm -q oracle-epel-release-el10 >/dev/null 2>&1; then
    log "Installing Oracle EPEL repository."
    dnf -y install oracle-epel-release-el10 || warn "EPEL repository package not installed."
  fi

  dnf -y makecache

  log "Installing required packages."
  dnf -y install "${PACKAGES[@]}"

  systemctl enable --now sshd
  systemctl enable --now firewalld
  systemctl enable --now cockpit.socket
}

harden_ssh() {
  local hardening_file="/etc/ssh/sshd_config.d/10-hardening.conf"

  log "Applying SSH hardening to ${hardening_file}."
  cat > "${hardening_file}" <<EOF
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
  systemctl reload sshd
}

configure_firewalld() {
  log "Configuring firewalld."

  if [[ "${SSH_PORT}" == "22" ]]; then
    firewall-cmd --permanent --add-service=ssh >/dev/null
  else
    firewall-cmd --permanent --remove-service=ssh >/dev/null || true
    firewall-cmd --permanent --add-port="${SSH_PORT}/tcp" >/dev/null
  fi

  if [[ -n "${COCKPIT_ALLOWED_CIDR}" ]]; then
    firewall-cmd --permanent --remove-service=cockpit >/dev/null || true
    firewall-cmd --permanent --remove-port=9090/tcp >/dev/null || true
    firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${COCKPIT_ALLOWED_CIDR} port port=9090 protocol=tcp accept" >/dev/null
  else
    warn "COCKPIT_ALLOWED_CIDR is empty. Cockpit (9090) will be open on the public zone."
    firewall-cmd --permanent --add-service=cockpit >/dev/null
  fi

  if [[ "${OPEN_WEB_PORTS}" == "yes" ]]; then
    firewall-cmd --permanent --add-service=http >/dev/null
    firewall-cmd --permanent --add-service=https >/dev/null
  fi

  firewall-cmd --reload >/dev/null
  firewall-cmd --list-all
}

post_checks() {
  log "Post-check summary:"
  printf '  - SSH config test: OK\n'
  printf '  - firewalld active: %s\n' "$(systemctl is-active firewalld)"
  printf '  - cockpit.socket active: %s\n' "$(systemctl is-active cockpit.socket)"

  if ! loginctl show-user "${ADMIN_USER}" 2>/dev/null | grep -q 'Linger=yes'; then
    warn "Enable user lingering for rootless Podman services: loginctl enable-linger ${ADMIN_USER}"
  fi

  printf '\nRecommended next step: run the script as %s user for rootless containers.\n' "${ADMIN_USER}"
}

main() {
  require_root
  check_platform
  ensure_admin_user
  install_packages
  harden_ssh
  configure_firewalld
  post_checks
}

main "$@"
