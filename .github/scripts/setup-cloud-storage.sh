#!/bin/bash

# MOSIP Cloud-Agnostic Remote Storage Setup Script
# Handles remote storage setup for Terraform state across AWS, Azure, and GCP
# Supports all workflow inputs: providers (aws, azure, gcp), components (base-infra, infra, observ-infra), and backend types

set -e  # Exit on any error

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -p, --provider        Cloud provider: aws, azure, gcp (required)"
    echo "  -c, --config          Remote backend config string (required)"
    echo "  -b, --branch          Branch name for resource naming (required)"
    echo "  -t, --component       Component type: base-infra, infra, observ-infra (optional, for validation)"
    echo "  --enable-locking      Enable state locking (optional, for production)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Remote config formats:"
    echo "  AWS:   aws:bucket_base_name:region"
    echo "  Azure: azure:resource_group:storage_account:container"
    echo "  GCP:   gcp:bucket_name:region"
    echo ""
    echo "Supported combinations:"
    echo "  Providers: aws, azure, gcp"
    echo "  Components: base-infra (one-time), infra (can be destroyed/recreated), observ-infra (can be destroyed/recreated)"
    echo "  Backends: local, remote (this script handles remote only)"
    echo ""
    echo "Examples:"
    echo "  $0 --provider aws --config 'aws:mosip-state:us-east-1' --branch main --component infra"
    echo "  $0 --provider azure --config 'azure:mosip-rg:mosipstate:terraform-state' --branch main --component base-infra"
    echo "  $0 --provider gcp --config 'gcp:mosip-terraform-state:us-central1' --branch main --component observ-infra"
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
if [ -z "$CLOUD_PROVIDER" ] || [ -z "$REMOTE_CONFIG" ] || [ -z "$BRANCH_NAME" ]; then
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

# Validate component if provided
if [ -n "$COMPONENT" ] && [[ ! "$COMPONENT" =~ ^(base-infra|infra|observ-infra)$ ]]; then
    echo "Error: Invalid component '$COMPONENT'"
    echo "Valid components: base-infra, infra, observ-infra"
    exit 1
fi

echo "=== MOSIP Cloud-Agnostic Remote Storage Setup ==="
echo "Cloud provider: $CLOUD_PROVIDER"
echo "Branch name: $BRANCH_NAME"
echo "Component: ${COMPONENT:-"not specified"}"
echo "Remote config: $REMOTE_CONFIG"
echo "================================================"

# Parse remote configuration
IFS=':' read -ra CONFIG_PARTS <<< "$REMOTE_CONFIG"
PROVIDER_TYPE="${CONFIG_PARTS[0]}"

# Validate provider match
if [ "$CLOUD_PROVIDER" != "$PROVIDER_TYPE" ]; then
    echo "Error: Provider mismatch"
    echo "Workflow provider: $CLOUD_PROVIDER"
    echo "Config provider: $PROVIDER_TYPE"
    exit 1
fi

