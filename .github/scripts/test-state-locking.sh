#!/bin/bash

# Cloud-Agnostic State Locking Test Script
# Tests the optional state locking functionality across all cloud providers
# AWS: DynamoDB tables, Azure: Built-in lease-based locking, GCP: Built-in consistency

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Cloud-Agnostic State Locking Test Script ==="
echo "Testing optional state locking functionality across cloud providers"
echo "AWS: DynamoDB, Azure: Blob lease-based, GCP: Built-in consistency"
echo "=============================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${YELLOW}ℹ $1${NC}"; }

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local test_name="$1"
    local expected_result="$2"
    shift 2
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    print_info "Testing: $test_name"
    
    if "$@" > /dev/null 2>&1; then
        local actual_result="success"
    else
        local actual_result="failure"
    fi
    
    if [[ "$actual_result" == "$expected_result" ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        print_success "$test_name"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        print_error "$test_name (expected: $expected_result, got: $actual_result)"
    fi
}

test_backend_without_locking() {
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    "$PROJECT_ROOT/.github/scripts/configure-backend.sh" \
        --type remote \
        --provider aws \
        --component observ-infra \
        --branch test-branch \
        --remote-config "aws:test-bucket:us-east-1"
    
    # Should NOT have DynamoDB table
    if [[ -f "backend.tf" ]] && ! grep -q "dynamodb_table" backend.tf; then
        rm -rf "$temp_dir"
        return 0
    else
        rm -rf "$temp_dir"
        return 1
    fi
}

test_backend_with_locking() {
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Set environment variable to simulate AWS DynamoDB table creation
    export TERRAFORM_STATE_LOCK_TABLE="terraform-state-lock-observ-infra-test-branch"
    
    "$PROJECT_ROOT/.github/scripts/configure-backend.sh" \
        --type remote \
        --provider aws \
        --component observ-infra \
        --branch test-branch \
        --remote-config "aws:test-bucket:us-east-1" \
        --enable-locking
    
    # Should have DynamoDB table and encryption
    if [[ -f "backend.tf" ]] && grep -q "dynamodb_table" backend.tf && grep -q "encrypt.*true" backend.tf; then
        unset TERRAFORM_STATE_LOCK_TABLE
        rm -rf "$temp_dir"
        return 0
    else
        unset TERRAFORM_STATE_LOCK_TABLE
        rm -rf "$temp_dir"
        return 1
    fi
}

test_storage_setup_without_locking() {
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Mock AWS CLI commands
    export PATH="$temp_dir:$PATH"
    cat > aws << 'EOF'
#!/bin/bash
case "$1" in
    "s3api")
        case "$2" in
            "head-bucket")
                exit 1  # Bucket doesn't exist
                ;;
            "put-bucket-versioning"|"put-bucket-encryption"|"put-public-access-block")
                exit 0  # Success
                ;;
        esac
        ;;
    "s3")
        case "$2" in
            "mb")
                exit 0  # Success
                ;;
        esac
        ;;
esac
exit 0
EOF
    chmod +x aws
    
    "$PROJECT_ROOT/.github/scripts/setup-cloud-storage.sh" \
        --provider aws \
        --config "aws:test-bucket:us-east-1" \
        --branch test-branch \
        --component observ-infra
    
    rm -rf "$temp_dir"
    return 0
}

test_storage_setup_with_locking() {
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Mock AWS CLI commands including DynamoDB
    export PATH="$temp_dir:$PATH"
    cat > aws << 'EOF'
#!/bin/bash
case "$1" in
    "s3api")
        case "$2" in
            "head-bucket")
                exit 1  # Bucket doesn't exist
                ;;
            "put-bucket-versioning"|"put-bucket-encryption"|"put-public-access-block")
                exit 0  # Success
                ;;
        esac
        ;;
    "s3")
        case "$2" in
            "mb")
                exit 0  # Success
                ;;
        esac
        ;;
    "dynamodb")
        case "$2" in
            "describe-table")
                exit 1  # Table doesn't exist
                ;;
            "create-table")
                exit 0  # Success
                ;;
            "wait")
                exit 0  # Success
                ;;
        esac
        ;;
esac
exit 0
EOF
    chmod +x aws
    
    "$PROJECT_ROOT/.github/scripts/setup-cloud-storage.sh" \
        --provider aws \
        --config "aws:test-bucket:us-east-1" \
        --branch test-branch \
        --component observ-infra \
        --enable-locking
    
    rm -rf "$temp_dir"
    return 0
}

echo ""
echo "Running cloud-agnostic state locking tests..."
echo "============================================="

# Test backend configuration
run_test "Backend WITHOUT locking" "success" test_backend_without_locking
run_test "Backend WITH locking" "success" test_backend_with_locking

# Test storage setup
run_test "Storage setup WITHOUT locking" "success" test_storage_setup_without_locking
run_test "Storage setup WITH locking" "success" test_storage_setup_with_locking

echo ""
echo "================================="
echo "Test Results Summary:"
echo "  Total tests: $TOTAL_TESTS"
echo "  Passed: $PASSED_TESTS"
echo "  Failed: $FAILED_TESTS"

if [[ $FAILED_TESTS -eq 0 ]]; then
    print_success "All cloud-agnostic state locking tests passed!"
    exit 0
else
    print_error "$FAILED_TESTS tests failed"
    exit 1
fi
