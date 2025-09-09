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
echo "📍 Extracting IPs from inventory file..."
CLUSTER_IPS=$(grep -oP 'ansible_host=\K[0-9.]+' "$INVENTORY_FILE" || true)
echo "📋 Found IPs: $CLUSTER_IPS"
FAILED_NODES=0

if [ -z "$CLUSTER_IPS" ]; then
    echo "⚠️  WARNING: No IPs found in inventory file!"
    echo "   Inventory file might have different format"
else
    echo "🔍 Testing connectivity to $(echo $CLUSTER_IPS | wc -w) nodes..."
    
    for ip in $CLUSTER_IPS; do
        echo -n "Testing SSH to $ip: "
        if timeout 10 nc -z "$ip" 22 2>/dev/null; then
            echo "✅ REACHABLE"
            # Test actual SSH authentication
            echo -n "  SSH auth test: "
            if timeout 15 ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 ubuntu@"$ip" "echo 'SSH_SUCCESS'" 2>/dev/null | grep -q "SSH_SUCCESS"; then
                echo "✅ SSH AUTH OK"
                
                # Check if RKE2 is already installed
                echo -n "  RKE2 status: "
                RKE2_STATUS=$(timeout 10 ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$ip" "ls -la /usr/local/bin/rke2* 2>/dev/null || echo 'NOT_INSTALLED'" 2>/dev/null)
                if echo "$RKE2_STATUS" | grep -q "NOT_INSTALLED"; then
                    echo "❌ NOT INSTALLED"
                else
                    echo "✅ ALREADY INSTALLED"
                    echo "    $RKE2_STATUS"
                fi
            else
                echo "❌ SSH AUTH FAILED"
                FAILED_NODES=$((FAILED_NODES + 1))
            fi
        else
            echo "❌ UNREACHABLE"
            FAILED_NODES=$((FAILED_NODES + 1))
        fi
        echo ""
    done
fi

if [ $FAILED_NODES -gt 0 ]; then
    echo "⚠️  WARNING: $FAILED_NODES nodes failed connectivity/auth tests"
    echo "   This may cause Ansible playbook to fail or hang"
    echo "   Consider checking:"
    echo "   - Security groups allow SSH (port 22) from GitHub Actions"
    echo "   - SSH key is correct and matches EC2 instances"
    echo "   - Nodes are fully started and not still booting"
    echo ""
fi

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
GITHUB_WORKSPACE_LOG="${GITHUB_WORKSPACE:-/tmp}/ansible-rke2-debug.log"

echo "📄 Log files:"
echo "  - Real-time: GitHub Actions console (you're seeing this now)"
echo "  - Detailed: $LOG_FILE" 
echo "  - Artifact: $GITHUB_WORKSPACE_LOG (downloadable)"
echo ""

# Execute with comprehensive logging
echo "🎬 STARTING ANSIBLE EXECUTION..."
echo "==============================="

# Add timeout wrapper for GitHub Actions (max 45 minutes)
echo "⏰ Setting up 45-minute timeout for GitHub Actions..."
echo "🚀 EXECUTING ANSIBLE COMMAND:"
echo "ansible-playbook -i $INVENTORY_FILE -u ubuntu --private-key=$SSH_KEY_FILE [with debug flags]"
echo ""
echo "⏱️  Starting at: $(date)"
echo "📡 This may take 15-30 minutes for RKE2 installation..."
echo "🔄 Real-time output follows:"
echo "=================================================================================="

# Execute ansible-playbook with timeout (45 minutes = 2700 seconds)
timeout 2700 ansible-playbook \
    -i "$INVENTORY_FILE" \
    -u ubuntu \
    --private-key="$SSH_KEY_FILE" \
    --ssh-common-args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o ConnectTimeout=30' \
    -vvvv \
    --diff \
    --timeout=600 \
    "$PLAYBOOK_FILE" 2>&1 | tee "$LOG_FILE" | tee "$GITHUB_WORKSPACE_LOG"

ANSIBLE_EXIT_CODE=${PIPESTATUS[0]}

# Check if it was killed by timeout
if [ $ANSIBLE_EXIT_CODE -eq 124 ]; then
    echo ""
    echo "⏰ TIMEOUT: Ansible execution exceeded 45 minutes and was terminated"
    echo "This suggests the playbook is hanging or nodes are not responding properly"
    ANSIBLE_EXIT_CODE=1
fi

echo ""
echo "=== 🏁 ANSIBLE RKE2 INSTALLATION COMPLETED ==="
echo "=============================================="
echo "Exit Code: $ANSIBLE_EXIT_CODE"
echo "Completion Time: $(date)"
echo ""
echo "📁 LOG FILE LOCATIONS:"
echo "  - GitHub Actions Console: ✅ Available above"
echo "  - Runner temp file: $LOG_FILE"
echo "  - Workspace artifact: $GITHUB_WORKSPACE_LOG"
echo ""

if [ $ANSIBLE_EXIT_CODE -eq 0 ]; then
    echo "✅ SUCCESS: RKE2 cluster installation completed successfully!"
    echo ""
    echo "🎉 CLUSTER READY!"
    echo "================"
    echo "Your RKE2 cluster is now operational with:"
    echo "  • $(grep -c 'control_plane' "$INVENTORY_FILE" 2>/dev/null || echo '3') Control Plane nodes"
    echo "  • $(grep -c 'etcd' "$INVENTORY_FILE" 2>/dev/null || echo '3') ETCD nodes" 
    echo "  • $(grep -c 'worker' "$INVENTORY_FILE" 2>/dev/null || echo '2') Worker nodes"
    echo ""
    echo "Next steps:"
    echo "  1. Download kubeconfig from primary control plane"
    echo "  2. Verify cluster with: kubectl get nodes"
    echo "  3. Deploy your applications!"
else
    echo "❌ FAILED: RKE2 cluster installation failed with exit code $ANSIBLE_EXIT_CODE"
    echo ""
    echo "🔍 DEBUGGING INFORMATION:"
    echo "========================"
    
    # Copy log to workspace for artifact download
    if [ -f "$LOG_FILE" ] && [ -n "$GITHUB_WORKSPACE" ]; then
        cp "$LOG_FILE" "$GITHUB_WORKSPACE_LOG" 2>/dev/null || true
        echo "  • Full debug log available as GitHub Actions artifact"
    fi
    
    echo "  • Most recent Ansible errors:"
    if [ -f "$LOG_FILE" ]; then
        echo "    ────────────────────────────────────────"
        tail -20 "$LOG_FILE" | grep -E "(FAILED|ERROR|fatal)" | head -5 || echo "    No obvious errors found in recent output"
        echo "    ────────────────────────────────────────"
    fi
    
    echo ""
    echo "💡 TROUBLESHOOTING TIPS:"
    echo "  1. Check node connectivity and SSH access"
    echo "  2. Verify inventory file format and node IPs"
    echo "  3. Review full debug log for detailed error information"
    echo "  4. Ensure nodes meet RKE2 system requirements"
fi

echo ""
echo "📋 LOG PRESERVATION:"
echo "==================="
echo "Logs are available in multiple locations for debugging:"
echo "  • Real-time: GitHub Actions console output (above)"
echo "  • Ephemeral: $LOG_FILE (in runner /tmp - not downloadable)"
if [ -n "$GITHUB_WORKSPACE" ]; then
    echo "  • Persistent: $GITHUB_WORKSPACE_LOG (downloadable as artifact)"
fi

# Ensure workspace log exists for artifact creation
if [ -n "$GITHUB_WORKSPACE" ] && [ -f "$LOG_FILE" ]; then
    cp "$LOG_FILE" "$GITHUB_WORKSPACE_LOG" 2>/dev/null || true
    echo ""
    echo "✅ Debug log copied to workspace for artifact download"
fi

echo ""
echo "🔚 Script execution completed at $(date)"
echo "======================================================="

exit $ANSIBLE_EXIT_CODE
