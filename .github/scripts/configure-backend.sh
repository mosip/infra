#!/bin/bash

# MOSIP Terraform Backend Configuration Script
# This script generates appropriate backend.tf files based on provider and configuration
# Supports all workflow inputs: providers (aws, azure, gcp), components (base-infra, infra, observ-infra), and backend types (local, remote)

set -e  # Exit on any error

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -t, --type            Backend type: local or remote (required)"
    echo "  -p, --provider        Cloud provider: aws, azure, gcp (required)"
    echo "  -c, --component       Component: base-infra, infra, observ-infra (required)"
    echo "  -b, --branch          Branch name for state key (required for remote)"
    echo "  -r, --remote-config   Remote backend config string (required for remote)"
    echo "  --enable-locking      Enable state locking (optional, for production)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Supported combinations:"
    echo "  Providers: aws, azure, gcp"
    echo "  Components: base-infra (one-time), infra (can be destroyed/recreated), observ-infra (can be destroyed/recreated)"
    echo "  Backends: local, remote"
    echo ""
    echo "Remote config formats:"
    echo "  AWS:   aws:bucket_name:region"
    echo "  Azure: azure:rg_name:storage_account:container"
    echo "  GCP:   gcp:bucket_name"
    echo ""
    echo "Examples:"
    echo "  Local backend:"
    echo "    $0 --type local --provider aws --component infra"
    echo ""
    echo "  Remote backends:"
    echo "    $0 --type remote --provider aws --component infra --branch main --remote-config 'aws:mybucket:us-east-1'"
    echo "    $0 --type remote --provider azure --component base-infra --branch main --remote-config 'azure:myRG:mystorageacct:terraform-state'"
    echo "    $0 --type remote --provider gcp --component observ-infra --branch main --remote-config 'gcp:mybucket'"
}

# Default values
BACKEND_TYPE=""
CLOUD_PROVIDER=""
COMPONENT=""
BRANCH_NAME=""
REMOTE_CONFIG=""
ENABLE_LOCKING=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--type)
            BACKEND_TYPE="$2"
            shift 2
            ;;
        -p|--provider)
            CLOUD_PROVIDER="$2"
            shift 2
            ;;
        -c|--component)
            COMPONENT="$2"
            shift 2
            ;;
        -b|--branch)
            BRANCH_NAME="$2"
            shift 2
            ;;
        -r|--remote-config)
            REMOTE_CONFIG="$2"
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
if [ -z "$BACKEND_TYPE" ] || [ -z "$CLOUD_PROVIDER" ] || [ -z "$COMPONENT" ]; then
    echo "Error: Missing required parameters"
    usage
    exit 1
fi

# Validate cloud provider
if [[ ! "$CLOUD_PROVIDER" =~ ^(aws|azure|gcp)$ ]]; then
    echo "Error: Invalid cloud provider '$CLOUD_PROVIDER'"
    echo "Valid providers: aws, azure, gcp"
    exit 1
fi

# Validate component
if [[ ! "$COMPONENT" =~ ^(base-infra|infra|observ-infra)$ ]]; then
    echo "Error: Invalid component '$COMPONENT'"
    echo "Valid components: base-infra, infra, observ-infra"
    exit 1
fi

# Validate backend type
if [[ ! "$BACKEND_TYPE" =~ ^(local|remote)$ ]]; then
    echo "Error: Invalid backend type '$BACKEND_TYPE'"
    echo "Valid types: local, remote"
    exit 1
fi

if [ "$BACKEND_TYPE" = "remote" ] && [ -z "$REMOTE_CONFIG" ]; then
    echo "Error: Remote config is required for remote backend type"
    usage
    exit 1
fi

if [ "$BACKEND_TYPE" = "remote" ] && [ -z "$BRANCH_NAME" ]; then
    echo "Error: Branch name is required for remote backend type"
    usage
    exit 1
fi

echo "=== MOSIP Terraform Backend Configuration ==="
echo "Backend type: $BACKEND_TYPE"
echo "Cloud provider: $CLOUD_PROVIDER"
echo "Component: $COMPONENT"
echo "Branch: $BRANCH_NAME"
echo "============================================="

