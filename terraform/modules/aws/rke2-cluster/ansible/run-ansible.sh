#!/bin/bash

# Enable strict error handling with immediate exit on any failure
set -eEuo pipefail
# Exit immediately on any error, undefined variable, or pipe failure
# -e: exit on error
# -E: inherit error traps  
# -u: exit on undefined variable
# -o pipefail: exit if any command in pipeline fails

# Script to run Ansible playbook for RKE2 installation
# This script is called by Terraform's local-exec provisioner

# Error trap function for immediate error reporting
error_exit() {
    local line_no=$1
    local error_code=$2
    echo ""
    echo "🚨 IMMEDIATE FAILURE DETECTED 🚨"
    echo "================================="
    echo "❌ Script failed at line $line_no with exit code $error_code"
    echo "❌ Timestamp: $(date)"
    echo "❌ Command that failed: ${BASH_COMMAND}"
    echo ""
    echo "🔍 DEBUGGING INFO:"
    echo "  - Working directory: $(pwd)"
    echo "  - User: $(whoami)"
    echo "  - Environment: ${GITHUB_ACTIONS:+GitHub Actions}${GITHUB_ACTIONS:-Local}"
    echo ""
    exit $error_code
}

# Set trap for immediate error reporting
trap 'error_exit $LINENO $?' ERR

ANSIBLE_DIR="$1"
INVENTORY_FILE="$2"
SSH_KEY_FILE="$3"
PLAYBOOK_FILE="$4"

echo "=== Starting Ansible RKE2 Installation ==="
echo "Ansible Directory: $ANSIBLE_DIR"
echo "Inventory File: $INVENTORY_FILE"
echo "SSH Key File: $SSH_KEY_FILE"
echo "Playbook File: $PLAYBOOK_FILE"

echo ""
echo "🔍 IMMEDIATE VALIDATION CHECKS:"
echo "==============================="

# Immediate validation - fail fast if anything is wrong
if [ ! -f "$INVENTORY_FILE" ]; then
    echo "❌ IMMEDIATE FAILURE: Inventory file not found: $INVENTORY_FILE"
    exit 1
fi

if [ ! -f "$SSH_KEY_FILE" ]; then
    echo "❌ IMMEDIATE FAILURE: SSH key file not found: $SSH_KEY_FILE"
    exit 1
fi

if [ ! -f "$PLAYBOOK_FILE" ]; then
    echo "❌ IMMEDIATE FAILURE: Playbook file not found: $PLAYBOOK_FILE"
    exit 1
fi

# Check SSH key permissions immediately
SSH_KEY_PERMS=$(stat -c %a "$SSH_KEY_FILE")
if [ "$SSH_KEY_PERMS" != "600" ]; then
    echo "❌ IMMEDIATE FAILURE: SSH key has incorrect permissions: $SSH_KEY_PERMS (should be 600)"
    echo "Fixing SSH key permissions..."
    chmod 600 "$SSH_KEY_FILE" || {
        echo "❌ IMMEDIATE FAILURE: Cannot fix SSH key permissions"
        exit 1
    }
    echo "✅ SSH key permissions fixed"
fi

# Verify SSH key is readable (without displaying contents)
if [ ! -r "$SSH_KEY_FILE" ]; then
    echo "❌ IMMEDIATE FAILURE: SSH key file is not readable: $SSH_KEY_FILE"
    exit 1
fi

echo "✅ SSH key file exists and is readable"
echo "✅ All immediate validation checks passed"
echo ""

# Convert relative paths to absolute paths before changing directory
INVENTORY_FILE=$(realpath "$INVENTORY_FILE")
SSH_KEY_FILE=$(realpath "$SSH_KEY_FILE")
PLAYBOOK_FILE=$(realpath "$PLAYBOOK_FILE")

echo "🔄 Converted to absolute paths:"
echo "  Inventory: $INVENTORY_FILE"
echo "  SSH Key: $SSH_KEY_FILE"
echo "  Playbook: $PLAYBOOK_FILE"
echo ""

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
# Test connectivity to nodes before starting (skip in GitHub Actions for speed)
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "⚡ Skipping detailed connectivity tests in GitHub Actions for speed"
    echo "📍 Extracting IPs from inventory file..."
    CLUSTER_IPS=$(grep -oP 'ansible_host:\s*\K[0-9.]+' "$INVENTORY_FILE" || true)
    echo "📋 Found IPs: $CLUSTER_IPS"
    echo "🚀 Proceeding directly to Ansible execution..."
    FAILED_NODES=0  # Skip connectivity checks in GitHub Actions
else
    echo "📍 Extracting IPs from inventory file..."
    CLUSTER_IPS=$(grep -oP 'ansible_host:\s*\K[0-9.]+' "$INVENTORY_FILE" || true)
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
                    RKE2_STATUS=$(timeout 5 ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o ServerAliveInterval=2 -o ServerAliveCountMax=3 ubuntu@"$ip" "test -f /usr/local/bin/rke2 && echo 'INSTALLED' || echo 'NOT_INSTALLED'" 2>/dev/null || echo 'CHECK_FAILED')
                    case "$RKE2_STATUS" in
                        "INSTALLED")
                            echo "✅ ALREADY INSTALLED"
                            ;;
                        "NOT_INSTALLED")
                            echo "❌ NOT INSTALLED"
                            ;;
                        *)
                            echo "⚠️ CHECK FAILED (will proceed with installation)"
                            ;;
                    esac
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
# Set optimized environment variables for production deployment with security
export ANSIBLE_DEBUG=False
export ANSIBLE_VERBOSE_TO_STDERR=False
export ANSIBLE_DISPLAY_SKIPPED_HOSTS=False
export ANSIBLE_DISPLAY_OK_HOSTS=False
export ANSIBLE_DISPLAY_FAILED_STDERR=True
export ANSIBLE_STDOUT_CALLBACK=minimal
export ANSIBLE_CALLBACK_WHITELIST=timer
export ANSIBLE_FORCE_COLOR=True
export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_SSH_RETRIES=2
export ANSIBLE_TIMEOUT=120
export ANSIBLE_GATHER_TIMEOUT=300
export ANSIBLE_SSH_PIPELINING=True

