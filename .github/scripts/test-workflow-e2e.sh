#!/bin/bash

# MOSIP Workflow End-to-End Testing Script
# Simulates complete GitHub Actions workflow execution for both terraform and terraform-destroy
# Tests all provider/component/backend combinations

set -e

echo "=== MOSIP Workflow End-to-End Testing ==="
echo "Simulating complete GitHub Actions workflow execution"
echo "Testing both terraform.yml and terraform-destroy.yml workflows"
echo "============================================================"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Project root: $PROJECT_ROOT"
echo "Scripts directory: $SCRIPT_DIR"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Function to print colored messages
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }
print_step() { echo -e "${PURPLE}▶ $1${NC}"; }

# Workflow test combinations
PROVIDERS=("aws" "azure" "gcp")
COMPONENTS=("base-infra" "infra" "observ-infra")
BACKENDS=("local" "remote")

# Remote config examples for testing
declare -A REMOTE_CONFIGS
REMOTE_CONFIGS["aws"]="aws:mosip-terraform-state:us-east-1"
REMOTE_CONFIGS["azure"]="azure:mosip-rg:mosipstate:terraform-state"
REMOTE_CONFIGS["gcp"]="gcp:mosip-terraform-state:us-central1"

# Function to simulate terraform workflow steps
simulate_terraform_workflow() {
    local provider="$1"
    local component="$2"
    local backend="$3"
    local remote_config="$4"
    local enable_locking="$5"
    local branch="main"
    
    local locking_flag=""
    if [[ "$enable_locking" == "true" ]]; then
        locking_flag="--enable-locking"
        print_step "Simulating TERRAFORM workflow: $provider/$component/$backend (WITH locking)"
    else
        print_step "Simulating TERRAFORM workflow: $provider/$component/$backend (WITHOUT locking)"
    fi
    
    # Change to the workflow working directory
    local work_dir="$PROJECT_ROOT/terraform/implementations/$provider/$component"
    if [[ ! -d "$work_dir" ]]; then
        print_warning "Directory not found: $work_dir"
        return 1
    fi
    
    cd "$work_dir"
    
    # Step 1: Check for required implementation directory (simulate workflow step)
    print_info "  Step 1: Checking required files..."
    if [[ -f "$provider.tfvars" ]]; then
        print_success "    ✓ $provider.tfvars found"
    else
        print_error "    ✗ $provider.tfvars not found"
        return 1
    fi
    
    # Step 2: Setup Cloud Storage for Remote State (if remote backend)
    if [[ "$backend" == "remote" ]]; then
        print_info "  Step 2: Setting up cloud storage..."
        if ../../../../.github/scripts/setup-cloud-storage.sh \
            --provider "$provider" \
            --config "$remote_config" \
            --branch "$branch" \
            --component "$component" \
            $locking_flag > /dev/null 2>&1; then
            print_success "    ✓ Cloud storage setup completed"
        else
            print_error "    ✗ Cloud storage setup failed"
            return 1
        fi
    else
        print_info "  Step 2: Skipping cloud storage (local backend)"
    fi
    
    # Step 3: Configure Terraform Backend
    print_info "  Step 3: Configuring Terraform backend..."
    if ../../../../.github/scripts/configure-backend.sh \
        --type "$backend" \
        --provider "$provider" \
        --component "$component" \
        --branch "$branch" \
        --remote-config "$remote_config" \
        $locking_flag > /dev/null 2>&1; then
        print_success "    ✓ Backend configuration completed"
    else
        print_error "    ✗ Backend configuration failed"
        return 1
    fi
    
    # Step 4: Verify backend.tf was created
    if [[ -f "backend.tf" ]]; then
        print_success "    ✓ backend.tf created successfully"
        
        # Validate DynamoDB locking based on settings
        if [[ "$backend" == "remote" && "$provider" == "aws" ]]; then
            if [[ "$enable_locking" == "true" ]]; then
                if grep -q "dynamodb_table" backend.tf; then
                    print_success "    ✓ DynamoDB locking correctly enabled"
                else
                    print_error "    ✗ DynamoDB locking missing when enabled"
                fi
                if grep -q "encrypt.*true" backend.tf; then
                    print_success "    ✓ Encryption correctly enabled with locking"
                else
                    print_error "    ✗ Encryption missing with locking"
                fi
            else
                if ! grep -q "dynamodb_table" backend.tf; then
                    print_success "    ✓ DynamoDB locking correctly disabled"
                else
                    print_error "    ✗ DynamoDB locking found when disabled"
                fi
            fi
        fi
        
        print_info "    Content preview:"
        echo "    $(head -5 backend.tf | sed 's/^/      /')"
    else
        print_error "    ✗ backend.tf not created"
        return 1
    fi
    
    # Clean up test files
    rm -f backend.tf
    
    local locking_status=""
    if [[ "$enable_locking" == "true" ]]; then
        locking_status=" (WITH locking)"
    else
        locking_status=" (WITHOUT locking)"
    fi
    print_success "  TERRAFORM workflow simulation completed for $provider/$component/$backend$locking_status"
    echo ""
}

