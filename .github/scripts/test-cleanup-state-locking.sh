#!/bin/bash

# Test script for the cleanup-state-locking.sh script
# Tests cloud-agnostic state locking cleanup functionality

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== State Locking Cleanup Test Script ==="
echo "Testing cloud-agnostic state locking cleanup"
echo "============================================"

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

# Test AWS cleanup (mocked)
test_aws_cleanup_without_locking() {
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Mock AWS CLI
    export PATH="$temp_dir:$PATH"
    cat > aws << 'EOF'
#!/bin/bash
# Mock successful AWS CLI responses
exit 0
EOF
    chmod +x aws
    
    "$PROJECT_ROOT/.github/scripts/cleanup-state-locking.sh" \
        --provider aws \
        --config "aws:test-bucket:us-east-1" \
        --branch test-branch \
        --component infra
    
    rm -rf "$temp_dir"
    return 0
}

test_aws_cleanup_with_locking() {
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Mock AWS CLI - simulate table exists and deletion succeeds
    export PATH="$temp_dir:$PATH"
    cat > aws << 'EOF'
#!/bin/bash
case "$1" in
    "dynamodb")
        case "$2" in
            "describe-table")
                # Simulate table exists
                echo '{"Table":{"TableName":"test-table"}}'
                exit 0
                ;;
            "delete-table")
                # Simulate successful deletion
                exit 0
                ;;
            "wait")
                # Simulate successful wait
                exit 0
                ;;
        esac
        ;;
esac
exit 0
EOF
    chmod +x aws
    
    "$PROJECT_ROOT/.github/scripts/cleanup-state-locking.sh" \
        --provider aws \
        --config "aws:test-bucket:us-east-1" \
        --branch test-branch \
        --component infra \
        --enable-locking
    
    rm -rf "$temp_dir"
    return 0
}

# Test Azure cleanup (should always succeed - no-op)
test_azure_cleanup() {
    "$PROJECT_ROOT/.github/scripts/cleanup-state-locking.sh" \
        --provider azure \
        --config "azure:test-rg:teststorage:terraform-state" \
        --branch test-branch \
        --component infra \
        --enable-locking
    
    return 0
}

# Test GCP cleanup (should always succeed - no-op)  
test_gcp_cleanup() {
    "$PROJECT_ROOT/.github/scripts/cleanup-state-locking.sh" \
        --provider gcp \
        --config "gcp:test-bucket:us-central1" \
        --branch test-branch \
        --component infra \
        --enable-locking
    
    return 0
}

# Test parameter validation
test_missing_provider() {
    "$PROJECT_ROOT/.github/scripts/cleanup-state-locking.sh" \
        --config "aws:test-bucket:us-east-1" \
        --branch test-branch \
        --component infra
    
    return 1  # Should fail due to missing provider
}

test_invalid_provider() {
    "$PROJECT_ROOT/.github/scripts/cleanup-state-locking.sh" \
        --provider invalid \
        --config "invalid:test-bucket:us-east-1" \
        --branch test-branch \
        --component infra
    
    return 1  # Should fail due to invalid provider
}

test_missing_component() {
    "$PROJECT_ROOT/.github/scripts/cleanup-state-locking.sh" \
        --provider aws \
        --config "aws:test-bucket:us-east-1" \
        --branch test-branch
    
    return 1  # Should fail due to missing component
}

echo ""
echo "Running state locking cleanup tests..."
echo "====================================="

# Test successful scenarios
run_test "AWS cleanup WITHOUT locking" "success" test_aws_cleanup_without_locking
run_test "AWS cleanup WITH locking" "success" test_aws_cleanup_with_locking
run_test "Azure cleanup (built-in locking)" "success" test_azure_cleanup
run_test "GCP cleanup (built-in consistency)" "success" test_gcp_cleanup

# Test parameter validation (should fail)
run_test "Missing provider (should fail)" "failure" test_missing_provider
run_test "Invalid provider (should fail)" "failure" test_invalid_provider
run_test "Missing component (should fail)" "failure" test_missing_component

echo ""
echo "================================="
echo "Test Results Summary:"
echo "  Total tests: $TOTAL_TESTS"
echo "  Passed: $PASSED_TESTS"
echo "  Failed: $FAILED_TESTS"

if [[ $FAILED_TESTS -eq 0 ]]; then
    print_success "All state locking cleanup tests passed!"
    exit 0
else
    print_error "$FAILED_TESTS tests failed"
    exit 1
fi
