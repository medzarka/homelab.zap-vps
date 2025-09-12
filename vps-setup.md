# Oracle Linux Installation & Hardening Guide (BIOS / netboot.xyz)

## Overview

This guide describes installing **Oracle Linux 9** on a BIOS‑only server via [`netboot.xyz`](https://netboot.xyz), applying a secure baseline, creating the `mgrsys` admin account with password and SSH public key, enabling **Cockpit** with **Podman** and file sharing, switching to the **Unbreakable Enterprise Kernel (UEK)**, and optionally upgrading to **Oracle Linux 10** if the CPU supports the **x86‑64‑v3** baseline.

---

## 1. Prerequisites

- **Hardware**:
  - BIOS‑only boot (no UEFI)
  - Network connectivity to `boot.netboot.xyz` and `yum.oracle.com`
  - Target disk with ≥ 20 GB free space
  - CPU check for OL 10:  
    ```bash
    /lib64/ld-linux-x86-64.so.2 --help | grep x86-64-v
    ```
    If `x86-64-v3` shows `(supported, searched)`, you can upgrade to OL 10 later.
- **Inputs Required**:
  - `mgrsys` password
  - `mgrsys` SSH public key (one line: starts with `ssh-rsa` or `ssh-ed25519`)
- Optional: ULN account for kernel/support channels

---

## 2. Install OL 9 via netboot.xyz

1. Boot the server into **iPXE** shell.
2. Press `Ctrl‑B`, set network manually:
   ```text
   ifconf --manual
   set netX/ip <YOUR_IP>
   set netX/netmask <NETMASK>
   set netX/gateway <GATEWAY>
   set dns <DNS_IP>
   ifopen net0
   ```
3. Chainload netboot.xyz:
   ```text
   chain --autofree https://boot.netboot.xyz
   ```
4. In the menu:  
   **Linux → Oracle Linux → 9.x → Install**.
5. In the OL9 installer:
   - Partition in BIOS/MBR mode.
   - Create `/boot` and `/` on the OS disk
   - Set language, timezone, and root password.
   - Add initial non‑root user (can be `mgrsys` or temporary).

---

## 3. Post‑Install Secure Baseline

SSH into the server as `mgrsys` or the initial user, then:

```bash
# Update
sudo dnf -y update

# Install required packages
sudo dnf -y install firewalld policycoreutils-python-utils dnf-automatic cockpit cockpit-files cockpit-podman
# Enable SELinux enforcing
sudo sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
sudo setenforce 1

# Enable firewalld and limit ports
sudo systemctl enable --now firewalld
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-port=9090/tcp   # Cockpit
sudo firewall-cmd --reload

# Configure automatic security updates
sudo systemctl enable --now dnf-automatic.timer
sudo sed -ri 's/^apply_updates.*/apply_updates = yes/' /etc/dnf/automatic.conf
sudo systemctl restart dnf-automatic.timer
```

---

## 4. Create `mgrsys` Admin User & Harden SSH

This section creates the `mgrsys` administrator, sets up SSH key-based access, and then disables password and root login for enhanced security.

This section creates the `mgrsys` administrator, sets up SSH key-based access, and then disables password and root login for enhanced security.

# Create the 'mgrsys' user, add it to the 'wheel' group for sudo access

```bash
useradd -m -G wheel -s /bin/bash mgrsys
# Set a password for 'mgrsys' (required for sudo commands)
echo "Set a strong password for the 'mgrsys' user:"
passwd mgrsys

# Set up SSH directory and authorized_keys for key-based login
echo "Write you public ssh key to be authorized on this VPS:"
read YOUR_PUBLIC_KEY_HERE
mkdir -p /home/mgrsys/.ssh
echo "$YOUR_PUBLIC_KEY_HERE" > /home/mgrsys/.ssh/authorized_keys
# Set correct permissions for the .ssh directory and key file
chmod 700 /home/mgrsys/.ssh
chmod 600 /home/mgrsys/.ssh/authorized_keys
chown -R mgrsys:mgrsys /home/mgrsys/.ssh
echo "SSH key for 'mgrsys' has been added."
```
No we configure passwordless sudo for mgrsys

```bash
# Create sudoers file for mgrsys
sudo tee /etc/sudoers.d/mgrsys-nopasswd > /dev/null <<'EOF'
# Allow mgrsys to run any command without password
mgrsys ALL=(ALL) NOPASSWD: ALL
EOF

sudo chmod 440 /etc/sudoers.d/mgrsys-nopasswd

# Verify sudoers syntax
if sudo visudo -c; then
    echo "Passwordless sudo configured for mgrsys"
else
    echo "Sudoers configuration error"
    exit 1
fi
```

Now harden SSH Server Configuration:

```bash
# Backup original SSH config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
# Configure SSH for maximum security
sudo tee /etc/ssh/sshd_config.d/security-hardening.conf > /dev/null <<'EOF'
# Disable root login completely
PermitRootLogin no

# Disable password authentication (keys only)
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM no

# Disable empty passwords
PermitEmptyPasswords no

# Disable X11 forwarding
X11Forwarding no

# Maximum authentication attempts
MaxAuthTries 3

# Only allow mgrsys user
AllowUsers mgrsys
EOF

# Test SSH config and reload
if sudo sshd -t; then
    sudo systemctl reload sshd
    echo "SSH hardened successfully"
else
    echo "SSH config error - check /etc/ssh/sshd_config"
    exit 1
fi
```

Generate SSH keys for the `mgrsys` user:

```bash
# Generate SSH keys for mgrsys user without any prompts
sudo -u mgrsys ssh-keygen -t ed25519 -f /home/mgrsys/.ssh/id_ed25519 -q -N '' -C 'mgrsys@zap-vps'
```

---

## 5. Enable Cockpit + Podman

```bash
# Cockpit web console
sudo systemctl enable --now cockpit.socket

# Podman API socket for Cockpit integration
sudo systemctl enable --now podman.socket
```

Access Cockpit: <https://SERVER_IP:9090> (accept the self‑signed cert). Log in as `mgrsys`.

---

## 6. Switch to Unbreakable Enterprise Kernel (UEK) on OL 9 or OL 10

Oracle Linux ships with two kernel families:

- **RHCK** – Red Hat Compatible Kernel
- **UEK** – Unbreakable Enterprise Kernel, Oracle‑built and tuned for performance

On **Oracle Linux 10 (x86‑64‑v3 CPUs)**, the initial UEK release is **UEK 8** (`kernel-uek-6.12.x`).  
On **Oracle Linux 9**, the latest supported UEK is UEK 8.

### Install UEK on OL 10

1. Ensure you’re on OL 10 and have the BaseOS/AppStream repos enabled:
   ```bash
   cat /etc/os-release
   sudo dnf repolist
   ```

2. Enable the UEK repo (public yum) if not already:
   ```bash
   sudo dnf config-manager --set-enabled ol10_UEKR8 # (for OL10)
   sudo dnf config-manager --set-enabled ol9_UEKR8 # (for OL9)
   ```

3. Install the UEK package:
   ```bash
   sudo dnf install -y kernel-uek
   ```

4. Reboot into UEK:
   ```bash
   sudo systemctl reboot
   ```

5. Verify you’re running UEK:
   ```bash
   uname -r
   # Example on OL10: 6.12.0-100.28.2.el10uek.x86_64
   ```

> **Tip:** Use `sudo grubby --info=ALL | grep ^kernel` to list all installed kernels and `sudo grubby --set-default /boot/vmlinuz-<version>` to set UEK as default.

---

## 7. Optional: Upgrade to OL 10

Only if CPU supports `x86‑64‑v3`:

```bash
dnf -y install leapp-upgrade
sudo leapp preupgrade --enablerepo ol10_baseos_latest --enablerepo ol10_appstream --enablerepo ol10_appstream ol10_UEKR8
leapp upgrade --enablerepo ol10_baseos_latest --enablerepo ol10_appstream --enablerepo ol10_appstream ol10_UEKR8
reboot
```

After reboot, verify:
```bash
cat /etc/os-release
sudo dnf remove --oldinstallonly --setopt=installonly_limit=2 kernel # Remove old kernel
sudo dnf autoremove -y # Remove Unused Packages (Orphans)
sudo dnf clean all # Optional: Clean DNF Cache

```

Re‑check SELinux/firewalld/Cockpit after the upgrade.

---

## 8. Create a Swap File

We can define a 1GB swap file on Oracle Linux using a few terminal commands. This process involves creating an empty file, formatting it as a swap area, and then enabling it.


```bash
# Simple 1GB Swap File Creator with Cleanup
SWAPFILE="/swapfile"
SWAPSIZE="1G"

# Remove existing swap file

if [ -f "$SWAPFILE" ]; then
    echo "Removing existing swapfile..."
    sudo swapoff "$SWAPFILE" 2>/dev/null || true
    sudo rm -f "$SWAPFILE"
    sudo sed -i "\|$SWAPFILE|d" /etc/fstab 2>/dev/null || true
    echo "Old swapfile removed"
fi

# Create new swap file

echo "Creating $SWAPSIZE swapfile at $SWAPFILE..."
sudo fallocate -l "$SWAPSIZE" "$SWAPFILE"
sudo chmod 600 "$SWAPFILE"
sudo mkswap "$SWAPFILE"
sudo swapon "$SWAPFILE"
# Make persistent
if ! sudo grep -q "$SWAPFILE" /etc/fstab 2>/dev/null; then
    echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab
fi
echo "New swapfile created and enabled"

# Show result
echo -e "\nCurrent swap status:"
sudo swapon --show
free -h | grep -E "(Mem|Swap)"
```
The swap file is now fully configured and will persist across system reboots.

---

## 9. Add the Oracle Epel repository

```bash
echo "Installing Oracle EPEL repository..."
sudo dnf install oracle-epel-release-el9 -y

# 2. Update package cache
echo "Updating package cache..."
sudo dnf makecache
```

---

## 10. Install and configure Fail2ban


### a. Install Fail2ban packages

```bash
echo "Installing Fail2ban and related packages..."
sudo dnf install fail2ban fail2ban-firewalld fail2ban-systemd -y
```

### b. Create local configuration file (never edit jail.conf directly)

```bashecho "Creating local configuration file..."
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
```

### c. Configure SSH protection

```bash
echo "Configuring SSH protection..."
sudo tee -a /etc/fail2ban/jail.local > /dev/null <<'EOF'

# SSH Protection Configuration
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/secure
maxretry = 5
findtime = 10m
bantime = 1h
backend = systemd

EOF
```

### d. Configure Cockpit protection

```bash
echo "Creating Cockpit filter..."
sudo tee /etc/fail2ban/filter.d/cockpit.conf > /dev/null <<'EOF'
[Definition]
failregex = ^.*cockpit-ws.*: received invalid credentials from <HOST>.*$
            ^.*cockpit-ws.*: authentication failed from <HOST>.*$
            ^.*cockpit-ws.*: login failed from <HOST>.*$
            ^.*cockpit-ws.*: refused connection from <HOST>.*$

ignoreregex =
EOF
```

### e. Configure Cockpit protection

```bash
echo "Configuring Cockpit protection..."
sudo tee -a /etc/fail2ban/jail.local > /dev/null <<'EOF'

### Cockpit Protection Configuration
[cockpit]
enabled = true
port = 9090
filter = cockpit
logpath = /var/log/messages
maxretry = 3
findtime = 10m
bantime = 1h
backend = systemd

EOF
```

### f. Configure global settings (optional improvements)

```bash
echo "Updating global settings..."
sudo sed -i '/^bantime\s*=/c\bantime = 1h' /etc/fail2ban/jail.local
sudo sed -i '/^findtime\s*=/c\findtime = 10m' /etc/fail2ban/jail.local
sudo sed -i '/^maxretry\s*=/c\maxretry = 5' /etc/fail2ban/jail.local

# Add ignoreip for localhost (uncomment and modify if needed)
# sudo sed -i '/^#ignoreip = 127.0.0.1\/8/c\ignoreip = 127.0.0.1\/8 ::1' /etc/fail2ban/jail.local
```

### g. Enable and start fail2ban service, and wait for 2 seconds

```bash
echo "Starting and enabling Fail2ban service..."
sudo systemctl enable --now fail2ban
sleep 2
```

### h. Verify installation and configuration

```bash
echo "=== Verifying Fail2ban Installation ==="

# Check service status
echo "Checking service status..."
sudo systemctl status fail2ban --no-pager

# Check fail2ban version
echo -e "\nFail2ban version:"
fail2ban-client version

# Check active jails
echo -e "\nActive jails:"
sudo fail2ban-client status

# Check SSH jail status
echo -e "\nSSH jail status:"
sudo fail2ban-client status sshd 2>/dev/null || echo "SSH jail not yet active (will activate after first log entry)"

# Check Cockpit jail status
echo -e "\nCockpit jail status:"
sudo fail2ban-client status cockpit 2>/dev/null || echo "Cockpit jail not yet active (will activate after first log entry)"
```

### Important Commands

```bash
echo "View all jails:           sudo fail2ban-client status"
echo "View SSH jail:            sudo fail2ban-client status sshd"
echo "View Cockpit jail:        sudo fail2ban-client status cockpit"
echo "Monitor fail2ban logs:    sudo journalctl -u fail2ban -f"
echo "Test configuration:       sudo fail2ban-client -t"

echo -e "\n=== Manual Ban/Unban Commands ==="
echo "Ban IP manually:          sudo fail2ban-client set sshd banip <IP>"
echo "Unban IP:                 sudo fail2ban-client set sshd unbanip <IP>"
echo "Unban all IPs:            sudo fail2ban-client unban --all"
```

---

## 11. Configure backup with Rclone

### a. Install `rclone`
```bash
echo "Installing Fail2ban and related packages..."
sudo dnf install rclone -y
```
**Mandatory Requirements** 
1. Active account with supported cloud provider (Google Drive, Dropbox, AWS S3, etc.)
2. API credentials or authentication tokens configured
3. Sufficient cloud storage space for synchronized data

### b. Prepare backup script variables

```bash
CONFIG_FILE="/root/cloud-sync-config.txt"
SYNC_SCRIPT="/etc/cron.hourly/cloud-sync"
LOG_FILE="/var/log/cloud-sync.log"
sudo touch "$LOG_FILE"
sudo chmod 644 "$LOG_FILE"
```

### c. Create a basic configuration file

```bash
echo "Creating configuration file at $CONFIG_FILE..."
cat <<'EOF' | sudo tee "$CONFIG_FILE" >/dev/null
# Cloud Sync Configuration - Hourly Execution
# Format: LOCAL_PATH|REMOTE_PATH|SYNC_TYPE
# 
# SYNC_TYPES:
#   sync   - Make source and dest identical, modifying dest only
#   copy   - Copy files from source to dest, skipping identical files
#   move   - Move files from source to dest (deletes from source)
#   bisync - Make source and dest identical, deleting files in dest if not in source
#
# Examples (uncomment and modify as needed):
# /home/mgrsys/documents|mycloud:backup/documents|sync
# /var/log/important|mycloud:logs/server-logs|copy
# /opt/application-data|mycloud:backups/app-data|sync
# /etc/important-configs|mycloud:configs/system|copy
#
# Add your sync paths below:
# /path/to/local/folder|remote:path/to/folder|sync
EOF

sudo chmod 600 "$CONFIG_FILE"
```

### d. Create the main sync script

```bash
echo "Creating hourly sync script at $SYNC_SCRIPT..."

cat <<'EOF' | sudo tee "$SYNC_SCRIPT" >/dev/null
#!/bin/bash

# Cloud Sync - Hourly Execution Script with Automatic Bisync Resync

CONFIG_FILE="/root/cloud-sync-config.txt"
LOG_FILE="/var/log/cloud-sync.log"
LOCK_FILE="/var/run/cloud-sync.lock"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to perform bisync with resync check
check_and_bisync() {
    local local_path="$1"
    local remote_path="$2"
    local resync_flag="$remote_path/.resync"

    # Check if .resync exists on remote
    if rclone lsjson "$resync_flag" >/dev/null 2>&1; then
        log_message "INFO: Resync flag found, proceeding with normal bisync"
        if rclone bisync \
            --conflict-resolve newer \
            --recover \
            --resilient \
            --check-sync=false \
            --fast-list \
            --progress \
            --retries 2 \
            --timeout 30m \
            "$local_path" "$remote_path" 2>&1 | tee -a "$LOG_FILE"; then
            return 0
        else
            return 1
        fi
    else
        log_message "INFO: Resync flag not found, performing initial resync"
        if rclone bisync \
            --resync \
            --fast-list \
            --progress \
            --retries 2 \
            --timeout 30m \
            "$local_path" "$remote_path" 2>&1 | tee -a "$LOG_FILE"; then
            if rclone touch "$resync_flag"; then
                log_message "INFO: Resync flag created successfully"
                return 0
            else
                log_message "WARNING: Failed to create resync flag"
                return 0
            fi
        else
            return 1
        fi
    fi
}

# Prevent overlapping executions
if [[ -f "$LOCK_FILE" ]]; then
    log_message "SKIP: Another sync process is already running"
    exit 0
fi

# Create lock file
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# Validate rclone binary
if ! command -v rclone &> /dev/null; then
    log_message "ERROR: rclone not installed or not in PATH"
    exit 1
fi

# Validate config file
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_message "ERROR: Configuration file $CONFIG_FILE not found"
    exit 1
fi

# Check if config file has active entries
if ! grep -v '^#' "$CONFIG_FILE" | grep -v '^[[:space:]]*$' | grep -q '|'; then
    log_message "INFO: No active sync entries found in config"
    exit 0
fi

log_message "START: Hourly cloud synchronization"

# Counters
sync_count=0
error_count=0
skip_count=0

# Process config file
while IFS='|' read -r local_path remote_path sync_type || [[ -n "$local_path" ]]; do
    # Skip comments and empty lines
    [[ -z "$local_path" || "$local_path" =~ ^[[:space:]]*# ]] && continue

    # Trim whitespace
    local_path=$(echo "$local_path" | xargs)
    remote_path=$(echo "$remote_path" | xargs)
    sync_type=$(echo "$sync_type" | xargs)

    # Skip invalid entries
    if [[ -z "$local_path" || -z "$remote_path" ]]; then
        skip_count=$((skip_count + 1))
        continue
    fi

    # Default sync type
    [[ -z "$sync_type" ]] && sync_type="sync"

    # Validate sync type
    if [[ ! "$sync_type" =~ ^(bisync|sync|copy|move)$ ]]; then
        log_message "WARNING: Invalid sync type '$sync_type' for $local_path, skipping"
        skip_count=$((skip_count + 1))
        continue
    fi

    # Check local path
    if [[ ! -d "$local_path" && ! -f "$local_path" ]]; then
        log_message "WARNING: Local path '$local_path' does not exist, skipping"
        skip_count=$((skip_count + 1))
        continue
    fi

    # Execute appropriate command
    log_message "SYNC: $local_path -> $remote_path ($sync_type)"

    if [[ "$sync_type" == "bisync" ]]; then
        # Bidirectional sync
        if check_and_bisync "$local_path" "$remote_path"; then
            log_message "SUCCESS: Bidirectional sync $local_path"
            sync_count=$((sync_count + 1))
        else
            log_message "ERROR: Failed bidirectional sync $local_path"
            error_count=$((error_count + 1))
        fi

    elif [[ "$sync_type" == "sync" ]]; then
        # One-way sync
        if rclone sync \
            --fast-list \
            --checkers 4 \
            --transfers 2 \
            --update \
            --log-level INFO \
            --retries 2 \
            --timeout 30m \
            "$local_path" "$remote_path" 2>&1 | tee -a "$LOG_FILE"; then

            log_message "SUCCESS: Synced $local_path"
            sync_count=$((sync_count + 1))
        else
            log_message "ERROR: Failed to sync $local_path"
            error_count=$((error_count + 1))
        fi

    elif [[ "$sync_type" == "copy" ]]; then
        # Copy (one-way, no deletions)
        if rclone copy \
            --fast-list \
            --checkers 4 \
            --transfers 2 \
            --update \
            --log-level INFO \
            --retries 2 \
            --timeout 30m \
            "$local_path" "$remote_path" 2>&1 | tee -a "$LOG_FILE"; then

            log_message "SUCCESS: Copied $local_path"
            sync_count=$((sync_count + 1))
        else
            log_message "ERROR: Failed to copy $local_path"
            error_count=$((error_count + 1))
        fi

    elif [[ "$sync_type" == "move" ]]; then
        # Move (one-way with source deletion)
        if rclone move \
            --fast-list \
            --checkers 4 \
            --transfers 2 \
            --update \
            --log-level INFO \
            --retries 2 \
            --timeout 30m \
            "$local_path" "$remote_path" 2>&1 | tee -a "$LOG_FILE"; then

            log_message "SUCCESS: Moved $local_path"
            sync_count=$((sync_count + 1))
        else
            log_message "ERROR: Failed to move $local_path"
            error_count=$((error_count + 1))
        fi

    else
        log_message "WARNING: Unknown sync type '$sync_type' for $local_path, skipping"
        skip_count=$((skip_count + 1))
    fi

done < "$CONFIG_FILE"

log_message "COMPLETE: Synced=$sync_count, Errors=$error_count, Skipped=$skip_count"

# Rotate log if too large
if [[ -f "$LOG_FILE" ]] && [[ $(wc -l < "$LOG_FILE" 2>/dev/null || echo 0) -gt 500 ]]; then
    tail -500 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    log_message "INFO: Log file rotated"
fi

exit $([[ $error_count -gt 0 ]] && echo 1 || echo 0)
EOF


sudo chmod +x "$SYNC_SCRIPT"
echo "Hourly sync script created at $SYNC_SCRIPT"
```
### e. Activate cron service 

```bash
echo "Checking cron service..."    
if systemctl is-active --quiet crond; then
   echo "Cron service is running"
else
   echo "Starting cron service..."
   systemctl enable --now crond
   echo "Cron service started"
fi
```

### f. Create a Function for management commands

```bash
echo "Creating management commands..."
    
cat <<'EOF' | sudo tee "/usr/local/sbin/cloud-sync-manage" >/dev/null
#!/bin/bash

# Cloud Sync Management Script

CONFIG_FILE="/root/cloud-sync-config.txt"
LOG_FILE="/var/log/cloud-sync.log"
SYNC_SCRIPT="/etc/cron.hourly/cloud-sync"

case "${1:-help}" in
    "status")
        echo "=== Cloud Sync Status ==="
        if [[ -f "/var/run/cloud-sync.lock" ]]; then
            echo "Status: RUNNING (PID: $(cat /var/run/cloud-sync.lock 2>/dev/null || echo 'unknown'))"
        else
            echo "Status: IDLE"
        fi
        
        if [[ -f "$LOG_FILE" ]]; then
            echo "Last run: $(tail -1 "$LOG_FILE" 2>/dev/null | cut -d' ' -f1-2)"
            echo "Recent activity:"
            tail -5 "$LOG_FILE" 2>/dev/null | sed 's/^/  /'
        fi
        ;;
        
    "config")
        echo "=== Current Configuration ==="
        if [[ -f "$CONFIG_FILE" ]]; then
            grep -v '^#' "$CONFIG_FILE" | grep -v '^[[:space:]]*$' || echo "No active sync paths configured"
        else
            echo "Configuration file not found"
        fi
        ;;
        
    "logs")
        echo "=== Recent Sync Logs ==="
        if [[ -f "$LOG_FILE" ]]; then
            tail -20 "$LOG_FILE"
        else
            echo "No log file found"
        fi
        ;;
        
    "test")
        echo "=== Testing Sync Configuration ==="
        if [[ -x "$SYNC_SCRIPT" ]]; then
            echo "Running sync script manually..."
            "$SYNC_SCRIPT"
        else
            echo "Sync script not found or not executable"
        fi
        ;;
        
    "edit")
        echo "Opening configuration file for editing..."
        ${EDITOR:-nano} "$CONFIG_FILE"
        ;;
        
    "help"|*)
        echo "Cloud Sync Management Commands:"
        echo "  cloud-sync-manage status  - Show current status"
        echo "  cloud-sync-manage config  - Show active configuration"
        echo "  cloud-sync-manage logs    - Show recent logs"
        echo "  cloud-sync-manage test    - Run sync manually"
        echo "  cloud-sync-manage edit    - Edit configuration"
        ;;
esac
EOF
    
sudo chmod +x "/usr/local/sbin/cloud-sync-manage"
echo "Management commands created: cloud-sync-manage"
```

### g. Manage the backup


Next steps:

1. Edit the configuration file to add your sync paths:"

   ```bash
   nano $CONFIG_FILE
   ```
2. Test the setup:"

   ```bash
   cloud-sync-manage test
   ```

3.Monitor execution:
   
   ```bash
   cloud-sync-manage logs
   cloud-sync-manage status
   ```

The sync will run automatically every hour via /etc/cron.hourly/"

---

## 12. Configure password rotation

### a. Create secure password storage directory

```bash
sudo mkdir -p /root/.zap-vps-pwd
sudo chmod 700 /root/.zap-vps-pwd
```

### b. Create password update script and set Proper Permissions

```bash
echo "Creating password update script..."
sudo tee /etc/cron.daily/rotate-passwords > /dev/null <<'EOF'
#!/bin/bash

# Function to update user password and store history
update_user_password() {
    local user="$1"
    local password_dir="/root/.zap-vps-pwd"
    local date_stamp=$(date +%Y-%m-%d)
    
    # Generate secure random password (32 characters)
    local new_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    
    # Store password with timestamp
    echo "${new_password}" | sudo tee "${password_dir}/${user}_${date_stamp}.pwd" > /dev/null
    sudo chmod 600 "${password_dir}/${user}_${date_stamp}.pwd"
    
    # Keep only last 7 password files for this user
    sudo find "${password_dir}" -name "${user}_*.pwd" -type f | \
        sort -r | tail -n +8 | sudo xargs rm -f
    
    # Update user password
    echo "${user}:${new_password}" | sudo chpasswd
    
    # Log the update (without password)
    echo "$(date): Password updated for user ${user}" | \
        sudo tee -a "${password_dir}/rotation.log" > /dev/null
    
    echo "Password updated for ${user}"
}

# Update both users
update_user_password "root"
update_user_password "mgrsys"

# Set secure permissions on the entire directory
sudo chown -R root:root /root/.zap-vps-pwd
sudo chmod 700 /root/.zap-vps-pwd
sudo chmod 600 /root/.zap-vps-pwd/*
EOF

sudo chmod +x /etc/cron.daily/rotate-passwords
sudo chown root:root /etc/cron.daily/rotate-passwords
```

### c. Run initial password rotation

```bash
sudo /etc/cron.daily/rotate-passwords
```

### d. Test the Setup

```bash
sudo run-parts --test /etc/cron.daily/
sudo run-parts /etc/cron.daily/
```

### e. Ensure cron service is running

```bash
sudo systemctl enable --now crond
```

### f. Configure Rotating passwords for remote backup

```bash
SERVER_NAME="ZAP-VPS"
# Create remote folders | change ZAP-VPS to any other server
rclone mkdir dropbox:HOMELAB/${SERVER_NAME}/BACKUP/root/.zap-vps-pwd

# add the rotating passwords to the backup config
sudo tee -a /root/cloud-sync-config.txt <<EOF > /dev/null
/root/.zap-vps-pwd|dropbox:HOMELAB/${SERVER_NAME}/BACKUP/root/.zap-vps-pwd|sync
EOF
```

---

## 13. Configure `nano` as default editor

```bash
# Install nano editor
sudo dnf update -y
sudo dnf install -y nano

# Create system-wide configuration
sudo tee /etc/profile.d/nano-editor.sh > /dev/null << 'EOF'
export VISUAL=nano
export EDITOR=nano
EOF

# Make it executable
sudo chmod +x /etc/profile.d/nano-editor.sh

# Apply changes (logout/login required for full effect)
source /etc/profile.d/nano-editor.sh
```

---

## 14. `journald` config: to limit log usage 

```bash
sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/99-custom-limits.conf <<EOF > /dev/null
[Journal]
SystemMaxUse=128M
MaxFileSec=7day
EOF
sudo systemctl restart systemd-journald
sudo journalctl --disk-usage
```
---

## 15. Mirror the ssh keys


```bash
SERVER_NAME="ZAP-VPS"
# Create remote folders
sudo rclone mkdir dropbox:HOMELAB/${SERVER_NAME}/BACKUP/home/mgrsys/.ssh

# add the rotating passwords to the backup config
sudo tee -a /root/cloud-sync-config.txt <<EOF > /dev/null
/home/mgrsys/.ssh|dropbox:HOMELAB/${SERVER_NAME}/BACKUP/home/mgrsys/.ssh|bisync
EOF
```

## 16. Add the `netboot.xyz` network bootloader


### A. Part one: Download

This script detects the system architecture (x86_64 or ARM) and boot mode (UEFI or BIOS) to download the appropriate iPXE bootloader for `netboot.xyz`.

```bash
#!/bin/bash
set -euo pipefail

# --- Configuration ---
# The destination directory for the bootloader files.
# NOTE: This script requires sudo to write to this directory.
DEST_DIR="/boot/efi/netboot.xyz"
BASE_URL="https://boot.netboot.xyz"

# --- Main Logic ---

echo "--- Netboot.xyz Downloader ---"

# Check for root/sudo privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo."
   exit 1
fi

# Determine system architecture
ARCH=$(uname -m)
echo "Detected architecture: ${ARCH}"

# Determine boot mode (UEFI or BIOS)
IS_UEFI=false
if [ -d "/sys/firmware/efi" ]; then
    IS_UEFI=true
    echo "Detected boot mode: UEFI"
else
    echo "Detected boot mode: BIOS/Legacy"
fi

# Select the correct file based on architecture and boot mode
FILENAME=""
if [[ "${ARCH}" == "x86_64" ]]; then
    if [[ "${IS_UEFI}" == true ]]; then
        FILENAME="netboot.xyz.efi"
    else
        FILENAME="netboot.xyz.kpxe"
        echo "Warning: For BIOS systems, this file is usually placed in /boot for GRUB chainloading, not /boot/efi."
    fi
elif [[ "${ARCH}" == "aarch64" || "${ARCH}" == "arm64" ]]; then
    if [[ "${IS_UEFI}" == true ]]; then
        FILENAME="netboot.xyz-arm64.efi"
    else
        echo "Error: ARM system detected without a UEFI environment. This is an unsupported configuration."
        exit 1
    fi
else
    echo "Error: Unsupported architecture '${ARCH}'."
    exit 1
fi

# Download the file
echo "Downloading ${FILENAME} for ${ARCH}..."
mkdir -p "${DEST_DIR}"
if curl -L -o "${DEST_DIR}/${FILENAME}" "${BASE_URL}/${FILENAME}"; then
    echo "✅ Download complete. File saved to: ${DEST_DIR}/${FILENAME}"
else
    echo "❌ Download failed. Please check your network connection."
    exit 1
fi

echo "---"
echo "Next steps: To make this a boot option, you may need to configure your bootloader (e.g., GRUB, systemd-boot) to chainload the downloaded file."
```
### B. Part two: GRUB Configuration 

```bash
echo -e "\n--- 2. GRUB Configuration ---"

# BIOS/Legacy Configuration
if [[ "${IS_UEFI}" == false ]]; then
    echo "Configuring GRUB for BIOS/Legacy system..."
    
    # Define file paths
    BIOS_FILE="/boot/netboot.xyz.kpxe"
    DOWNLOADED_FILE="${DEST_DIR}/netboot.xyz.kpxe"

    # Move bootloader to /boot
    echo "Moving bootloader to /boot..."
    mv "${DOWNLOADED_FILE}" "${BIOS_FILE}"

    # Check if menu entry already exists
    if grep -q "netboot.xyz.kpxe" "${GRUB_CUSTOM_FILE}"; then
        echo "GRUB menu entry already exists. Skipping add."
    else
        echo "Adding GRUB menu entry..."
        tee -a "${GRUB_CUSTOM_FILE}" > /dev/null <<'EOF'

menuentry "Network Boot (netboot.xyz)" {
    linux16 /boot/netboot.xyz.kpxe
}
EOF
    fi

    # Update GRUB configuration
    GRUB_CFG_PATH="/boot/grub2/grub.cfg"
    echo "Updating GRUB configuration at ${GRUB_CFG_PATH}..."
    if grub2-mkconfig -o "${GRUB_CFG_PATH}"; then
        echo "✅ GRUB for BIOS updated successfully."
    else
        echo "❌ Failed to update GRUB. Please check for errors."
        exit 1
    fi

# UEFI Configuration
else
    echo "Configuring GRUB for UEFI system..."

    # The FILENAME variable is already set from the download section.
    UEFI_FILE_PATH="/efi/netboot.xyz/${FILENAME}"

    # Check if menu entry already exists
    if grep -q "${FILENAME}" "${GRUB_CUSTOM_FILE}"; then
        echo "GRUB menu entry already exists. Skipping add."
    else
        echo "Adding GRUB menu entry..."
        # Note: The 'chainloader' path is relative to the ESP root, which is /boot/efi for GRUB.
        tee -a "${GRUB_CUSTOM_FILE}" > /dev/null <<EOF
menuentry "Network Boot (netboot.xyz) - UEFI" {
    chainloader ${UEFI_FILE_PATH}
}
EOF
    fi

    # Update GRUB configuration for UEFI (path is specific to Oracle Linux)
    GRUB_CFG_PATH="/boot/efi/EFI/ol/grub.cfg"
    if [ ! -f "${GRUB_CFG_PATH}" ]; then
        echo "Warning: Standard Oracle Linux GRUB path not found. This might not be OL."
        echo "Attempting a common fallback path..."
        GRUB_CFG_PATH="/boot/grub2/grub.cfg" # A common fallback
    fi
    
    echo "Updating GRUB configuration at ${GRUB_CFG_PATH}..."
    if grub2-mkconfig -o "${GRUB_CFG_PATH}"; then
        echo "✅ GRUB for UEFI updated successfully."
    else
        echo "❌ Failed to update GRUB. The path ${GRUB_CFG_PATH} might be incorrect for your system."
        exit 1
    fi
fi

echo -e "\n---"
echo "🎉 All done! Reboot your server to see the new 'Network Boot (netboot.xyz)' option in GRUB."
```



### TODO

- GENERIC SERVER NAME
- CENTRALIZED RCLONE MODEL NAME