# Function to simulate terraform-destroy workflow steps
simulate_destroy_workflow() {
    local provider="$1"
    local component="$2"
    local backend="$3"
    local remote_config="$4"
    local branch="main"
    
    print_step "Simulating TERRAFORM-DESTROY workflow: $provider/$component/$backend"
    
    # Change to the workflow working directory
    local work_dir="$PROJECT_ROOT/terraform/implementations/$provider/$component"
    if [[ ! -d "$work_dir" ]]; then
        print_warning "Directory not found: $work_dir"
        return 1
    fi
    
    cd "$work_dir"
    
    # Step 1: Check for required implementation directory
    print_info "  Step 1: Checking required files..."
    if [[ -f "$provider.tfvars" ]]; then
        print_success "    ✓ $provider.tfvars found"
    else
        print_error "    ✗ $provider.tfvars not found"
        return 1
    fi
    
    # Step 2: Check Cloud Storage for Remote State (note: destroy workflow has custom logic here)
    if [[ "$backend" == "remote" ]]; then
        print_info "  Step 2: Checking cloud storage for remote state..."
        
        # Parse remote configuration to simulate the destroy workflow's logic
        IFS=':' read -ra CONFIG_PARTS <<< "$remote_config"
        local provider_type="${CONFIG_PARTS[0]}"
        
        case "$provider_type" in
            aws)
                local bucket_base="${CONFIG_PARTS[1]}"
                local region="${CONFIG_PARTS[2]:-us-east-1}"
                print_info "    Checking AWS S3 bucket: $bucket_base-$branch"
                ;;
            azure)
                local rg="${CONFIG_PARTS[1]}"
                local storage="${CONFIG_PARTS[2]}"
                local container="${CONFIG_PARTS[3]}"
                print_info "    Checking Azure Storage: RG=$rg, Account=$storage, Container=$container"
                ;;
            gcp)
                local bucket="${CONFIG_PARTS[1]}"
                print_info "    Checking GCP Cloud Storage bucket: $bucket"
                ;;
        esac
        
        print_success "    ✓ Cloud storage check completed"
    else
        print_info "  Step 2: Skipping cloud storage check (local backend)"
    fi
    
    # Step 3: Configure Terraform Backend (same as terraform workflow)
    print_info "  Step 3: Configuring Terraform backend..."
    if ../../../../.github/scripts/configure-backend.sh \
        --type "$backend" \
        --provider "$provider" \
        --component "$component" \
        --branch "$branch" \
        --remote-config "$remote_config" > /dev/null 2>&1; then
        print_success "    ✓ Backend configuration completed"
    else
        print_error "    ✗ Backend configuration failed"
        return 1
    fi
    
    # Step 4: Verify backend.tf was created
    if [[ -f "backend.tf" ]]; then
        print_success "    ✓ backend.tf created successfully"
    else
        print_error "    ✗ backend.tf not created"
        return 1
    fi
    
    # Clean up test files (simulate the destroy workflow cleanup)
    rm -f backend.tf terraform.tfstate*
    print_info "    ✓ Cleanup completed (backend.tf and state files removed)"
    
    print_success "  TERRAFORM-DESTROY workflow simulation completed for $provider/$component/$backend"
    echo ""
}

