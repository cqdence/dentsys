#!/bin/bash
set -e

echo "🚀 Starting Dentsys Automation..."

# 1. Install Dependencies
echo ">> Installing system tools..."
apt-get update -qq
apt-get install -y pipx git lz4 zstd zfsutils-linux
pipx ensurepath

# 2. Install the Tool (Force update)
echo ">> Installing Dentsys software..."
pipx install --force git+https://github.com/cqdence/dentsys.git

# 3. Link Binary
ln -sf /root/.local/bin/dentsys /usr/local/bin/dentsys

# 4. Configure /etc/dentsys
echo ">> Generating Configuration..."
mkdir -p /etc/dentsys

# Detect System Info
HOST_NAME=$(hostname)

# Get all pools
if ! POOLS=$(zpool list -H -o name 2>/dev/null); then
    echo "❌ ERROR: ZFS is not available or no pools found!"
    echo "   Please ensure ZFS is installed and at least one pool exists."
    exit 1
fi

# Try to find a pool that isn't the standard boot pool ('rpool' or 'bpool')
POOL_NAME=$(echo "$POOLS" | grep -vE "^(rpool|bpool)$" | head -n 1)

# Fallback: If filtering removed everything (e.g., only 'rpool' exists), just use the first one.
if [ -z "$POOL_NAME" ]; then
    POOL_NAME=$(echo "$POOLS" | head -n 1)
fi

echo "   Detected ZFS pool: $POOL_NAME"

# Smart dataset detection - find the best dataset to snapshot
echo ">> Detecting datasets..."
DATASET=""

# Strategy 1: Look for {POOL}/data (common on Proxmox)
if zfs list "${POOL_NAME}/data" >/dev/null 2>&1; then
    DATASET="${POOL_NAME}/data"
    echo "   Found dataset: ${DATASET}"
# Strategy 2: Look for common Proxmox patterns
elif zfs list "${POOL_NAME}/ROOT" >/dev/null 2>&1; then
    # Skip ROOT for boot, look for data storage
    if zfs list "${POOL_NAME}/vm-data" >/dev/null 2>&1; then
        DATASET="${POOL_NAME}/vm-data"
        echo "   Found dataset: ${DATASET}"
    elif zfs list "${POOL_NAME}/subvol-100-disk-0" >/dev/null 2>&1; then
        # Has VMs but no dedicated data pool, use root pool
        DATASET="${POOL_NAME}"
        echo "   Found dataset: ${DATASET} (pool root)"
    fi
# Strategy 3: Use the pool root if it has direct filesystems
elif zfs list -H -r -d 1 -t filesystem "${POOL_NAME}" | grep -v "^${POOL_NAME}$" >/dev/null 2>&1; then
    DATASET="${POOL_NAME}"
    echo "   Using pool root: ${DATASET}"
else
    DATASET="${POOL_NAME}"
    echo "   Using pool root: ${DATASET}"
fi

# Allow override via environment variable
if [ -n "$DENTSYS_DATASET" ]; then
    echo "   Override detected: Using $DENTSYS_DATASET"
    DATASET="$DENTSYS_DATASET"
    # Validate override exists
    if ! zfs list "$DATASET" >/dev/null 2>&1; then
        echo "❌ ERROR: Override dataset '$DATASET' does not exist!"
        exit 1
    fi
fi

# Final validation
if [ -z "$DATASET" ]; then
    echo "❌ ERROR: Could not determine dataset to snapshot!"
    echo "   Set DENTSYS_DATASET environment variable to specify manually."
    echo "   Example: DENTSYS_DATASET=tank/mydata bash install.sh"
    exit 1
fi

echo ""
echo "📋 Configuration Summary:"
echo "   Hostname: $HOST_NAME"
echo "   ZFS Pool: $POOL_NAME"
echo "   Dataset:  $DATASET"
echo ""

# Download Template (FIXED: correct path with pyznap/ prefix)
echo ">> Downloading configuration template..."
if ! curl -fsSL https://raw.githubusercontent.com/cqdence/dentsys/master/pyznap/dentsys.conf.template -o /etc/dentsys/dentsys.conf; then
    echo "❌ ERROR: Failed to download configuration template!"
    echo "   Check internet connection and GitHub availability."
    exit 1