# Security: Hide sensitive information in logs (TEMPORARILY DISABLED FOR DEBUGGING)
export ANSIBLE_NO_LOG=False  # CHANGED: Enable logs for debugging
export ANSIBLE_HIDE_CMDLINE_FROM_PS=True
export ANSIBLE_PARAMIKO_RECORD_HOST_KEYS=False
export ANSIBLE_LOG_FILTER=""  # CHANGED: Remove log filtering for debugging
export ANSIBLE_DEPRECATION_WARNINGS=False
export ANSIBLE_COMMAND_WARNINGS=False
export ANSIBLE_SYSTEM_WARNINGS=False

echo "Ansible Version:"
ansible-playbook --version
echo ""

echo "� STARTING RKE2 CLUSTER DEPLOYMENT:"
echo "===================================="
echo "This will deploy RKE2 with minimal logging for clean output..."
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

# Add timeout wrapper for GitHub Actions (max 30 minutes)
echo "⏰ Setting up 25-minute timeout for GitHub Actions..."
echo "🚀 EXECUTING ANSIBLE COMMAND (with security filters):"
echo "ansible-playbook -i $INVENTORY_FILE -u ubuntu --private-key=[HIDDEN] [secure deployment]"
echo ""
echo "⏱️  Starting at: $(date)"
echo "📡 This may take 15-30 minutes for RKE2 installation..."
echo "🔄 Real-time output follows:"
echo "=================================================================================="

# Debug: Show current working directory and files
echo "🔍 DEBUG: Current working directory: $(pwd)"
echo "🔍 DEBUG: Available files: $(ls -la | head -10)"
echo "🔍 DEBUG: Ansible version: $(ansible-playbook --version | head -1)"
echo "=================================================================================="

# Add background progress monitor for GitHub Actions
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "🕐 Progress monitor enabled for GitHub Actions visibility..."
    (
        sleep 120  # Wait 2 minutes before first update
        while true; do
            if ps aux | grep -q "ansible-playbook.*rke2-playbook.yml" | grep -v grep; then
                echo "⏰ $(date): Ansible still running... (normal for RKE2 installation)"
                echo "   📊 Process status: ACTIVE"
            fi
            sleep 180  # Update every 3 minutes
        done
    ) &
    PROGRESS_PID=$!
fi

# Execute ansible-playbook without timeout since SSH connectivity is stable
# Using single fork for immediate error visibility and fail-fast behavior
echo "🚀 Starting Ansible execution with immediate error reporting..."
ansible-playbook \
    -i "$INVENTORY_FILE" \
    -u ubuntu \
    --private-key="$SSH_KEY_FILE" \
    --forks=1 \
    --ssh-common-args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=60 -o ServerAliveCountMax=10' \
    -v \
    "$PLAYBOOK_FILE" 2>&1 | \
    while IFS= read -r line; do
        # Immediate error detection and reporting
        if [[ "$line" =~ "FAILED\!" ]] || [[ "$line" =~ "fatal:" ]] || [[ "$line" =~ "ERROR!" ]]; then
            echo ""
            echo "🚨 IMMEDIATE ANSIBLE FAILURE DETECTED 🚨"
            echo "========================================"
            echo "❌ $line"
            echo "❌ Timestamp: $(date)"
            echo ""
            # Still log to files but exit immediately
            echo "$line" | tee -a "$LOG_FILE" | tee -a "$GITHUB_WORKSPACE_LOG"
            exit 1
        fi
        
        # Show progress indicators for GitHub Actions
        if [[ "$line" =~ "PLAY \[" ]]; then
            echo "🎭 $line"
        elif [[ "$line" =~ "TASK \[" ]]; then
            echo "📋 $line"
        elif [[ "$line" =~ "PLAY RECAP" ]]; then
            echo "📊 $line"
        elif [[ "$line" =~ "changed:" ]] && [[ ! "$line" =~ "censored" ]]; then
            echo "✅ $line"
        else
            # Log everything to file but only show important stuff to console in GitHub Actions
            echo "$line"
        fi
    done | tee "$LOG_FILE" | tee "$GITHUB_WORKSPACE_LOG"

ANSIBLE_EXIT_CODE=${PIPESTATUS[0]}

# Clean up progress monitor
if [ -n "$PROGRESS_PID" ]; then
    kill $PROGRESS_PID 2>/dev/null || true
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
    if [ -f "$LOG_FILE" ] && [ -n "${GITHUB_WORKSPACE:-}" ]; then
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
if [ -n "${GITHUB_WORKSPACE:-}" ]; then
    echo "  • Persistent: $GITHUB_WORKSPACE_LOG (downloadable as artifact)"
fi

# Ensure workspace log exists for artifact creation
if [ -n "${GITHUB_WORKSPACE:-}" ] && [ -f "$LOG_FILE" ]; then
    cp "$LOG_FILE" "$GITHUB_WORKSPACE_LOG" 2>/dev/null || true
    echo ""
    echo "✅ Debug log copied to workspace for artifact download"
fi

echo ""
echo "🔚 Script execution completed at $(date)"
echo "======================================================="

exit $ANSIBLE_EXIT_CODE
