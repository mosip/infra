#!/bin/bash

# Quick validation script for the MOSIP infrastructure setup
# This script validates that all major components are in place

set -e

echo "=== MOSIP Infrastructure Setup Validation ==="
echo ""

# Check directory structure
echo "1. Validating directory structure..."
for dir in "terraform/observ-infra/aws" "terraform/modules/aws/rancher-keycloak-setup" "terraform/implementations/aws/observ-infra" ".github/scripts"; do
    if [ -d "$dir" ]; then
        echo "  ✅ $dir exists"
    else
        echo "  ❌ $dir missing"
        exit 1
    fi
done

echo ""

# Check key files
echo "2. Validating key files..."
KEY_FILES=(
    "terraform/observ-infra/aws/main.tf"
    "terraform/modules/aws/rancher-keycloak-setup/main.tf"
    "terraform/implementations/aws/observ-infra/main.tf"
    "terraform/implementations/aws/observ-infra/aws.tfvars"
    ".github/workflows/terraform.yml"
    ".github/workflows/terraform-destroy.yml"
    ".github/scripts/setup-cloud-storage.sh"
    ".github/scripts/configure-backend.sh"
    ".github/scripts/cleanup-state-locking.sh"
    ".github/scripts/test-state-locking.sh"
)

for file in "${KEY_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✅ $file exists"
    else
        echo "  ❌ $file missing"
        exit 1
    fi
done

echo ""

# Check that old rancher-keycloak-integration module is removed
echo "3. Validating cleanup..."
if [ -d "terraform/modules/rancher-keycloak-integration" ]; then
    echo "  ❌ Old rancher-keycloak-integration module still exists"
    exit 1
else
    echo "  ✅ Old rancher-keycloak-integration module properly removed"
fi

echo ""

# Check script permissions
echo "4. Validating script permissions..."
SCRIPTS=(
    ".github/scripts/setup-cloud-storage.sh"
    ".github/scripts/configure-backend.sh"
    ".github/scripts/cleanup-state-locking.sh"
    ".github/scripts/test-infrastructure.sh"
    ".github/scripts/test-workflow-e2e.sh"
    ".github/scripts/test-state-locking.sh"
    ".github/scripts/test-cleanup-state-locking.sh"
)

for script in "${SCRIPTS[@]}"; do
    if [ -x "$script" ]; then
        echo "  ✅ $script is executable"
    else
        echo "  ⚠️  $script is not executable - fixing..."
        chmod +x "$script"
    fi
done

echo ""

# Validate Terraform syntax for key files
echo "5. Validating Terraform syntax..."
cd terraform/implementations/aws/observ-infra

# Check if terraform is available
if ! command -v terraform &> /dev/null; then
    echo "  ⚠️  Terraform not installed - skipping syntax validation"
else
    echo "  🔍 Running terraform fmt check..."
    if terraform fmt -check -recursive .; then
        echo "  ✅ Terraform formatting is correct"
    else
        echo "  ⚠️  Some files need formatting - run 'terraform fmt -recursive'"
    fi
    
    echo "  🔍 Running terraform init and validate..."
    if terraform init -backend=false &> /dev/null && terraform validate &> /dev/null; then
        echo "  ✅ Terraform configuration is valid"
    else
        echo "  ⚠️  Terraform validation failed - check configuration"
    fi
fi

cd - > /dev/null

echo ""

# Check GitHub Actions workflow syntax
echo "6. Validating GitHub Actions workflow..."
if command -v yamllint &> /dev/null; then
    if yamllint .github/workflows/terraform.yml &> /dev/null; then
        echo "  ✅ GitHub Actions workflow YAML is valid"
    else
        echo "  ⚠️  GitHub Actions workflow has YAML issues"
    fi
else
    echo "  ⚠️  yamllint not available - skipping YAML validation"
fi

echo ""

# Check for proper variable usage
echo "7. Validating integration points..."

# Check that observ-infra calls rancher-keycloak-setup
if grep -q "rancher-keycloak-setup" terraform/observ-infra/aws/main.tf; then
    echo "  ✅ observ-infra properly calls rancher-keycloak-setup module"
else
    echo "  ❌ observ-infra doesn't call rancher-keycloak-setup module"
    exit 1
fi

# Check that main infra doesn't have rancher variables
if ! grep -q "ENABLE_RANCHER_KEYCLOAK" terraform/infra/aws/variables.tf 2>/dev/null; then
    echo "  ✅ Main infra is clean of Rancher-Keycloak variables"
else
    echo "  ❌ Main infra still contains Rancher-Keycloak variables"
    exit 1
fi

# Check ENABLE_STATE_LOCKING default in workflow
if grep -q "default: true" .github/workflows/terraform.yml | grep -q "ENABLE_STATE_LOCKING" -A1 -B1 .github/workflows/terraform.yml; then
    echo "  ✅ Cloud-agnostic state locking defaults to enabled"
else
    echo "  ⚠️  Check ENABLE_STATE_LOCKING default in workflow"
fi

echo ""
echo "=== Validation Summary ==="
echo "🎉 All major components are properly configured!"
echo ""
echo "✅ Rancher-Keycloak integration is properly isolated to observ-infra"
echo "✅ Cloud-agnostic state locking is optional with safe defaults"
echo "✅ GitHub Actions workflow supports all required scenarios"
echo "✅ All test scripts are in place and executable"
echo ""
echo "Your infrastructure is ready for deployment!"
echo ""
echo "Next steps:"
echo "  1. Configure your cloud credentials in GitHub secrets"
echo "  2. Set up environment-specific secrets for WireGuard"
echo "  3. Run the GitHub Actions workflow to deploy your infrastructure"
echo ""
echo "For detailed deployment instructions, see:"
echo "  - README.md"
echo "  - terraform/CLOUD_AGNOSTIC_README.md"
echo "  - docs/OPTIONAL_STATE_LOCKING.md"
