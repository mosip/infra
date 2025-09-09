#!/bin/bash

set -e

# Script to run Ansible playbook for RKE2 installation
# This script is called by Terraform's local-exec provisioner

ANSIBLE_DIR="$1"
INVENTORY_FILE="$2"
SSH_KEY_FILE="$3"
PLAYBOOK_FILE="$4"

echo "=== Starting Ansible RKE2 Installation ==="
echo "Ansible Directory: $ANSIBLE_DIR"
echo "Inventory File: $INVENTORY_FILE"
echo "SSH Key File: $SSH_KEY_FILE"
echo "Playbook File: $PLAYBOOK_FILE"

cd "$ANSIBLE_DIR"

# Check if ansible is installed
if ! command -v ansible-playbook &> /dev/null; then
    echo "🔧 Ansible not found. Installing Ansible..."
    
    # Try different package managers
    if command -v apt-get &> /dev/null; then
        echo "📦 Using apt-get (Ubuntu/Debian)..."
        sudo apt-get update -qq
        sudo apt-get install -y ansible python3-pip
    elif command -v yum &> /dev/null; then
        echo "📦 Using yum (RHEL/CentOS)..."
        sudo yum install -y epel-release
        sudo yum install -y ansible python3-pip
    elif command -v dnf &> /dev/null; then
        echo "📦 Using dnf (Fedora)..."
        sudo dnf install -y ansible python3-pip
    elif command -v zypper &> /dev/null; then
        echo "📦 Using zypper (openSUSE)..."
        sudo zypper install -y ansible python3-pip
    elif command -v brew &> /dev/null; then
        echo "📦 Using brew (macOS)..."
        brew install ansible
    elif command -v pip3 &> /dev/null; then
        echo "📦 Using pip3 (fallback)..."
        pip3 install --user ansible
        # Add to PATH if needed
        export PATH="$HOME/.local/bin:$PATH"
    else
        echo "❌ ERROR: No suitable package manager found!"
        echo "Please install Ansible manually:"
        echo "  Ubuntu/Debian: sudo apt-get install ansible"
        echo "  RHEL/CentOS:   sudo yum install ansible"
        echo "  macOS:         brew install ansible"
        echo "  pip:           pip3 install ansible"
        exit 1
    fi
    
    # Verify installation
    if command -v ansible-playbook &> /dev/null; then
        echo "✅ Ansible installation successful!"
        ansible-playbook --version | head -1
    else
        echo "❌ Ansible installation failed!"
        exit 1
    fi
else
    echo "✅ Ansible found:"
    ansible-playbook --version | head -1
fi

# Set proper permissions for SSH key
chmod 600 "$SSH_KEY_FILE"

# Run the Ansible playbook with maximum debugging for GitHub Actions
echo "=== 🚀 ANSIBLE RKE2 INSTALLATION STARTING ==="
echo "GitHub Actions Environment Detected"
echo "Time: $(date)"
echo "=============================================="

echo ""
echo "📋 INVENTORY CONTENTS:"
echo "====================="
cat "$INVENTORY_FILE"
echo ""

echo "🔑 SSH KEY PERMISSIONS:"
echo "======================"
ls -la "$SSH_KEY_FILE"
echo ""

echo "🌐 NETWORK CONNECTIVITY TEST:"
echo "============================="
# Test connectivity to nodes before starting
CLUSTER_IPS=$(grep -oP 'ansible_host=\K[0-9.]+' "$INVENTORY_FILE" || true)
for ip in $CLUSTER_IPS; do
    echo -n "Testing SSH to $ip: "
    if timeout 10 nc -z "$ip" 22 2>/dev/null; then
        echo "✅ REACHABLE"
    else
        echo "❌ UNREACHABLE (may still be starting)"
    fi
done
echo ""

echo "🎯 ANSIBLE ENVIRONMENT SETUP:"
echo "============================="
# Set comprehensive logging environment variables optimized for CI/CD
export ANSIBLE_DEBUG=True
export ANSIBLE_VERBOSE_TO_STDERR=True
export ANSIBLE_DISPLAY_SKIPPED_HOSTS=True
export ANSIBLE_DISPLAY_OK_HOSTS=True
export ANSIBLE_DISPLAY_FAILED_STDERR=True
export ANSIBLE_STDOUT_CALLBACK=yaml
export ANSIBLE_CALLBACK_WHITELIST=profile_tasks,timer
export ANSIBLE_FORCE_COLOR=True
export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_SSH_RETRIES=3
export ANSIBLE_TIMEOUT=30

echo "Ansible Version:"
ansible-playbook --version
echo ""

echo "🔥 STARTING PLAYBOOK EXECUTION WITH FULL DEBUGGING:"
echo "=================================================="
echo "This will show every step, task, and connection detail..."
echo ""

# Create a unique log file with timestamp for GitHub Actions
LOG_FILE="/tmp/ansible-rke2-$(date +%Y%m%d-%H%M%S).log"

ansible-playbook \
    -i "$INVENTORY_FILE" \
    -u ubuntu \
    --private-key="$SSH_KEY_FILE" \
    --ssh-common-args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o ConnectTimeout=30' \
    -vvvv \
    --diff \
    --timeout=600 \
    "$PLAYBOOK_FILE" 2>&1 | tee "$LOG_FILE"

ANSIBLE_EXIT_CODE=${PIPESTATUS[0]}

echo ""
echo "=== 🏁 ANSIBLE RKE2 INSTALLATION COMPLETED ==="
echo "=============================================="
echo "Exit Code: $ANSIBLE_EXIT_CODE"
echo "Completion Time: $(date)"
echo "Full debug log saved to: $LOG_FILE"

if [ $ANSIBLE_EXIT_CODE -eq 0 ]; then
    echo "✅ SUCCESS: RKE2 cluster installation completed successfully!"
else
    echo "❌ FAILED: RKE2 cluster installation failed with exit code $ANSIBLE_EXIT_CODE"
    echo ""
    echo "🔍 LAST 50 LINES OF DEBUG LOG:"
    echo "=============================="
    tail -50 "$LOG_FILE"
fi

exit $ANSIBLE_EXIT_CODE
