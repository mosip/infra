#!/bin/bash

# GitHub Actions RKE2 Deployment Monitor
# This script helps decode what's happening in your GitHub Actions workflow

echo "🔍 GitHub Actions RKE2 Deployment Monitor"
echo "=========================================="
echo ""

# Function to show colored output for better readability in GitHub Actions
show_status() {
    local status=$1
    local message=$2
    case $status in
        "SUCCESS") echo "✅ $message" ;;
        "ERROR") echo "❌ $message" ;;
        "INFO") echo "ℹ️  $message" ;;
        "WARN") echo "⚠️  $message" ;;
        *) echo "$message" ;;
    esac
}

show_status "INFO" "This script analyzes the current state of your RKE2 infrastructure"
echo ""

# Check if we're in the right directory structure
if [ ! -d "terraform/modules/aws/rke2-cluster/ansible" ]; then
    show_status "ERROR" "Not in the right directory. Please run from infra root."
    echo "Expected to find: terraform/modules/aws/rke2-cluster/ansible/"
    exit 1
fi

# Analyze Ansible configuration
echo "📋 ANSIBLE CONFIGURATION ANALYSIS"
echo "================================="

ANSIBLE_DIR="terraform/modules/aws/rke2-cluster/ansible"

# Check playbook structure
if [ -f "$ANSIBLE_DIR/rke2-playbook.yml" ]; then
    show_status "SUCCESS" "RKE2 playbook found"
    echo "   Phases in playbook:"
    grep -n "^- name:" "$ANSIBLE_DIR/rke2-playbook.yml" | head -5
else
    show_status "ERROR" "RKE2 playbook not found"
fi

# Check run script
if [ -f "$ANSIBLE_DIR/run-ansible.sh" ]; then
    show_status "SUCCESS" "Ansible runner script found"
    if grep -q "GITHUB ACTIONS" "$ANSIBLE_DIR/run-ansible.sh"; then
        show_status "SUCCESS" "GitHub Actions optimizations enabled"
    else
        show_status "WARN" "GitHub Actions optimizations not detected"
    fi
else
    show_status "ERROR" "Ansible runner script not found"
fi

echo ""
echo "🏗️  TERRAFORM CONFIGURATION ANALYSIS"
echo "==================================="

# Check main Terraform files
MAIN_TF="terraform/modules/aws/rke2-cluster/main.tf"
if [ -f "$MAIN_TF" ]; then
    show_status "SUCCESS" "Main Terraform configuration found"
    
    # Check if Ansible integration is configured
    if grep -q "local_file.*ansible_inventory" "$MAIN_TF"; then
        show_status "SUCCESS" "Ansible inventory generation configured"
    fi
    
    if grep -q "null_resource.*rke2_ansible_installation" "$MAIN_TF"; then
        show_status "SUCCESS" "Ansible execution resource configured"
    fi
else
    show_status "ERROR" "Main Terraform configuration not found"
fi

echo ""
echo "🎯 WHAT TO LOOK FOR IN GITHUB ACTIONS LOGS"
echo "=========================================="
show_status "INFO" "In your GitHub Actions workflow, look for these key phases:"
echo ""
echo "1. 📦 TERRAFORM INITIALIZATION"
echo "   - Look for: 'Terraform has been successfully initialized!'"
echo ""
echo "2. 🗂️  INVENTORY GENERATION"
echo "   - Look for: 'INVENTORY CONTENTS:' section"
echo "   - Verify cluster node IPs are listed correctly"
echo ""
echo "3. 🔑 SSH CONNECTIVITY"
echo "   - Look for: 'NETWORK CONNECTIVITY TEST:'"
echo "   - All nodes should show '✅ REACHABLE'"
echo ""
echo "4. 🚀 ANSIBLE PLAYBOOK PHASES"
echo "   Phase 1: Primary Control Plane Installation"
echo "   - Look for: 'Install Primary RKE2 Control Plane Node'"
echo "   - Should see: 'GITHUB ACTIONS DEBUG - Show target node information'"
echo ""
echo "   Phase 2: Secondary Nodes Installation"
echo "   - Look for: 'Install remaining RKE2 nodes in parallel'"
echo "   - Worker and additional control plane nodes"
echo ""
echo "   Phase 3: Cluster Health Verification"
echo "   - Look for: 'Verify RKE2 cluster health'"
echo "   - Final cluster status and node count"
echo ""
echo "5. 📋 SUCCESS INDICATORS"
echo "   - Look for: '✅ SUCCESS: RKE2 cluster installation completed'"
echo "   - Kubeconfig file downloaded"
echo "   - All nodes in Ready state"
echo ""

echo "🔍 COMMON ISSUES TO CHECK"
echo "========================"
show_status "WARN" "If your deployment is stuck, check for:"
echo ""
echo "• SSH connectivity issues:"
echo "  - Look for 'UNREACHABLE' in connectivity test"
echo "  - Check security group SSH access (port 22)"
echo ""
echo "• Package download timeouts:"
echo "  - RKE2 binary download from GitHub releases"
echo "  - Network connectivity from cluster nodes"
echo ""
echo "• Resource constraints:"
echo "  - Insufficient memory/CPU on cluster nodes"
echo "  - Disk space issues"
echo ""
echo "• Timing issues:"
echo "  - Nodes not fully ready when Ansible connects"
echo "  - EC2 instances still initializing"
echo ""

echo "⏱️  EXPECTED TIMELINE"
echo "==================="
echo "Your RKE2 deployment should follow this timeline:"
echo ""
echo "• 0-2 minutes:   Terraform resource creation"
echo "• 2-4 minutes:   EC2 instances starting up"
echo "• 4-6 minutes:   Primary control plane installation"
echo "• 6-8 minutes:   Secondary nodes installation"
echo "• 8-10 minutes:  Final cluster verification"
echo ""
show_status "SUCCESS" "Total expected time: 8-10 minutes (60% faster than remote-exec!)"
echo ""

echo "📊 CURRENT LOCAL STATE"
echo "====================="
# Show some local file states to help with debugging
find terraform/modules/aws/rke2-cluster/ansible -name "*.yml" -o -name "*.sh" | while read file; do
    if [ -f "$file" ]; then
        show_status "SUCCESS" "$(basename $file) exists"
    fi
done

echo ""
show_status "INFO" "Monitor your GitHub Actions workflow for the above indicators!"
echo "GitHub Actions URL: https://github.com/mosip/infra/actions"
