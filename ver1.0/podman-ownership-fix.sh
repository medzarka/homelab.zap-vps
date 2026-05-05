#!/bin/bash

#────────────────────────────────────────────────────────────
# 🔧 PODMAN OWNERSHIP FIX - SYSTEMD TIMER SETUP
#────────────────────────────────────────────────────────────

set -e

echo "🔧 Setting up periodic Podman volume ownership fix..."

# Configuration
SERVICE_NAME="fix-podman-ownership"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"
TIMER_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.timer"
TARGET_DIR="$HOME/podman_data"
FREQUENCY="*:0/15"  # Every 30 minutes

# Create systemd user directory
echo "📁 Creating systemd user directory..."
mkdir -p "$HOME/.config/systemd/user"

# Create the service unit
echo "📝 Creating systemd service unit..."
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Fix Podman Volume Ownership
Documentation=https://docs.podman.io/
After=podman.socket

[Service]
Type=oneshot
ExecStart=/usr/bin/podman unshare chown -R 1000:1000 ${TARGET_DIR}
StandardOutput=journal
StandardError=journal
TimeoutSec=300
User=%i
EOF

# Create the timer unit
echo "⏰ Creating systemd timer unit..."
cat > "$TIMER_FILE" << EOF
[Unit]
Description=Fix Podman Volume Ownership Timer
Requires=${SERVICE_NAME}.service

[Timer]
OnCalendar=${FREQUENCY}
Persistent=true
RandomizedDelaySec=5m

[Install]
WantedBy=timers.target
EOF

# Reload systemd user daemon
echo "🔄 Reloading systemd user daemon..."
systemctl --user daemon-reload

# Enable and start the timer
echo "▶️ Enabling and starting timer..."
systemctl --user enable "${SERVICE_NAME}.timer"
systemctl --user start "${SERVICE_NAME}.timer"

# Run the service once immediately
echo "🚀 Running ownership fix immediately..."
systemctl --user start "${SERVICE_NAME}.service"

echo ""
echo "✅ Systemd timer setup complete!"
echo ""
echo "📊 Timer Status:"
systemctl --user status "${SERVICE_NAME}.timer" --no-pager -l
echo ""
echo "📊 Service Status:"
systemctl --user status "${SERVICE_NAME}.service" --no-pager -l
echo ""
echo "🔧 Management Commands:"
echo "  View timer status:   systemctl --user status ${SERVICE_NAME}.timer"
echo "  View service status: systemctl --user status ${SERVICE_NAME}.service"
echo "  View timer list:     systemctl --user list-timers ${SERVICE_NAME}.timer"
echo "  View logs:           journalctl --user -u ${SERVICE_NAME}.service"
echo "  Run manually:        systemctl --user start ${SERVICE_NAME}.service"
echo "  Stop timer:          systemctl --user stop ${SERVICE_NAME}.timer"
echo "  Disable timer:       systemctl --user disable ${SERVICE_NAME}.timer"
echo ""
echo "📅 Schedule: Runs every 30 minutes"
echo "📁 Target directory: ${TARGET_DIR}"
echo ""
echo "🎉 Your Podman volumes will now have ownership fixed automatically!"
