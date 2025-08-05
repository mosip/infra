#!/bin/bash

# MOSIP Cloud-Agnostic State Lock Cleanup Script  
# Cleans up state locking resources after terraform destroy
# AWS: Removes DynamoDB tables, Azure/GCP: No cleanup needed (built-in locking)

set -e  # Exit on any error

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -p, --provider        Cloud provider: aws, azure, gcp (required)"
    echo "  -c, --config          Remote backend config string (required for remote backend)"
    echo "  -b, --branch          Branch name for resource naming (required)"
    echo "  -t, --component       Component type: base-infra, infra, observ-infra (required)"
    echo "  --enable-locking      Cleanup state locking resources (optional)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Remote config formats:"
    echo "  AWS:   aws:bucket_base_name:region"
    echo "  Azure: azure:resource_group:storage_account:container"
    echo "  GCP:   gcp:bucket_name:region"
    echo ""
    echo "Examples:"
    echo "  $0 --provider aws --config 'aws:mosip-state:us-east-1' --branch main --component infra --enable-locking"
    echo "  $0 --provider azure --config 'azure:mosip-rg:mosipstate:terraform-state' --branch main --component infra"
    echo "  $0 --provider gcp --config 'gcp:mosip-terraform-state:us-central1' --branch main --component infra"
}

# Default values
CLOUD_PROVIDER=""
REMOTE_CONFIG=""
BRANCH_NAME=""
COMPONENT=""
ENABLE_LOCKING=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--provider)
            CLOUD_PROVIDER="$2"
            shift 2
            ;;
        -c|--config)
            REMOTE_CONFIG="$2"
            shift 2
            ;;
        -b|--branch)
            BRANCH_NAME="$2"
            shift 2
            ;;
        -t|--component)
            COMPONENT="$2"
            shift 2
            ;;
        --enable-locking)
            ENABLE_LOCKING=true
            shift
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

# Validate required parameters
if [[ -z "$CLOUD_PROVIDER" ]]; then
    echo "Error: Cloud provider is required"
    usage
    exit 1
fi

if [[ -z "$BRANCH_NAME" ]]; then
    echo "Error: Branch name is required"
    usage
    exit 1
fi

if [[ -z "$COMPONENT" ]]; then
    echo "Error: Component is required"
    usage
    exit 1
fi

# Validate cloud provider
if [[ ! "$CLOUD_PROVIDER" =~ ^(aws|azure|gcp)$ ]]; then
    echo "Error: Invalid cloud provider: $CLOUD_PROVIDER"
    echo "Valid providers: aws, azure, gcp"
    exit 1
fi

# Validate component
if [[ ! "$COMPONENT" =~ ^(base-infra|infra|observ-infra)$ ]]; then
    echo "Error: Invalid component: $COMPONENT"
    echo "Valid components: base-infra, infra, observ-infra"
    exit 1
fi

echo "=== MOSIP Cloud-Agnostic State Lock Cleanup ==="
echo "Provider: $CLOUD_PROVIDER"
echo "Component: $COMPONENT"
echo "Branch: $BRANCH_NAME"
echo "State Locking Cleanup: $ENABLE_LOCKING"
echo "================================================"

# Function to cleanup AWS DynamoDB tables
cleanup_aws_state_locking() {
    local component="$1"
    local branch_name="$2"
    local region="$3"
    
    if [ "$ENABLE_LOCKING" != true ]; then
        echo "AWS state locking cleanup disabled - skipping DynamoDB table cleanup"
        return 0
    fi
    
    local lock_table_name="terraform-state-lock-${component}-${branch_name}"
    
    echo "Cleaning up AWS DynamoDB table: $lock_table_name"
    echo "Region: $region"
    
    # Check if DynamoDB table exists
    if aws dynamodb describe-table --table-name "$lock_table_name" --region "$region" 2>/dev/null; then
        echo "DynamoDB table exists - proceeding with deletion"
        
        # Delete the DynamoDB table
        if aws dynamodb delete-table --table-name "$lock_table_name" --region "$region"; then
            echo "DynamoDB table deletion initiated successfully"
            
            # Wait for table to be deleted (optional - can be done in background)
            echo "Waiting for table deletion to complete..."
            aws dynamodb wait table-not-exists --table-name "$lock_table_name" --region "$region" 2>/dev/null || {
                echo "Wait timeout - table deletion may still be in progress"
                echo "Check AWS console to confirm deletion completion"
            }
            
            echo "DynamoDB table cleanup completed"
        else
            echo "ERROR: Failed to delete DynamoDB table"
            echo "Manual cleanup may be required"
            return 1
        fi
    else
        echo "DynamoDB table not found - may already be deleted or was never created"
    fi
}

# Function to cleanup Azure state locking (no-op - built-in locking)
cleanup_azure_state_locking() {
    local component="$1"
    local branch_name="$2"
    
    echo "Azure state locking cleanup:"
    echo "  Azure uses built-in blob lease-based locking"
    echo "  No additional cleanup required - locking resources are part of storage account"
    echo "  Storage account cleanup is handled separately if needed"
}

# Function to cleanup GCP state locking (no-op - built-in locking)
cleanup_gcp_state_locking() {
    local component="$1"
    local branch_name="$2"
    
    echo "GCP state locking cleanup:"
    echo "  GCP uses built-in object consistency and versioning"
    echo "  No additional cleanup required - locking is part of Cloud Storage"
    echo "  Bucket cleanup is handled separately if needed"
}

# Main cleanup logic based on provider
case "$CLOUD_PROVIDER" in
    aws)
        if [ -n "$REMOTE_CONFIG" ]; then
            # Parse AWS config to get region
            IFS=':' read -ra CONFIG_PARTS <<< "$REMOTE_CONFIG"
            if [ ${#CONFIG_PARTS[@]} -lt 3 ]; then
                echo "Error: AWS config requires format: aws:bucket_base_name:region"
                exit 1
            fi
            
            BUCKET_BASE_NAME="${CONFIG_PARTS[1]}"
            REGION="${CONFIG_PARTS[2]}"
            
            if [ -z "$REGION" ]; then
                echo "Error: Region is required for AWS state locking cleanup"
                exit 1
            fi
            
            cleanup_aws_state_locking "$COMPONENT" "$BRANCH_NAME" "$REGION"
        else
            echo "No remote config provided - assuming local backend (no cleanup needed)"
        fi
        ;;
        
    azure)
        cleanup_azure_state_locking "$COMPONENT" "$BRANCH_NAME"
        ;;
        
    gcp)
        cleanup_gcp_state_locking "$COMPONENT" "$BRANCH_NAME"
        ;;
        
    *)
        echo "Error: Unsupported cloud provider: $CLOUD_PROVIDER"
        exit 1
        ;;
esac

echo ""
echo "State locking cleanup completed for $CLOUD_PROVIDER!"
echo ""
echo "Summary:"
case "$CLOUD_PROVIDER" in
    aws)
        if [ "$ENABLE_LOCKING" = true ]; then
            echo "  ✅ AWS DynamoDB table cleanup attempted"
            echo "  💡 Verify in AWS console that DynamoDB table was deleted"
        else
            echo "  ⏭️  AWS DynamoDB cleanup skipped (--enable-locking not set)"
        fi
        ;;
    azure)
        echo "  ✅ Azure: No additional cleanup needed (built-in locking)"
        ;;
    gcp)
        echo "  ✅ GCP: No additional cleanup needed (built-in consistency)"
        ;;
esac

echo ""
echo "Note: This script only cleans up state locking resources."
echo "Storage buckets/accounts are preserved for potential state recovery."
echo "To fully clean up storage resources, use separate cleanup procedures."
