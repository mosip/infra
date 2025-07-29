# Updated GitHub Actions Workflows for Cloud-Agnostic Terraform

## Overview

The GitHub Actions workflows have been updated to support the new cloud-agnostic Terraform structure with separate `base-infra` and `infra` components, each with isolated state files per cloud provider.

## New Structure

```
terraform/
├── implementations/
│   ├── aws/
│   │   ├── base-infra/         # One-time foundational resources
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── aws.tfvars
│   │   └── infra/             # Application infrastructure (can be recreated)
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       └── aws.tfvars
│   ├── azure/
│   │   ├── base-infra/
│   │   └── infra/
│   └── gcp/
│       ├── base-infra/
│       └── infra/
```

## Updated Workflows

### 1. `terraform.yml` - Infrastructure Creation/Update

**Workflow Inputs:**
- **CLOUD_PROVIDER**: Choose from `aws`, `azure`, `gcp`
- **TERRAFORM_COMPONENT**: Choose between:
  - `base-infra` - One-time foundational setup (VPCs, subnets, etc.)
  - `infra` - Application infrastructure (can be destroyed/recreated)
- **SSH_PRIVATE_KEY**: GitHub secret name containing SSH private key
- **TERRAFORM_APPLY**: Boolean to confirm actual deployment

**State Management:**
- Each combination gets its own state file: `{cloud}-{component}-terraform.tfstate`
- Examples:
  - `aws-base-infra-terraform.tfstate`
  - `aws-infra-terraform.tfstate`
  - `azure-base-infra-terraform.tfstate`

### 2. `terraform-destroy.yml` - Infrastructure Destruction

**Workflow Inputs:**
- **CLOUD_PROVIDER**: Choose from `aws`, `azure`, `gcp`
- **TERRAFORM_COMPONENT**: Choose between:
  - `infra` - Safe to destroy and recreate (default)
  - `base-infra` - ⚠️ **CRITICAL WARNING** - Destroys foundational resources
- **SSH_PRIVATE_KEY**: GitHub secret name containing SSH private key
- **TERRAFORM_DESTROY**: Boolean to confirm actual destruction

## Usage Guide

### Phase 1: Deploy Base Infrastructure (One-time setup)

1. Go to **Actions** → **terraform plan / apply**
2. Set inputs:
   - **CLOUD_PROVIDER**: `aws` (or your preferred cloud)
   - **TERRAFORM_COMPONENT**: `base-infra`
   - **SSH_PRIVATE_KEY**: Your SSH key secret name
   - **TERRAFORM_APPLY**: `false` (for planning) or `true` (for deployment)
3. Click **Run workflow**

This creates foundational resources like VPCs, subnets, security groups, etc.

### Phase 2: Deploy Application Infrastructure (Repeatable)

1. Go to **Actions** → **terraform plan / apply**
2. Set inputs:
   - **CLOUD_PROVIDER**: `aws` (same as base-infra)
   - **TERRAFORM_COMPONENT**: `infra`
   - **SSH_PRIVATE_KEY**: Your SSH key secret name
   - **TERRAFORM_APPLY**: `false` (for planning) or `true` (for deployment)
3. Click **Run workflow**

This creates MOSIP application infrastructure (K8s clusters, NGINX, etc.).

### Phase 3: Destroy Application Infrastructure (When needed)

1. Go to **Actions** → **terraform destroy**
2. Set inputs:
   - **CLOUD_PROVIDER**: `aws`
   - **TERRAFORM_COMPONENT**: `infra` (NOT base-infra unless absolutely necessary)
   - **SSH_PRIVATE_KEY**: Your SSH key secret name
   - **TERRAFORM_DESTROY**: `true` (to confirm destruction)
3. Click **Run workflow**

### Phase 4: Destroy Base Infrastructure (Rarely needed)

⚠️ **WARNING**: This destroys foundational resources and should rarely be done.

1. Go to **Actions** → **terraform destroy**
2. Set inputs:
   - **CLOUD_PROVIDER**: `aws`
   - **TERRAFORM_COMPONENT**: `base-infra`
   - **SSH_PRIVATE_KEY**: Your SSH key secret name
   - **TERRAFORM_DESTROY**: `true` (to confirm destruction)
3. Click **Run workflow**

## State File Management

### Backend Configuration

The workflows automatically configure appropriate backends based on cloud provider:

**AWS (S3 Backend):**
```hcl
terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "aws-infra-terraform.tfstate"  # Changes per component
    region = "us-east-1"
  }
}
```

**Azure (Azure Storage Backend):**
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "terraformstate"
    container_name       = "terraform-state"
    key                  = "azure-infra-terraform.tfstate"
  }
}
```

**GCP (GCS Backend):**
```hcl
terraform {
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "terraform/gcp-infra"
  }
}
```

### Required Secrets

Configure these GitHub secrets in your repository:

**AWS:**
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

**Azure:**
- `AZURE_CLIENT_ID`
- `AZURE_CLIENT_SECRET`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_TENANT_ID`

**GCP:**
- `GOOGLE_CREDENTIALS`

**Common:**
- `[SSH_KEY_NAME]` - Your SSH private key
- `WG_CONFIG` - WireGuard configuration (if used)
- `SLACK_WEBHOOK_URL` - Slack notifications (optional)

## Benefits of New Structure

### ✅ **Isolation**
- Each cloud provider has separate state files
- base-infra and infra are completely isolated
- No risk of accidental cross-cloud or cross-component interference

### ✅ **Flexibility**
- Deploy to multiple clouds simultaneously
- Destroy and recreate application infrastructure without affecting base infrastructure
- Easy to test different configurations

### ✅ **Safety**
- Clear separation between one-time setup (base-infra) and repeatable deployments (infra)
- Explicit warnings for destructive operations
- Dry-run capability with plan-only executions

### ✅ **Scalability**
- Easy to add new cloud providers
- Simple to extend with additional components
- Consistent patterns across all clouds

## Migration from Old Structure

If migrating from the old single-file structure:

1. **Don't run both old and new workflows simultaneously**
2. **Destroy existing infrastructure using old workflow first**
3. **Deploy base-infra using new workflow**
4. **Deploy infra using new workflow**
5. **Remove/disable old workflow files**

## Troubleshooting

### Common Issues:

1. **Missing backend bucket**: Ensure S3/Azure Storage/GCS bucket exists
2. **State file conflicts**: Check that you're not mixing old and new structures
3. **Permission errors**: Verify cloud provider credentials and permissions
4. **Missing tfvars**: Ensure `{cloud}.tfvars` files exist in implementation directories

### Best Practices:

1. **Always plan first**: Run with `TERRAFORM_APPLY: false` to review changes
2. **Use descriptive commit messages**: Workflows automatically commit changes
3. **Monitor state files**: Keep track of which resources are in which state file
4. **backup state files**: Implement state file backups for critical environments
