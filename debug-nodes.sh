#!/bin/bash

# Quick script to check RKE2 installation status on all nodes
# Usage: ./debug-nodes.sh <inventory_file> <ssh_key_file>

INVENTORY_FILE="$1"
SSH_KEY_FILE="$2"

if [ -z "$INVENTORY_FILE" ] || [ -z "$SSH_KEY_FILE" ]; then
    echo "Usage: $0 <inventory_file> <ssh_key_file>"
    exit 1
fi

echo "🔍 RKE2 Cluster Node Diagnostic"
echo "==============================="
echo "Checking nodes from: $INVENTORY_FILE"
echo "Using SSH key: $SSH_KEY_FILE"
echo ""

# Extract all IPs from inventory
CLUSTER_IPS=$(grep -oP 'ansible_host=\K[0-9.]+' "$INVENTORY_FILE" || true)

for ip in $CLUSTER_IPS; do
    echo "📍 Checking node: $ip"
    echo "  ├─ SSH connectivity..."
    
    if timeout 10 ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 ubuntu@"$ip" "echo 'Connected'" >/dev/null 2>&1; then
        echo "  │  ✅ SSH OK"
        
        echo "  ├─ RKE2 binary check..."
        RKE2_BIN=$(ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$ip" "ls -la /usr/local/bin/rke2* 2>/dev/null || echo 'NOT_FOUND'" 2>/dev/null)
        if echo "$RKE2_BIN" | grep -q "NOT_FOUND"; then
            echo "  │  ❌ RKE2 binary NOT installed"
        else
            echo "  │  ✅ RKE2 binary found"
        fi
        
        echo "  ├─ RKE2 service status..."
        SERVICE_STATUS=$(ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$ip" "sudo systemctl is-active rke2-server 2>/dev/null || sudo systemctl is-active rke2-agent 2>/dev/null || echo 'not-running'" 2>/dev/null)
        echo "  │  📋 Service: $SERVICE_STATUS"
        
        echo "  ├─ Installation log check..."
        LOG_EXISTS=$(ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$ip" "ls -la /tmp/rke2-setup.log 2>/dev/null || echo 'NO_LOG'" 2>/dev/null)
        if echo "$LOG_EXISTS" | grep -q "NO_LOG"; then
            echo "  │  ❌ No installation log found"
        else
            echo "  │  ✅ Installation log exists"
            # Get last few lines of log
            LAST_LOG=$(ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$ip" "tail -3 /tmp/rke2-setup.log 2>/dev/null || echo 'Cannot read log'" 2>/dev/null)
            echo "  │     Last log entries:"
            echo "$LAST_LOG" | sed 's/^/  │     /'
        fi
        
        echo "  └─ Process check..."
        PROCESSES=$(ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$ip" "ps aux | grep -E 'rke2|containerd|kubelet' | grep -v grep | wc -l" 2>/dev/null)
        echo "     🔄 RKE2-related processes: $PROCESSES"
        
    else
        echo "  └─ ❌ SSH connection failed"
    fi
    echo ""
done

echo "🏁 Diagnostic complete"
echo ""
echo "💡 If no RKE2 components are found:"
echo "   1. Check if Ansible playbook actually started"
echo "   2. Verify GitHub Actions logs for errors"
echo "   3. Ensure inventory file has correct IPs"
echo "   4. Check security groups allow SSH from GitHub Actions"