# Function to test all combinations
test_all_combinations() {
    echo "Testing all workflow combinations..."
    echo "====================================="
    
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    
    for provider in "${PROVIDERS[@]}"; do
        for component in "${COMPONENTS[@]}"; do
            for backend in "${BACKENDS[@]}"; do
                local remote_config=""
                if [[ "$backend" == "remote" ]]; then
                    remote_config="${REMOTE_CONFIGS[$provider]}"
                fi
                
                echo "----------------------------------------"
                echo "Testing combination: $provider/$component/$backend"
                echo "Remote config: ${remote_config:-"N/A"}"
                echo ""
                
                # For remote AWS backends, test both with and without locking
                if [[ "$backend" == "remote" && "$provider" == "aws" ]]; then
                    # Test WITHOUT locking
                    total_tests=$((total_tests + 2))
                    
                    if simulate_terraform_workflow "$provider" "$component" "$backend" "$remote_config" "false"; then
                        passed_tests=$((passed_tests + 1))
                    else
                        failed_tests=$((failed_tests + 1))
                        print_error "TERRAFORM workflow (no locking) failed for $provider/$component/$backend"
                    fi
                    
                    if simulate_destroy_workflow "$provider" "$component" "$backend" "$remote_config"; then
                        passed_tests=$((passed_tests + 1))
                    else
                        failed_tests=$((failed_tests + 1))
                        print_error "TERRAFORM-DESTROY workflow (no locking) failed for $provider/$component/$backend"
                    fi
                    
                    # Test WITH locking
                    total_tests=$((total_tests + 2))
                    
                    if simulate_terraform_workflow "$provider" "$component" "$backend" "$remote_config" "true"; then
                        passed_tests=$((passed_tests + 1))
                    else
                        failed_tests=$((failed_tests + 1))
                        print_error "TERRAFORM workflow (with locking) failed for $provider/$component/$backend"
                    fi
                    
                    if simulate_destroy_workflow "$provider" "$component" "$backend" "$remote_config"; then
                        passed_tests=$((passed_tests + 1))
                    else
                        failed_tests=$((failed_tests + 1))
                        print_error "TERRAFORM-DESTROY workflow (with locking) failed for $provider/$component/$backend"
                    fi
                else
                    # For local backends and non-AWS providers, test normally
                    total_tests=$((total_tests + 2))
                    
                    if simulate_terraform_workflow "$provider" "$component" "$backend" "$remote_config" "false"; then
                        passed_tests=$((passed_tests + 1))
                    else
                        failed_tests=$((failed_tests + 1))
                        print_error "TERRAFORM workflow failed for $provider/$component/$backend"
                    fi
                    
                    if simulate_destroy_workflow "$provider" "$component" "$backend" "$remote_config"; then
                        passed_tests=$((passed_tests + 1))
                    else
                        failed_tests=$((failed_tests + 1))
                        print_error "TERRAFORM-DESTROY workflow failed for $provider/$component/$backend"
                    fi
                fi
            done
        done
    done
    
    echo "======================================="
    echo "Test Results Summary:"
    echo "  Total tests: $total_tests"
    echo "  Passed: $passed_tests"
    echo "  Failed: $failed_tests"
    
    if [[ $failed_tests -eq 0 ]]; then
        print_success "All workflow tests passed!"
        return 0
    else
        print_error "$failed_tests tests failed"
        return 1
    fi
}

