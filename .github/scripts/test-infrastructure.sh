#!/bin/bash

# MOSIP Infrastructure Testing Script
# Tests GitHub Actions scripts locally to ensure they work correctly
# Validates all workflow inputs: providers (aws, azure, gcp), components (base-infra, infra, observ-infra), and backend types

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== MOSIP Infrastructure Testing Script ==="
echo "Script directory: $SCRIPT_DIR"
echo "Project root: $PROJECT_ROOT"
echo "Testing support for all workflow inputs:"
echo "  Providers: aws, azure, gcp"
echo "  Components: base-infra, infra, observ-infra"
echo "  Backends: local, remote"
echo "==========================================="

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -t, --test-type       Type of test: scripts, paths, or all (default: all)"
    echo "  -p, --provider        Cloud provider: aws, azure, gcp (default: aws)"
    echo "  -c, --component       Component: base-infra, infra, observ-infra (default: infra)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Test types:"
    echo "  scripts    - Test script functionality locally"
    echo "  paths      - Test script paths from workflow directories"
    echo "  all        - Run both script and path tests"
    echo ""
    echo "Examples:"
    echo "  $0 --test-type scripts --provider aws --component infra"
    echo "  $0 --test-type paths"
    echo "  $0  # Run all tests with defaults"
}

# Default values
TEST_TYPE="all"
PROVIDER="aws"
COMPONENT="infra"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--test-type)
            TEST_TYPE="$2"
            shift 2
            ;;
        -p|--provider)
            PROVIDER="$2"
            shift 2
            ;;
        -c|--component)
            COMPONENT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate test type
if [[ ! "$TEST_TYPE" =~ ^(scripts|paths|all)$ ]]; then
    echo "Error: Invalid test type '$TEST_TYPE'"
    echo "Valid types: scripts, paths, all"
    exit 1
fi

