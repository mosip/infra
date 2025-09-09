#!/bin/bash

# Debug script to monitor ongoing RKE2 installation
# Run this script in a separate terminal to get real-time logs

echo "🔍 RKE2 Ansible Installation Debug Monitor"
echo "=========================================="
echo ""

# Check if Terraform is running
TERRAFORM_PID=$(pgrep -f "terraform.*apply" | head -1)
if [ -n "$TERRAFORM_PID" ]; then
    echo "✅ Terraform process found (PID: $TERRAFORM_PID)"
else
    echo "❌ No Terraform apply process found"
fi

# Check for Ansible processes
ANSIBLE_PID=$(pgrep -f "ansible-playbook" | head -1)
if [ -n "$ANSIBLE_PID" ]; then
    echo "✅ Ansible playbook process found (PID: $ANSIBLE_PID)"
else
    echo "❌ No Ansible playbook process found"
fi

echo ""
echo "📁 Current working directory:"
pwd
echo ""

# Find the Ansible working directory
ANSIBLE_DIR=$(find . -name "inventory.yml" -type f | head -1 | xargs dirname 2>/dev/null)
if [ -n "$ANSIBLE_DIR" ]; then
    echo "🎯 Found Ansible directory: $ANSIBLE_DIR"
    echo ""
    
    # Show inventory contents
    echo "📋 Current inventory contents:"
    echo "=============================="
    cat "$ANSIBLE_DIR/inventory.yml" 2>/dev/null || echo "Inventory file not found"
    echo ""
    
    # Check if SSH key exists
    if [ -f "$ANSIBLE_DIR/ssh_key" ]; then
        echo "🔑 SSH key file found: $ANSIBLE_DIR/ssh_key"
        ls -la "$ANSIBLE_DIR/ssh_key"
    else
        echo "❌ SSH key file not found in $ANSIBLE_DIR"
    fi
    echo ""
fi

# Monitor log files
echo "📄 Looking for log files..."
echo "=========================="

# Check for Ansible debug log
if [ -f "/tmp/ansible-debug.log" ]; then
    echo "✅ Found Ansible debug log: /tmp/ansible-debug.log"
    echo "Last 10 lines:"
    tail -10 /tmp/ansible-debug.log
    echo ""
    echo "🔄 To monitor in real-time, run:"
    echo "   tail -f /tmp/ansible-debug.log"
else
    echo "❌ No Ansible debug log found at /tmp/ansible-debug.log"
fi

# Check SSH connections to cluster nodes
echo ""
echo "🔗 Checking SSH connectivity to cluster nodes..."
echo "=============================================="

if [ -n "$ANSIBLE_DIR" ] && [ -f "$ANSIBLE_DIR/inventory.yml" ]; then
    # Extract IPs from inventory
    IPS=$(grep -oP 'ansible_host=\K[0-9.]+' "$ANSIBLE_DIR/inventory.yml" 2>/dev/null)
    if [ -n "$IPS" ]; then
        for IP in $IPS; do
            echo -n "Testing $IP: "
            if timeout 5 nc -z "$IP" 22 2>/dev/null; then
                echo "✅ SSH port open"
            else
                echo "❌ SSH port not reachable"
            fi
        done
    else
        echo "❌ Could not extract IPs from inventory"
    fi
else
    echo "❌ Inventory file not available for SSH testing"
fi

echo ""
echo "🚀 Real-time monitoring commands:"
echo "================================"
echo "1. Monitor Ansible logs:     tail -f /tmp/ansible-debug.log"
echo "2. Monitor all processes:    watch 'ps aux | grep -E \"(terraform|ansible)\"'"
echo "3. Monitor network:          watch 'netstat -tulpn | grep :22'"
echo "4. Re-run this script:       ./debug-rke2-installation.sh"
echo ""

# Offer to start real-time monitoring
read -p "Start real-time log monitoring? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -f "/tmp/ansible-debug.log" ]; then
        echo "Starting real-time log monitoring..."
        tail -f /tmp/ansible-debug.log
    else
        echo "Debug log not found. Monitoring for creation..."
        while [ ! -f "/tmp/ansible-debug.log" ]; do
            echo "Waiting for debug log to be created..."
            sleep 2
        done
        echo "Debug log created! Starting monitoring..."
        tail -f /tmp/ansible-debug.log
    fi
fi