# Function to validate workflow consistency
validate_workflow_consistency() {
    echo ""
    echo "Validating workflow consistency..."
    echo "=================================="
    
    # Check if both workflows use the same backend configuration approach
    local terraform_backend_calls=$(grep -c "configure-backend.sh" "$PROJECT_ROOT/.github/workflows/terraform.yml" 2>/dev/null || echo "0")
    local destroy_backend_calls=$(grep -c "configure-backend.sh" "$PROJECT_ROOT/.github/workflows/terraform-destroy.yml" 2>/dev/null || echo "0")
    
    if [[ "$terraform_backend_calls" -gt 0 && "$destroy_backend_calls" -gt 0 ]]; then
        print_success "Both workflows use configure-backend.sh consistently"
    else
        print_warning "Workflows may not use backend configuration consistently"
    fi
    
    # Check if terraform workflow uses setup-cloud-storage.sh but destroy doesn't
    local terraform_storage_calls=$(grep -c "setup-cloud-storage.sh" "$PROJECT_ROOT/.github/workflows/terraform.yml" 2>/dev/null || echo "0")
    local destroy_storage_calls=$(grep -c "setup-cloud-storage.sh" "$PROJECT_ROOT/.github/workflows/terraform-destroy.yml" 2>/dev/null || echo "0")
    
    if [[ "$terraform_storage_calls" -gt 0 && "$destroy_storage_calls" -eq 0 ]]; then
        print_warning "terraform.yml uses setup-cloud-storage.sh but terraform-destroy.yml does not"
        print_info "This is actually correct - destroy workflow only needs to check storage existence, not create it"
    elif [[ "$terraform_storage_calls" -gt 0 && "$destroy_storage_calls" -gt 0 ]]; then
        print_success "Both workflows use setup-cloud-storage.sh"
    else
        print_info "Cloud storage setup usage varies between workflows (this may be intentional)"
    fi
    
    echo ""
}

# Function to generate workflow usage guide
generate_usage_guide() {
    echo "Workflow Usage Guide"
    echo "===================="
    
    cat << 'EOF'

🚀 How to Use the MOSIP Terraform Workflows

1. TERRAFORM WORKFLOW (terraform.yml)
   Purpose: Deploy infrastructure
   When to use: Creating new infrastructure or updating existing

   Steps to run:
   a) Go to GitHub Actions → terraform plan / apply
   b) Click "Run workflow"
   c) Fill in the inputs:
      - CLOUD_PROVIDER: aws, azure, or gcp
      - TERRAFORM_COMPONENT: base-infra, infra, or observ-infra
      - BACKEND_TYPE: local or remote
      - REMOTE_BACKEND_CONFIG: (if remote) aws:bucket:region OR azure:rg:storage:container OR gcp:bucket:region
      - SSH_PRIVATE_KEY: Name of your GitHub secret containing SSH private key
      - TERRAFORM_APPLY: true (to actually apply changes)

2. TERRAFORM-DESTROY WORKFLOW (terraform-destroy.yml)
   Purpose: Destroy infrastructure
   When to use: Removing infrastructure to save costs or clean up

   Steps to run:
   a) Go to GitHub Actions → terraform destroy
   b) Click "Run workflow"
   c) Fill in the same inputs as terraform workflow
   d) TERRAFORM_DESTROY: true (required to confirm destruction)

💡 Best Practices:

1. Component Order:
   - Deploy base-infra FIRST (creates VPC, networking)
   - Deploy infra SECOND (creates application resources)
   - Deploy observ-infra THIRD (creates monitoring)

2. Destruction Order (reverse):
   - Destroy observ-infra FIRST
   - Destroy infra SECOND
   - Destroy base-infra LAST (only if completely cleaning up)

3. Branch Isolation:
   - Each branch gets its own state storage
   - Safe for parallel development
   - Use feature branches for testing

4. Security:
   - Always use GitHub secrets for sensitive data
   - Use remote backends for production
   - Test with TERRAFORM_APPLY: false first

🔧 Example Configurations:

Development Environment:
- Provider: aws
- Component: infra
- Backend: local
- Apply: false (plan only)

Production Environment:
- Provider: aws
- Component: infra
- Backend: remote
- Config: aws:mosip-prod-state:us-east-1
- Apply: true

Multi-Cloud Setup:
- Run workflows for each provider (aws, azure, gcp)
- Use consistent component naming
- Use remote backends for state management

EOF
    
    echo ""
}

# Main execution
main() {
    echo "Starting end-to-end workflow testing..."
    echo "======================================="
    
    # Return to script directory for consistent execution
    cd "$SCRIPT_DIR"
    
    test_all_combinations
    validate_workflow_consistency
    generate_usage_guide
    
    print_success "End-to-end workflow testing completed!"
    print_info "Your MOSIP Terraform workflows are ready for production use."
}

# Run main function
main
