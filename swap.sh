#!/bin/bash

SWAP_FILE="/swapfile"

echo "======================================"
echo "        Swap Creation Script"
echo "======================================"

# Check if swap already exists
if swapon --show | grep -q "$SWAP_FILE"; then
    echo "Swap already exists at $SWAP_FILE"
    swapon --show
    exit 0
fi

# Ask user for swap size
read -p "Enter swap size (Example: 2G, 4G, 8G): " SWAP_SIZE

if [[ -z "$SWAP_SIZE" ]]; then
    echo "Invalid input. Exiting..."
    exit 1
fi

echo "Creating $SWAP_SIZE swap file..."

# Create swap file
if command -v fallocate >/dev/null 2>&1; then
    fallocate -l $SWAP_SIZE $SWAP_FILE
else
    SIZE_MB=$(echo $SWAP_SIZE | sed 's/G//' )
    SIZE_MB=$((SIZE_MB * 1024))
    dd if=/dev/zero of=$SWAP_FILE bs=1M count=$SIZE_MB
fi

# Set permissions
chmod 600 $SWAP_FILE

# Make swap
mkswap $SWAP_FILE

# Enable swap
swapon $SWAP_FILE

# Add to fstab if not already added
if ! grep -q "$SWAP_FILE" /etc/fstab; then
    echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
fi

# Optimize swappiness
sysctl vm.swappiness=10
if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
    echo "vm.swappiness=10" >> /etc/sysctl.conf
fi

echo "======================================"
echo "Swap successfully created!"
echo "======================================"
free -h
swapon --show