# Function to create local backend configuration
create_local_backend() {
    local provider="$1"
    local component="$2"
    local branch="$3"
    
    # Include branch name for consistency and to avoid conflicts
    # Use 'local' as default branch name if not provided
    local branch_suffix="${branch:-local}"
    local state_file="${provider}-${component}-${branch_suffix}-terraform.tfstate"
    
    echo "Configuring local backend..."
    echo "State file will be: $state_file"
    
    cat > backend.tf << EOF
terraform {
  backend "local" {
    path = "$state_file"
  }
}
EOF
    
    echo "Local backend configuration created"
}

# Function to create AWS S3 backend configuration
create_aws_backend() {
    local component="$1"
    local branch="$2"
    local bucket_base_name="$3"
    local region="$4"
    
    # Construct dynamic bucket name using same logic as setup-cloud-storage.sh
    local bucket_name
    if [[ "$bucket_base_name" == *"-$component"* ]]; then
        # Already component-specific: mosip-base-infra -> mosip-base-infra-main
        bucket_name="${bucket_base_name}-${branch}"
    else
        # Add component for security: mosip-terraform-state -> mosip-terraform-state-observ-infra-main
        bucket_name="${bucket_base_name}-${component}-${branch}"
    fi
    
    # Use environment variables if available (from S3 setup script) - this overrides the calculated name
    if [ -n "$DYNAMIC_STORAGE_NAME" ]; then
        echo "Using dynamic storage name from environment: $DYNAMIC_STORAGE_NAME"
        bucket_name="$DYNAMIC_STORAGE_NAME"
    fi
    if [ -n "$DYNAMIC_REGION" ]; then
        echo "Using dynamic region from environment: $DYNAMIC_REGION"
        region="$DYNAMIC_REGION"
    fi
    
    local state_key="${CLOUD_PROVIDER}-${component}-${branch}-terraform.tfstate"
    
    echo "Configuring AWS S3 backend..."
    echo "Base bucket name: $bucket_base_name"
    echo "Component: $component"
    echo "Branch: $branch"
    echo "Final bucket name: $bucket_name"
    echo "Region: $region"
    echo "State Key: $state_key"
    
    # Create backend configuration with optional state locking
    if [ "$ENABLE_LOCKING" = true ] && [ -n "$TERRAFORM_STATE_LOCK_TABLE" ]; then
        echo "State Locking Resource: $TERRAFORM_STATE_LOCK_TABLE"
        echo "State locking: ENABLED"
        
        cat > backend.tf << EOF
terraform {
  backend "s3" {
    bucket         = "$bucket_name"
    key            = "$state_key"
    region         = "$region"
    dynamodb_table = "$TERRAFORM_STATE_LOCK_TABLE"
    encrypt        = true
  }
}
EOF
    else
        echo "State locking: DISABLED"
        echo "Note: For production environments, consider enabling state locking"
        
        cat > backend.tf << EOF
terraform {
  backend "s3" {
    bucket = "$bucket_name"
    key    = "$state_key"
    region = "$region"
  }
}
EOF
    fi
    
    echo "AWS S3 backend configuration created"
}

# Function to create Azure backend configuration
create_azure_backend() {
    local component="$1"
    local branch="$2"
    local resource_group="$3"
    local storage_account="$4"
    local container="$5"
    
    # Use environment variables if available (from storage setup script)
    if [ -n "$DYNAMIC_RESOURCE_GROUP" ]; then
        echo "Using dynamic resource group from environment: $DYNAMIC_RESOURCE_GROUP"
        resource_group="$DYNAMIC_RESOURCE_GROUP"
    fi
    if [ -n "$DYNAMIC_STORAGE_NAME" ]; then
        echo "Using dynamic storage account from environment: $DYNAMIC_STORAGE_NAME"
        storage_account="$DYNAMIC_STORAGE_NAME"
    fi
    if [ -n "$DYNAMIC_CONTAINER" ]; then
        echo "Using dynamic container from environment: $DYNAMIC_CONTAINER"
        container="$DYNAMIC_CONTAINER"
    fi
    
    # Include branch name in state key to avoid conflicts
    local state_key="${CLOUD_PROVIDER}-${component}-${branch}-terraform.tfstate"
    
    echo "Configuring Azure Storage backend..."
    echo "Resource Group: $resource_group"
    echo "Storage Account: $storage_account"  
    echo "Container: $container"
    echo "State Key: $state_key"
    
    # Azure Storage has built-in lease-based locking
    if [ "$ENABLE_LOCKING" = true ]; then
        echo "State locking: ENABLED (Azure Blob Storage lease-based locking)"
    else
        echo "State locking: DISABLED"
        echo "Note: For production environments, consider enabling state locking"
    fi

    cat > backend.tf << EOF
terraform {
  backend "azurerm" {
    resource_group_name  = "$resource_group"
    storage_account_name = "$storage_account"
    container_name       = "$container"
    key                  = "$state_key"
  }
}
EOF
    
    echo "Azure Storage backend configuration created"
}

