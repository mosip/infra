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

# Run the Ansible playbook
echo "=== Running Ansible Playbook ==="
ansible-playbook \
    -i "$INVENTORY_FILE" \
    -u ubuntu \
    --private-key="$SSH_KEY_FILE" \
    --ssh-common-args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' \
    -v \
    "$PLAYBOOK_FILE"

echo "=== Ansible RKE2 Installation Completed ==="