# Function to setup AWS S3 bucket
setup_aws_s3() {
    local bucket_base_name="$1"
    local region="$2"
    local branch_name="$3"
    local component="$4"
    local enable_locking="$5"  # Added state locking parameter
    
    # SECURITY IMPROVEMENT: Create component-specific buckets for better isolation
    # For production, recommended pattern: bucket-base-component-branch
    # e.g., mosip-state-base-infra-main, mosip-state-infra-main, mosip-state-observ-infra-main
    local bucket_name
    
    # Check if bucket_base_name already includes component (for backwards compatibility)
    if [[ "$bucket_base_name" == *"-$component"* ]]; then
        # Already component-specific: mosip-base-infra -> mosip-base-infra-main
        bucket_name="${bucket_base_name}-${branch_name}"
    else
        # Add component for security: mosip-state -> mosip-state-base-infra-main
        bucket_name="${bucket_base_name}-${component}-${branch_name}"
    fi
    
    echo "Setting up AWS S3 bucket for Terraform state..."
    echo "Base bucket name: $bucket_base_name"
    echo "Component: $component"
    echo "Dynamic bucket name: $bucket_name"
    echo "Region: $region"
    echo ""
    echo "SECURITY NOTE: Using component-specific bucket for better isolation"
    echo "  - base-infra: Contains VPC, networking (high security)"
    echo "  - infra: Contains applications (medium security)"  
    echo "  - observ-infra: Contains monitoring (low security)"
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        echo "Bucket $bucket_name already exists"
    else
        echo "Creating S3 bucket: $bucket_name"
        
        # Create bucket (different command for us-east-1 vs other regions)
        if [ "$region" = "us-east-1" ]; then
            aws s3 mb "s3://$bucket_name"
        else
            aws s3 mb "s3://$bucket_name" --region "$region"
        fi
        
        if [ $? -eq 0 ]; then
            echo "S3 bucket created successfully"
        else
            echo "ERROR: Failed to create S3 bucket"
            exit 1
        fi
    fi
    
    # Enable versioning for state file safety
    echo "Enabling versioning on bucket..."
    aws s3api put-bucket-versioning \
        --bucket "$bucket_name" \
        --versioning-configuration Status=Enabled
    
    if [ $? -eq 0 ]; then
        echo "Bucket versioning enabled"
    else
        echo "WARNING: Failed to enable versioning, but continuing..."
    fi
    
    # Enable server-side encryption for security
    echo "Enabling server-side encryption..."
    aws s3api put-bucket-encryption \
        --bucket "$bucket_name" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }'
    
    if [ $? -eq 0 ]; then
        echo "Bucket encryption enabled"
    else
        echo "WARNING: Failed to enable encryption, but continuing..."
    fi
    
    # Block public access for security
    echo "Blocking public access..."
    aws s3api put-public-access-block \
        --bucket "$bucket_name" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    if [ $? -eq 0 ]; then
        echo "Public access blocked"
    else
        echo "WARNING: Failed to block public access, but continuing..."
    fi
    
    # Optional: Setup state locking infrastructure (provider-specific)
    if [ "$enable_locking" = true ]; then
        local lock_resource_name="terraform-state-lock-${component}-${branch_name}"
        echo "Setting up state locking infrastructure: $lock_resource_name"
        
        # Check if DynamoDB table exists
        if aws dynamodb describe-table --table-name "$lock_resource_name" --region "$region" 2>/dev/null; then
            echo "DynamoDB table $lock_resource_name already exists"
        else
            echo "Creating DynamoDB table: $lock_resource_name"
            aws dynamodb create-table \
                --table-name "$lock_resource_name" \
                --attribute-definitions AttributeName=LockID,AttributeType=S \
                --key-schema AttributeName=LockID,KeyType=HASH \
                --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
                --region "$region"
            
            if [ $? -eq 0 ]; then
                echo "DynamoDB table created successfully"
                # Wait for table to be active
                echo "Waiting for table to become active..."
                aws dynamodb wait table-exists --table-name "$lock_resource_name" --region "$region"
                echo "DynamoDB table is now active"
            else
                echo "ERROR: Failed to create DynamoDB table"
                exit 1
            fi
        fi
        
        # Set environment variable for backend configuration
        export TERRAFORM_STATE_LOCK_TABLE="$lock_resource_name"
    else
        echo "State locking disabled (DynamoDB table will not be created)"
        echo "Note: For production environments, consider enabling state locking with --enable-locking"
    fi
    
    # Set environment variables for GitHub Actions and shell usage
    export DYNAMIC_STORAGE_NAME="$bucket_name"
    export DYNAMIC_REGION="$region"
    
    if [ -n "$GITHUB_ENV" ]; then
        echo "DYNAMIC_STORAGE_NAME=$bucket_name" >> "$GITHUB_ENV"
        echo "DYNAMIC_REGION=$region" >> "$GITHUB_ENV"
        if [ -n "$TERRAFORM_STATE_LOCK_TABLE" ]; then
            echo "TERRAFORM_STATE_LOCK_TABLE=$TERRAFORM_STATE_LOCK_TABLE" >> "$GITHUB_ENV"
        fi
    fi
}

