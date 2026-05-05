# ver2.0

This is the clean Oracle Linux 10 setup layout.

## Structure

- `init-script.sh`: robust post-install bootstrap (OL10 checks, security, package availability checks, firewalld, Cockpit, updates, and log retention)
- `containers/`: Podman deployment scripts

## Step 1: run post-install script

```bash
cd ~/homelab.zap-vps/ver2.0
chmod +x init-script.sh

sudo ADMIN_USER=mgrsys \
  ADMIN_PUBKEY="ssh-ed25519 AAAA...your-key..." \
  SSH_PORT=22 \
  COCKPIT_ALLOWED_CIDR="YOUR.PUBLIC.IP/32" \
  ./init-script.sh
```

## Step 2: deploy containers

```bash
cd ~/homelab.zap-vps/ver2.0/containers
chmod +x *.sh
./container-cloudflare.sh

# Optional additional services
./container-code-server.sh
./container-gitea.sh
./container-overleaf.sh

# Verify Quadlet service generated and active
systemctl --user status cloudflare.service
systemctl --user cat cloudflare.service

# One-command fleet status and validation
./status-all.sh
./quadlet-doctor.sh

# Verify generated unit and keep it alive after logout
systemctl --user cat gitea.service
sudo loginctl enable-linger mgrsys
```

## Quadlet compatibility

- Container scripts in `containers/` now use native Quadlet units (`*.container`).
- Units are created in `~/.config/containers/systemd/`.
- Services are managed as `<name>.service` (for example `cloudflare.service`, `code-server.service`, `gitea.service`).
- Overleaf script creates 3 services: `overleaf.service`, `overleaf-mongo.service`, and `overleaf-redis.service`.

## What the init script now enforces

- Oracle Linux 10 compatibility checks (with warning when running elsewhere)
- Package availability detection before install
- Fail2ban install when available, automatic `sshguard` fallback otherwise
- SSH hardening with config validation (`sshd -t`)
- Firewalld baseline rules for SSH/Cockpit/HTTP(S)
- Automatic security updates (`dnf-automatic`)
- Journald retention policy to keep only the last 30 days:
  - `MaxRetentionSec=30day`
  - immediate `journalctl --vacuum-time=30d`
  - daily systemd timer (`journal-retention-check.timer`)