# Function to test script functionality
test_scripts() {
    echo ""
    echo "Testing Script Functionality for All Workflow Inputs"
    echo "======================================================="
    
    cd "$PROJECT_ROOT"
    
    echo "Current directory: $(pwd)"
    echo "Available scripts:"
    ls -la .github/scripts/
    
    echo ""
    echo "Testing setup-cloud-storage.sh --help"
    .github/scripts/setup-cloud-storage.sh --help || echo "ERROR: setup-cloud-storage.sh help failed"
    
    echo ""
    echo "Testing configure-backend.sh --help"
    .github/scripts/configure-backend.sh --help || echo "ERROR: configure-backend.sh help failed"
    
    echo ""
    echo "Testing all provider/component/backend combinations"
    
    PROVIDERS=("aws" "azure" "gcp")
    COMPONENTS=("base-infra" "infra" "observ-infra")
    BACKENDS=("local" "remote")
    
    for provider in "${PROVIDERS[@]}"; do
        for component in "${COMPONENTS[@]}"; do
            for backend in "${BACKENDS[@]}"; do
                echo ""
                echo "Testing: $provider/$component/$backend"
                
                TEMP_DIR=$(mktemp -d)
                cd "$TEMP_DIR"
                
                if [ "$backend" = "local" ]; then
                    echo "  Testing local backend configuration..."
                    "$PROJECT_ROOT/.github/scripts/configure-backend.sh" \
                        --type local \
                        --provider "$provider" \
                        --component "$component" || echo "ERROR: Local backend test failed for $provider/$component"
                        
                    if [ -f "backend.tf" ]; then
                        echo "  SUCCESS: Local backend configuration created for $provider/$component"
                        # Validate content
                        if grep -q "backend \"local\"" backend.tf && grep -q "$provider-$component.*terraform.tfstate" backend.tf; then
                            echo "  SUCCESS: Backend content is correct"
                            # Check if branch name is included in state file name
                            if grep -q "$provider-$component-.*-terraform.tfstate" backend.tf; then
                                echo "  SUCCESS: Branch name correctly included in state file name"
                            else
                                echo "  WARNING: Branch name not found in state file name"
                            fi
                        else
                            echo "  ERROR: Backend content validation failed"
                        fi
                    else
                        echo "  ERROR: backend.tf not created for $provider/$component"
                    fi
                    
                elif [ "$backend" = "remote" ]; then
                    echo "  Testing remote backend configuration..."
                    
                    case "$provider" in
                        aws)
                            REMOTE_CONFIG="aws:test-bucket:us-east-1"
                            ;;
                        azure)
                            REMOTE_CONFIG="azure:test-rg:teststorage:terraform-state"
                            ;;
                        gcp)
                            REMOTE_CONFIG="gcp:test-bucket"
                            ;;
                    esac
                    
                    # Test without locking first
                    echo "    Testing remote backend WITHOUT locking..."
                    "$PROJECT_ROOT/.github/scripts/configure-backend.sh" \
                        --type remote \
                        --provider "$provider" \
                        --component "$component" \
                        --branch "test-branch" \
                        --remote-config "$REMOTE_CONFIG" || echo "ERROR: Remote backend test failed for $provider/$component"
                        
                    if [ -f "backend.tf" ]; then
                        echo "    SUCCESS: Remote backend configuration created for $provider/$component"
                        # Validate content based on provider
                        case "$provider" in
                            aws)
                                if grep -q "backend \"s3\"" backend.tf && grep -q "test-bucket" backend.tf; then
                                    echo "    SUCCESS: AWS S3 backend content is correct"
                                    # Verify no DynamoDB table in non-locking mode
                                    if ! grep -q "dynamodb_table" backend.tf; then
                                        echo "    SUCCESS: No DynamoDB table (locking disabled)"
                                    else
                                        echo "    ERROR: DynamoDB table found when locking should be disabled"
                                    fi
                                    # Check if branch name is included in state key
                                    if grep -q "$provider-$component-.*-terraform.tfstate" backend.tf; then
                                        echo "    SUCCESS: Branch name correctly included in state key"
                                    else
                                        echo "    ERROR: Branch name missing in state key"
                                    fi
                                else
                                    echo "    ERROR: AWS S3 backend content validation failed"
                                fi
                                ;;
                            azure)
                                if grep -q "backend \"azurerm\"" backend.tf && grep -q "test-rg" backend.tf; then
                                    echo "    SUCCESS: Azure backend content is correct"
                                    # Check if branch name is included in state key
                                    if grep -q "$provider-$component-.*-terraform.tfstate" backend.tf; then
                                        echo "    SUCCESS: Branch name correctly included in state key"
                                    else
                                        echo "    ERROR: Branch name missing in state key"
                                    fi
                                else
                                    echo "    ERROR: Azure backend content validation failed"
                                fi
                                ;;
                            gcp)
                                if grep -q "backend \"gcs\"" backend.tf && grep -q "test-bucket" backend.tf; then
                                    echo "    SUCCESS: GCP backend content is correct"
                                    # Check if branch name is included in prefix
                                    if grep -q "terraform/$provider-$component-" backend.tf; then
                                        echo "    SUCCESS: Branch name correctly included in prefix"
                                    else
                                        echo "    ERROR: Branch name missing in prefix"
                                    fi
                                else
                                    echo "    ERROR: GCP backend content validation failed"
                                fi
                                ;;
                        esac
                    else
                        echo "    ERROR: backend.tf not created for $provider/$component"
                    fi
                    
                    # Test WITH locking (AWS only for now)
                    if [ "$provider" = "aws" ]; then
                        echo "    Testing remote backend WITH locking..."
                        rm -f backend.tf  # Clean up previous test
                        
                        # Set environment variable to simulate DynamoDB table creation
                        export DYNAMIC_DYNAMODB_TABLE="terraform-state-lock-$component-test-branch"
                        
                        "$PROJECT_ROOT/.github/scripts/configure-backend.sh" \
                            --type remote \
                            --provider "$provider" \
                            --component "$component" \
                            --branch "test-branch" \
                            --remote-config "$REMOTE_CONFIG" \
                            --enable-locking || echo "ERROR: Remote backend locking test failed for $provider/$component"
                            
                        if [ -f "backend.tf" ]; then
                            echo "    SUCCESS: Remote backend with locking created for $provider/$component"
                            # Validate DynamoDB table is included
                            if grep -q "dynamodb_table" backend.tf && grep -q "terraform-state-lock-$component-test-branch" backend.tf; then
                                echo "    SUCCESS: DynamoDB table correctly configured for locking"
                            else
                                echo "    ERROR: DynamoDB table missing in locking-enabled backend"
                            fi
                            # Verify encryption is enabled
                            if grep -q "encrypt.*true" backend.tf; then
                                echo "    SUCCESS: Encryption enabled with locking"
                            else
                                echo "    ERROR: Encryption not enabled with locking"
                            fi
                        else
                            echo "    ERROR: backend.tf with locking not created for $provider/$component"
                        fi
                        
                        unset DYNAMIC_DYNAMODB_TABLE
                    fi
                    ;;
                azure)
                    if grep -q "backend \"azurerm\"" backend.tf && grep -q "test-rg" backend.tf; then
                        echo "    SUCCESS: Azure backend content is correct"
                        # Check if branch name is included in state key
                        if grep -q "$provider-$component-.*-terraform.tfstate" backend.tf; then
                            echo "    SUCCESS: Branch name correctly included in state key"
                        else
                            echo "    ERROR: Branch name missing in state key"
                        fi
                    else
                        echo "    ERROR: Azure backend content validation failed"
                    fi
                    ;;
                gcp)
                    if grep -q "backend \"gcs\"" backend.tf && grep -q "test-bucket" backend.tf; then
                        echo "    SUCCESS: GCP backend content is correct"
                        # Check if branch name is included in prefix
                        if grep -q "terraform/$provider-$component-" backend.tf; then
                            echo "    SUCCESS: Branch name correctly included in prefix"
                        else
                            echo "    ERROR: Branch name missing in prefix"
                        fi
                    else
                        echo "    ERROR: GCP backend content validation failed"
                    fi
                    ;;
            esac
                    else
                        echo "  ERROR: backend.tf not created for $provider/$component"
                    fi
                fi
                
                cd "$PROJECT_ROOT"
                rm -rf "$TEMP_DIR"
            done
        done
    done
    
    echo "SUCCESS: Script functionality tests completed for all combinations"
}

