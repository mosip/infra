#!/bin/bash

# Simple test script to validate Ansible-based RKE2 installation
# Run this script after terraform apply to check cluster health

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$SCRIPT_DIR"

echo "=== RKE2 Ansible Cluster Test ==="

# Check if inventory file exists
if [[ ! -f "$ANSIBLE_DIR/inventory.yml" ]]; then
    echo "ERROR: Inventory file not found at $ANSIBLE_DIR/inventory.yml"
    echo "Please run 'terraform apply' first to generate the inventory."
    exit 1
fi

# Check if SSH key exists
if [[ ! -f "$ANSIBLE_DIR/ssh_key" ]]; then
    echo "ERROR: SSH key file not found at $ANSIBLE_DIR/ssh_key"
    echo "Please run 'terraform apply' first to generate the SSH key."
    exit 1
fi

# Check if primary kubeconfig exists
if [[ -f "$ANSIBLE_DIR/primary-kubeconfig.yaml" ]]; then
    echo "✅ Primary kubeconfig found"
    export KUBECONFIG="$ANSIBLE_DIR/primary-kubeconfig.yaml"
    
    # Test kubectl connectivity
    echo "🔍 Testing kubectl connectivity..."
    if kubectl get nodes &>/dev/null; then
        echo "✅ Kubectl connectivity successful"
        echo ""
        echo "=== Cluster Nodes ==="
        kubectl get nodes -o wide
        echo ""
        echo "=== Cluster Info ==="
        kubectl cluster-info
    else
        echo "❌ Kubectl connectivity failed"
        echo "Cluster may still be initializing. Wait a few minutes and try again."
    fi
else
    echo "⚠️  Primary kubeconfig not found. Testing with Ansible..."
fi

# Test Ansible connectivity
echo ""
echo "🔍 Testing Ansible connectivity to all nodes..."
ansible all -i "$ANSIBLE_DIR/inventory.yml" \
    -u ubuntu \
    --private-key="$ANSIBLE_DIR/ssh_key" \
    --ssh-common-args='-o StrictHostKeyChecking=no' \
    -m ping

echo ""
echo "🔍 Checking RKE2 service status on all nodes..."
ansible rke2_cluster -i "$ANSIBLE_DIR/inventory.yml" \
    -u ubuntu \
    --private-key="$ANSIBLE_DIR/ssh_key" \
    --ssh-common-args='-o StrictHostKeyChecking=no' \
    -m shell \
    -a "sudo systemctl is-active rke2-server || sudo systemctl is-active rke2-agent || echo 'RKE2 service not active'"

echo ""
echo "=== Test Complete ==="
echo "If you see any errors above, the cluster may still be initializing."
echo "Wait a few minutes and run this test again."
