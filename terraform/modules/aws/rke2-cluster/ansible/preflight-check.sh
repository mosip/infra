#!/bin/bash

# Pre-flight check script for Ansible RKE2 installation
# Run this before terraform apply to ensure all requirements are met

set -e

echo "🔍 Ansible RKE2 Pre-flight Checks"
echo "=================================="

# Check if we're in the right directory
if [[ ! -f "main.tf" ]]; then
    echo "❌ Not in terraform directory. Please run from terraform/implementations/aws/infra/"
    exit 1
fi

echo "✅ Running from correct terraform directory"

# Check terraform installation
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform not found. Please install terraform first."
    exit 1
fi

echo "✅ Terraform found: $(terraform version | head -1)"

# Check for required tools
REQUIRED_TOOLS=("ssh" "scp" "curl" "git")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "❌ Required tool '$tool' not found"
        exit 1
    fi
done

echo "✅ Required tools available: ${REQUIRED_TOOLS[*]}"

# Check Python (needed for Ansible)
if ! command -v python3 &> /dev/null; then
    echo "⚠️  Python3 not found. Installing..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y python3 python3-pip
    elif command -v yum &> /dev/null; then
        sudo yum install -y python3 python3-pip
    else
        echo "❌ Please install Python3 manually"
        exit 1
    fi
fi

echo "✅ Python3 found: $(python3 --version)"

# Check Ansible (will be auto-installed if needed)
if command -v ansible-playbook &> /dev/null; then
    echo "✅ Ansible already installed: $(ansible-playbook --version | head -1)"
else
    echo "📦 Ansible not found - will be auto-installed during terraform apply"
fi

# Check SSH key permissions
if [[ -f "ssh_private_key" ]]; then
    chmod 600 ssh_private_key
    echo "✅ SSH key permissions set correctly"
fi

# Check disk space (Ansible + RKE2 needs some space)
AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
REQUIRED_SPACE=1048576  # 1GB in KB

if [[ $AVAILABLE_SPACE -lt $REQUIRED_SPACE ]]; then
    echo "⚠️  Low disk space. Available: $(($AVAILABLE_SPACE/1024))MB, Recommended: 1GB+"
else
    echo "✅ Sufficient disk space available"
fi

# Check network connectivity
if ping -c 1 8.8.8.8 &> /dev/null; then
    echo "✅ Network connectivity available"
else
    echo "⚠️  Network connectivity issues detected"
fi

echo ""
echo "🎯 Pre-flight Checks Summary:"
echo "=============================="
echo "✅ Terraform directory: OK"
echo "✅ Terraform installed: OK"
echo "✅ Required tools: OK"  
echo "✅ Python3: OK"
if command -v ansible-playbook &> /dev/null; then
    echo "✅ Ansible: Already installed"
else
    echo "📦 Ansible: Will auto-install"
fi
echo "✅ System ready for terraform apply"

echo ""
echo "🚀 Next Steps:"
echo "=============="
echo "1. Set your AWS credentials:"
echo "   export AWS_ACCESS_KEY_ID=your_key"
echo "   export AWS_SECRET_ACCESS_KEY=your_secret"
echo ""
echo "2. Run terraform:"
echo "   terraform init"
echo "   terraform plan"
echo "   terraform apply"
echo ""
echo "3. The Ansible installation will happen automatically during apply!"

echo ""
echo "📋 Installation Flow:"
echo "===================="
echo "• Terraform creates AWS infrastructure"
echo "• Terraform generates Ansible inventory"  
echo "• Ansible auto-installs (if needed)"
echo "• Ansible installs RKE2 cluster:"
echo "  - Primary control plane (sequential)"
echo "  - All other nodes (parallel)"
echo "• Cluster ready in ~6-8 minutes"