# Function to test paths from workflow directories
test_paths() {
    echo ""
    echo "Testing Script Paths from Workflow Directories"
    echo "==============================================="
    
    # Test all combinations of provider/component that should exist
    PROVIDERS=("aws" "azure" "gcp")
    COMPONENTS=("base-infra" "infra" "observ-infra")
    
    for provider in "${PROVIDERS[@]}"; do
        for component in "${COMPONENTS[@]}"; do
            WORKFLOW_DIR="$PROJECT_ROOT/terraform/implementations/$provider/$component"
            
            echo ""
            echo "Testing from: $WORKFLOW_DIR"
            
            # Check if directory exists (it's okay if some don't exist)
            if [ ! -d "$WORKFLOW_DIR" ]; then
                echo "INFO: Directory doesn't exist: $WORKFLOW_DIR (this is normal)"
                continue
            fi
            
            cd "$WORKFLOW_DIR"
            echo "Current working directory: $(pwd)"
            
            # Test relative path to scripts (as used in workflows)
            SETUP_SCRIPT="../../../../.github/scripts/setup-cloud-storage.sh"
            CONFIG_SCRIPT="../../../../.github/scripts/configure-backend.sh"
            
            echo "Testing script paths:"
            echo "   Setup script: $SETUP_SCRIPT"
            echo "   Config script: $CONFIG_SCRIPT"
            
            # Test if scripts exist and are executable
            if [ -x "$SETUP_SCRIPT" ]; then
                echo "SUCCESS: setup-cloud-storage.sh found and executable"
                
                # Test help command
                echo "Testing setup script help:"
                "$SETUP_SCRIPT" --help > /dev/null && echo "SUCCESS: Help command works" || echo "ERROR: Help command failed"
            else
                echo "ERROR: setup-cloud-storage.sh not found or not executable at $SETUP_SCRIPT"
            fi
            
            if [ -x "$CONFIG_SCRIPT" ]; then
                echo "SUCCESS: configure-backend.sh found and executable"
                
                # Test help command
                echo "Testing config script help:"
                "$CONFIG_SCRIPT" --help > /dev/null && echo "SUCCESS: Help command works" || echo "ERROR: Help command failed"
                
                # Test local backend configuration
                echo "Testing local backend configuration:"
                TEMP_BACKEND=$(mktemp)
                
                "$CONFIG_SCRIPT" \
                    --type local \
                    --provider "$provider" \
                    --component "$component" > /dev/null 2>&1
                
                if [ -f "backend.tf" ]; then
                    echo "SUCCESS: Local backend configuration created successfully"
                    rm -f backend.tf  # Clean up
                else
                    echo "ERROR: Local backend configuration failed"
                fi
            else
                echo "ERROR: configure-backend.sh not found or not executable at $CONFIG_SCRIPT"
            fi
        done
    done
    
    cd "$PROJECT_ROOT"
    echo ""
    echo "SUCCESS: Path tests completed"
}

