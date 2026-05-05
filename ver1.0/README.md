# homelab.zap-vps

## Oracle Linux 10 first-step scripts

- `ol10-first-setup.sh`: hardens SSH, installs base packages, configures firewalld, and enables Cockpit.
- `podman-droplet-template.sh`: reusable rootless Podman deployment template with systemd user service generation.
- `container-cloudflare.sh`: deploys Cloudflare Tunnel with Podman secret and systemd user service.

Quick run:

```bash
cd ver1.0
chmod +x ol10-first-setup.sh podman-droplet-template.sh container-cloudflare.sh
```