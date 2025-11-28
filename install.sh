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
# Get all pools
POOLS=$(zpool list -H -o name)

# Try to find a pool that isn't the standard boot pool ('rpool' or 'bpool')
# If there is only one pool, use it. If there are two, pick the non-rpool one.
POOL_NAME=$(echo "$POOLS" | grep -vE "^(rpool|bpool)$" | head -n 1)

# Fallback: If filtering removed everything (e.g., only 'rpool' exists), just use the first one.
if [ -z "$POOL_NAME" ]; then
    POOL_NAME=$(echo "$POOLS" | head -n 1)
fi
HOST_NAME=$(hostname)

if [ -z "$POOL_NAME" ]; then
    echo "⚠️  No ZFS pool found! Creating config with placeholder."
    POOL_NAME="rpool"
fi

# Download Template
curl -sL https://raw.githubusercontent.com/cqdence/dentsys/master/dentsys.conf.template -o /etc/dentsys/dentsys.conf

# Apply Variables
sed -i "s/{{POOL}}/$POOL_NAME/g" /etc/dentsys/dentsys.conf
sed -i "s/{{HOSTNAME}}/$HOST_NAME/g" /etc/dentsys/dentsys.conf

echo "   Configured for Pool: $POOL_NAME"
echo "   Configured for Host: $HOST_NAME"

# 5. Setup Cron (Idempotent: won't add duplicates)
echo ">> Setting up Cron Jobs..."

# Define the jobs
SNAP_JOB="*/15 * * * * dentsys snap >> /var/log/dentsys.log 2>&1"
SEND_JOB="0 0 * * * dentsys send >> /var/log/dentsys.log 2>&1"

# Add PATH and Jobs if they don't exist
(crontab -l 2>/dev/null) | { cat; echo "PATH=/usr/sbin:/usr/bin:/sbin:/bin"; echo "$SNAP_JOB"; echo "$SEND_JOB"; } | sort | uniq | crontab -

echo "✅ Installation Complete! Run 'dentsys snap --verbose' to test."