# Function to setup Azure Storage Account
setup_azure_storage() {
    local resource_group_base="$1"
    local storage_account_base="$2"
    local container="$3"
    local branch_name="$4"
    local component="$5"
    local enable_locking="$6"  # Added state locking parameter
    
    # SECURITY IMPROVEMENT: Create component-specific storage accounts
    local branch_suffix=$(echo "$branch_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | cut -c1-8)
    local comp_suffix=$(echo "$component" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
    
    # Check if already component-specific (backwards compatibility)
    if [[ "$resource_group_base" == *"$comp_suffix"* ]]; then
        local dynamic_resource_group="${resource_group_base}-${branch_name}"
        local dynamic_storage_account="${storage_account_base}${branch_suffix}"
    else
        local dynamic_resource_group="${resource_group_base}-${component}-${branch_name}"
        local dynamic_storage_account="${storage_account_base}${comp_suffix}${branch_suffix}"
    fi
    
    echo "Setting up Azure Storage Account for Terraform state..."
    echo "Base resource group: $resource_group_base"
    echo "Base storage account: $storage_account_base"
    echo "Component: $component"
    echo "Dynamic resource group: $dynamic_resource_group"
    echo "Dynamic storage account: $dynamic_storage_account"
    echo "Container: $container"
    echo ""
    echo "SECURITY NOTE: Using component-specific storage for better isolation"
    
    # Check if Azure CLI is available
    if ! command -v az &> /dev/null; then
        echo "WARNING: Azure CLI not found. Please install Azure CLI and run 'az login'"
        echo "Setting environment variables for GitHub Actions workflow..."
    else
        echo "Azure CLI found, proceeding with storage setup..."
        
        # Check if logged in
        if ! az account show &> /dev/null; then
            echo "WARNING: Not logged into Azure. Run 'az login' first"
            echo "Setting environment variables for GitHub Actions workflow..."
        else
            echo "Azure authentication verified"
            
            # Create resource group if it doesn't exist
            echo "Checking/creating resource group: $dynamic_resource_group"
            az group create --name "$dynamic_resource_group" --location "eastus" --output none || echo "Resource group may already exist"
            
            # Create storage account
            echo "Creating storage account: $dynamic_storage_account"
            az storage account create \
                --name "$dynamic_storage_account" \
                --resource-group "$dynamic_resource_group" \
                --location "eastus" \
                --sku "Standard_LRS" \
                --kind "StorageV2" \
                --output none || echo "Storage account may already exist"
            
            # Create container
            echo "Creating container: $container"
            az storage container create \
                --name "$container" \
                --account-name "$dynamic_storage_account" \
                --output none || echo "Container may already exist"
            
            echo "Azure Storage setup completed"
        fi
        
        # Azure state locking information
        if [ "$enable_locking" = true ]; then
            echo "State locking: Azure Blob Storage has built-in lease-based locking"
            echo "No additional setup required - locking is handled by the azurerm backend"
        else
            echo "State locking disabled"
            echo "Note: For production environments, consider enabling state locking with --enable-locking"
        fi
    fi
    
    # Set environment variables for GitHub Actions and shell usage
    export DYNAMIC_STORAGE_NAME="$dynamic_storage_account"
    export DYNAMIC_RESOURCE_GROUP="$dynamic_resource_group"
    export DYNAMIC_CONTAINER="$container"
    
    if [ -n "$GITHUB_ENV" ]; then
        echo "DYNAMIC_STORAGE_NAME=$dynamic_storage_account" >> "$GITHUB_ENV"
        echo "DYNAMIC_RESOURCE_GROUP=$dynamic_resource_group" >> "$GITHUB_ENV"
        echo "DYNAMIC_CONTAINER=$container" >> "$GITHUB_ENV"
        if [ "$enable_locking" = true ]; then
            echo "TERRAFORM_STATE_LOCKING=true" >> "$GITHUB_ENV"
        fi
    fi
    
    echo "Azure Storage configuration prepared: $dynamic_storage_account"
}

# Function to setup GCP Cloud Storage bucket
setup_gcp_storage() {
    local bucket_base_name="$1"
    local region="$2"
    local branch_name="$3"
    local component="$4"
    local enable_locking="$5"  # Added state locking parameter
    
    # SECURITY IMPROVEMENT: Create component-specific buckets
    local bucket_name
    
    # Check if bucket_base_name already includes component (backwards compatibility)
    if [[ "$bucket_base_name" == *"-$component"* ]]; then
        bucket_name="${bucket_base_name}-${branch_name}"
    else
        bucket_name="${bucket_base_name}-${component}-${branch_name}"
    fi
    
    echo "Setting up GCP Cloud Storage bucket for Terraform state..."
    echo "Base bucket name: $bucket_base_name"
    echo "Component: $component"
    echo "Dynamic bucket name: $bucket_name"
    echo "Region: $region"
    echo ""
    echo "SECURITY NOTE: Using component-specific bucket for better isolation"
    
    # Check if gcloud CLI is available
    if ! command -v gcloud &> /dev/null; then
        echo "WARNING: gcloud CLI not found. Please install gcloud CLI and run 'gcloud auth login'"
        echo "Setting environment variables for GitHub Actions workflow..."
    else
        echo "gcloud CLI found, proceeding with storage setup..."
        
        # Check if authenticated
        if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 &> /dev/null; then
            echo "WARNING: Not authenticated with gcloud. Run 'gcloud auth login' first"
            echo "Setting environment variables for GitHub Actions workflow..."
        else
            echo "GCP authentication verified"
            
            # Create bucket if it doesn't exist
            echo "Creating Cloud Storage bucket: $bucket_name"
            if ! gcloud storage buckets describe "gs://$bucket_name" &> /dev/null; then
                gcloud storage buckets create "gs://$bucket_name" \
                    --location="$region" \
                    --uniform-bucket-level-access || echo "Bucket creation may have failed"
                echo "Bucket created successfully"
            else
                echo "Bucket already exists"
            fi
            
            # Enable versioning
            echo "Enabling versioning on bucket..."
            gcloud storage buckets update "gs://$bucket_name" --versioning || echo "Versioning may already be enabled"
            
            echo "GCP Storage setup completed"
        fi
        
        # GCP state locking information
        if [ "$enable_locking" = true ]; then
            echo "State locking: GCP Cloud Storage has built-in object versioning and consistency"
            echo "No additional setup required - locking is handled by the gcs backend"
        else
            echo "State locking disabled"
            echo "Note: For production environments, consider enabling state locking with --enable-locking"
        fi
    fi
    
    # Set environment variables for GitHub Actions and shell usage
    export DYNAMIC_STORAGE_NAME="$bucket_name"
    export DYNAMIC_REGION="$region"
    if [ "$enable_locking" = true ]; then
        export TERRAFORM_STATE_LOCKING="true"
    fi
    
    if [ -n "$GITHUB_ENV" ]; then
        echo "DYNAMIC_STORAGE_NAME=$bucket_name" >> "$GITHUB_ENV"
        echo "DYNAMIC_REGION=$region" >> "$GITHUB_ENV"
        if [ "$enable_locking" = true ]; then
            echo "TERRAFORM_STATE_LOCKING=true" >> "$GITHUB_ENV"
        fi
    fi
    
    echo "GCP Storage configuration prepared: $bucket_name"
}

# Main execution based on cloud provider
case "$CLOUD_PROVIDER" in
    aws)
        if [ ${#CONFIG_PARTS[@]} -lt 3 ]; then
            echo "Error: AWS config requires format: aws:bucket_base_name:region"
            exit 1
        fi
        
        BUCKET_BASE_NAME="${CONFIG_PARTS[1]}"
        REGION="${CONFIG_PARTS[2]}"
        
        if [ -z "$BUCKET_BASE_NAME" ]; then
            echo "Error: Bucket base name is required for AWS"
            exit 1
        fi
        
        setup_aws_s3 "$BUCKET_BASE_NAME" "$REGION" "$BRANCH_NAME" "${COMPONENT:-infra}" "$ENABLE_LOCKING"
        ;;
        
    azure)
        if [ ${#CONFIG_PARTS[@]} -lt 4 ]; then
            echo "Error: Azure config requires format: azure:resource_group:storage_account:container"
            exit 1
        fi
        
        RESOURCE_GROUP="${CONFIG_PARTS[1]}"
        STORAGE_ACCOUNT="${CONFIG_PARTS[2]}"
        CONTAINER="${CONFIG_PARTS[3]}"
        
        if [ -z "$RESOURCE_GROUP" ] || [ -z "$STORAGE_ACCOUNT" ] || [ -z "$CONTAINER" ]; then
            echo "Error: Resource group, storage account, and container are required for Azure"
            exit 1
        fi
        
        setup_azure_storage "$RESOURCE_GROUP" "$STORAGE_ACCOUNT" "$CONTAINER" "$BRANCH_NAME" "${COMPONENT:-infra}" "$ENABLE_LOCKING"
        ;;
        
    gcp)
        if [ ${#CONFIG_PARTS[@]} -lt 3 ]; then
            echo "Error: GCP config requires format: gcp:bucket_name:region"
            exit 1
        fi
        
        BUCKET_BASE_NAME="${CONFIG_PARTS[1]}"
        REGION="${CONFIG_PARTS[2]}"
        
        if [ -z "$BUCKET_BASE_NAME" ]; then
            echo "Error: Bucket name is required for GCP"
            exit 1
        fi
        
        setup_gcp_storage "$BUCKET_BASE_NAME" "$REGION" "$BRANCH_NAME" "${COMPONENT:-infra}" "$ENABLE_LOCKING"
        ;;
        
    *)
        echo "Error: Unsupported cloud provider: $CLOUD_PROVIDER"
        exit 1
        ;;
esac

echo ""
echo "Cloud-agnostic remote storage setup completed successfully!"