fi

# Verify downloaded file is valid INI format
if ! grep -q "^\[" /etc/dentsys/dentsys.conf; then
    echo "❌ ERROR: Downloaded config is not valid INI format!"
    echo "   This usually means GitHub returned an error page."
    exit 1
fi

# Apply Variables
sed -i "s/{{POOL}}/$POOL_NAME/g" /etc/dentsys/dentsys.conf
sed -i "s/{{HOSTNAME}}/$HOST_NAME/g" /etc/dentsys/dentsys.conf

# Update the dataset section in the config
sed -i "s|\[${POOL_NAME}/data\]|[${DATASET}]|g" /etc/dentsys/dentsys.conf

echo "   ✅ Configuration written to /etc/dentsys/dentsys.conf"

# Validate that the dataset exists in ZFS
if ! zfs list "$DATASET" >/dev/null 2>&1; then
    echo "⚠️  WARNING: Dataset '$DATASET' does not exist in ZFS!"
    echo "   Snapshots will fail until this dataset is created."
    echo "   Create it with: zfs create $DATASET"
fi

# 5. Create log file with proper permissions
echo ">> Setting up logging..."
touch /var/log/dentsys.log
chmod 644 /var/log/dentsys.log

# Setup logrotate
cat > /etc/logrotate.d/dentsys <<'LOGROTATE_EOF'
/var/log/dentsys.log {
    weekly
    rotate 12
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
LOGROTATE_EOF

echo "   ✅ Log rotation configured"

# 6. Setup Cron (FIXED: proper deduplication)
echo ">> Setting up Cron Jobs..."

# Define the jobs
SNAP_JOB="*/15 * * * * dentsys snap >> /var/log/dentsys.log 2>&1"
SEND_JOB="0 0 * * * dentsys send >> /var/log/dentsys.log 2>&1"
PATH_LINE="PATH=/usr/sbin:/usr/bin:/sbin:/bin"

# Get current crontab, removing any existing dentsys entries
CURRENT_CRON=$(crontab -l 2>/dev/null || true)
NEW_CRON=$(echo "$CURRENT_CRON" | grep -v "dentsys snap" | grep -v "dentsys send" || true)

# Add PATH if not already present
if ! echo "$NEW_CRON" | grep -q "^PATH="; then
    NEW_CRON="${PATH_LINE}
${NEW_CRON}"
fi

# Add the jobs
NEW_CRON="${NEW_CRON}
${SNAP_JOB}
${SEND_JOB}"

# Install new crontab
echo "$NEW_CRON" | crontab -

echo "   ✅ Cron jobs installed"

# 7. Final validation
echo ""
echo ">> Running validation checks..."

# Test that dentsys binary is accessible
if ! command -v dentsys >/dev/null 2>&1; then
    echo "⚠️  WARNING: 'dentsys' command not found in PATH"
    echo "   You may need to logout and login again for PATH to update"
fi

# Test configuration parsing
if dentsys snap --help >/dev/null 2>&1; then
    echo "   ✅ Dentsys binary is working"
else
    echo "⚠️  WARNING: Dentsys binary test failed"
fi

# Check if dataset has any existing snapshots
SNAP_COUNT=$(zfs list -t snapshot -H -o name -d 1 "$DATASET" 2>/dev/null | wc -l || echo "0")
echo "   ℹ️  Current snapshots on ${DATASET}: ${SNAP_COUNT}"

echo ""
echo "✅ Installation Complete!"
echo ""
echo "📝 Next steps:"
echo "   1. Review config: cat /etc/dentsys/dentsys.conf"
echo "   2. Test snapshot:  dentsys snap --verbose"
echo "   3. Check logs:     tail -f /var/log/dentsys.log"
echo "   4. View cron:      crontab -l"
echo ""
echo "   To configure remote backups, edit /etc/dentsys/dentsys.conf"
echo "   and uncomment the 'dest' line with your backup server details."
echo ""