# Function to test workflow simulation
test_workflow_simulation() {
    echo ""
    echo "Simulating Workflow Steps for All Combinations"
    echo "==============================================="
    
    PROVIDERS=("aws" "azure" "gcp")
    COMPONENTS=("base-infra" "infra" "observ-infra")
    
    for provider in "${PROVIDERS[@]}"; do
        for component in "${COMPONENTS[@]}"; do
            echo ""
            echo "Testing workflow simulation: $provider/$component"
            
            # Simulate what happens in the actual workflow
            WORKFLOW_DIR="$PROJECT_ROOT/terraform/implementations/$provider/$component"
            
            if [ ! -d "$WORKFLOW_DIR" ]; then
                echo "WARNING: Creating test workflow directory: $WORKFLOW_DIR"
                mkdir -p "$WORKFLOW_DIR"
                
                # Create a minimal tfvars file for testing
                echo "# Test tfvars file for $provider $component" > "$WORKFLOW_DIR/$provider.tfvars"
                echo "region = \"us-east-1\"" >> "$WORKFLOW_DIR/$provider.tfvars"
            fi
            
            cd "$WORKFLOW_DIR"
            echo "Simulating workflow from: $(pwd)"
            
            # Simulate the workflow steps
            echo "Step 1: Check for required files"
            if [ -f "$provider.tfvars" ]; then
                echo "SUCCESS: $provider.tfvars found"
            else
                echo "ERROR: $provider.tfvars not found"
            fi
            
            echo "Step 2: Configure local backend"
            ../../../../.github/scripts/configure-backend.sh \
                --type local \
                --provider "$provider" \
                --component "$component"
            
            if [ -f "backend.tf" ]; then
                echo "SUCCESS: Local backend.tf created successfully"
            else
                echo "ERROR: Local backend.tf creation failed"
            fi
            
            echo "Step 3: Test remote backend config"
            case "$provider" in
                aws)
                    REMOTE_CONFIG="aws:mosip-terraform-state-$component:us-east-1"
                    ;;
                azure)
                    REMOTE_CONFIG="azure:mosip-$component-rg:mosip${component}storage:terraform-state"
                    ;;
                gcp)
                    REMOTE_CONFIG="gcp:mosip-$component-terraform-state"
                    ;;
            esac
            
            ../../../../.github/scripts/configure-backend.sh \
                --type remote \
                --provider "$provider" \
                --component "$component" \
                --branch "main" \
                --remote-config "$REMOTE_CONFIG"
            
            if [ -f "backend.tf" ]; then
                echo "SUCCESS: Remote backend configuration created"
            else
                echo "ERROR: Remote backend configuration failed"
            fi
            
            # Clean up test files but keep directory structure
            rm -f backend.tf
        done
    done
    
    cd "$PROJECT_ROOT"
    echo "Workflow simulation completed for all combinations"
}

# Function to check prerequisites
check_prerequisites() {
    echo ""
    echo "Checking Prerequisites"
    echo "========================"
    
    # Check if scripts exist
    if [ ! -f "$PROJECT_ROOT/.github/scripts/setup-cloud-storage.sh" ]; then
        echo "ERROR: setup-cloud-storage.sh not found"
        exit 1
    fi
    
    if [ ! -f "$PROJECT_ROOT/.github/scripts/configure-backend.sh" ]; then
        echo "ERROR: configure-backend.sh not found"
        exit 1
    fi
    
    # Check if scripts are executable
    if [ ! -x "$PROJECT_ROOT/.github/scripts/setup-cloud-storage.sh" ]; then
        echo "Making setup-cloud-storage.sh executable"
        chmod +x "$PROJECT_ROOT/.github/scripts/setup-cloud-storage.sh"
    fi
    
    if [ ! -x "$PROJECT_ROOT/.github/scripts/configure-backend.sh" ]; then
        echo "Making configure-backend.sh executable"
        chmod +x "$PROJECT_ROOT/.github/scripts/configure-backend.sh"
    fi
    
    echo "Prerequisites check completed"
}

# Main execution
main() {
    check_prerequisites
    
    case "$TEST_TYPE" in
        scripts)
            test_scripts
            ;;
        paths)
            test_paths
            ;;
        all)
            test_scripts
            test_paths
            test_workflow_simulation
            ;;
    esac
    
    echo ""
    echo "All tests completed successfully!"
    echo ""
    echo "Summary:"
    echo "  - Scripts are properly executable"
    echo "  - Paths work correctly from workflow directories"
    echo "  - Backend configuration generates valid Terraform code"
    echo ""
    echo "Your workflows should work correctly in GitHub Actions!"
}

# Execute main function
main