# Function to create GCP backend configuration
create_gcp_backend() {
    local component="$1"
    local branch="$2"
    local bucket_name="$3"
    
    # Use environment variables if available (from storage setup script)
    if [ -n "$DYNAMIC_STORAGE_NAME" ]; then
        echo "Using dynamic bucket name from environment: $DYNAMIC_STORAGE_NAME"
        bucket_name="$DYNAMIC_STORAGE_NAME"
    fi
    
    # Include branch name in prefix to avoid conflicts
    local state_prefix="terraform/${CLOUD_PROVIDER}-${component}-${branch}"
    
    echo "Configuring GCS backend..."
    echo "Bucket: $bucket_name"
    echo "State Prefix: $state_prefix"
    
    # GCP Cloud Storage has built-in consistency and versioning
    if [ "$ENABLE_LOCKING" = true ]; then
        echo "State locking: ENABLED (GCS built-in consistency and versioning)"
    else
        echo "State locking: DISABLED"
        echo "Note: For production environments, consider enabling state locking"
    fi

    cat > backend.tf << EOF
terraform {
  backend "gcs" {
    bucket = "$bucket_name"
    prefix = "$state_prefix"
  }
}
EOF
    
    echo "GCS backend configuration created"
}

# Main execution
main() {
    if [ "$BACKEND_TYPE" = "local" ]; then
        create_local_backend "$CLOUD_PROVIDER" "$COMPONENT" "$BRANCH_NAME"
        
    elif [ "$BACKEND_TYPE" = "remote" ]; then
        # Parse remote configuration
        IFS=':' read -ra CONFIG_PARTS <<< "$REMOTE_CONFIG"
        PROVIDER_TYPE="${CONFIG_PARTS[0]}"
        
        # Validate provider match
        if [ "$CLOUD_PROVIDER" != "$PROVIDER_TYPE" ]; then
            echo "Error: Backend configuration mismatch"
            echo "Cloud provider: $CLOUD_PROVIDER"
            echo "Backend config provider: $PROVIDER_TYPE"
            echo "They must match!"
            exit 1
        fi
        
        case "$PROVIDER_TYPE" in
            aws)
                BUCKET_NAME="${CONFIG_PARTS[1]}"
                REGION="${CONFIG_PARTS[2]:-us-east-1}"
                
                if [ -z "$BUCKET_NAME" ]; then
                    echo "Error: Bucket name is required for AWS S3 backend"
                    exit 1
                fi
                
                create_aws_backend "$COMPONENT" "$BRANCH_NAME" "$BUCKET_NAME" "$REGION"
                ;;
            azure)
                RESOURCE_GROUP="${CONFIG_PARTS[1]}"
                STORAGE_ACCOUNT="${CONFIG_PARTS[2]}"
                CONTAINER="${CONFIG_PARTS[3]:-terraform-state}"
                
                if [ -z "$RESOURCE_GROUP" ] || [ -z "$STORAGE_ACCOUNT" ]; then
                    echo "Error: Resource Group and Storage Account are required for Azure backend"
                    exit 1
                fi
                
                create_azure_backend "$COMPONENT" "$BRANCH_NAME" "$RESOURCE_GROUP" "$STORAGE_ACCOUNT" "$CONTAINER"
                ;;
            gcp)
                BUCKET_NAME="${CONFIG_PARTS[1]}"
                
                if [ -z "$BUCKET_NAME" ]; then
                    echo "Error: Bucket name is required for GCS backend"
                    exit 1
                fi
                
                create_gcp_backend "$COMPONENT" "$BRANCH_NAME" "$BUCKET_NAME"
                ;;
            *)
                echo "Error: Unsupported provider type: $PROVIDER_TYPE"
                exit 1
                ;;
        esac
    else
        echo "Error: Invalid backend type: $BACKEND_TYPE"
        echo "Valid types: local, remote"
        exit 1
    fi
    
    echo ""
    echo "=== Generated Backend Configuration ==="
    cat backend.tf
    echo "======================================="
    echo ""
    echo "Backend configuration completed successfully"
}

# Execute main function
main
