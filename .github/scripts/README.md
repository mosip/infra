# GitHub Actions Scripts

This directory contains helper scripts used by GitHub Actions workflows to keep the workflow files clean and maintainable following the KISS (Keep It Simple, Stupid) principle. All scripts support the complete range of workflow inputs for cloud-agnostic MOSIP infrastructure deployment.

## Supported Workflow Inputs

All scripts support these workflow input combinations:

- **Providers**: `aws`, `azure`, `gcp`
- **Components**: `base-infra` (one-time), `infra` (can be destroyed/recreated), `observ-infra` (can be destroyed/recreated)
- **Backend Types**: `local`, `remote`

## Scripts Overview

| Script | Purpose | Cloud Support | Component Support |
|--------|---------|---------------|-------------------|
| `setup-cloud-storage.sh` | Sets up remote storage for Terraform state | AWS, Azure, GCP | All components |
| `configure-backend.sh` | Generates backend.tf files | AWS, Azure, GCP | All components |
| `setup-s3-backend.sh` | AWS-specific S3 setup (legacy) | AWS only | All components |
| `test-infrastructure.sh` | Tests all scripts and combinations | All providers | All components |

## Scripts

### setup-cloud-storage.sh

**Purpose**: Cloud-agnostic remote storage setup for Terraform state across AWS, Azure, and GCP.

**Usage**:
```bash
./setup-cloud-storage.sh --provider <provider> --config <config> --branch <branch> [--component <component>]
```

**Parameters**:
- `--provider` (required): Cloud provider (`aws`, `azure`, `gcp`)
- `--config` (required): Remote backend config string
- `--branch` (required): Branch name for resource naming
- `--component` (optional): Component type for validation (`base-infra`, `infra`, `observ-infra`)
- `--help`: Show help message

**Configuration Formats**:
- **AWS**: `aws:bucket_base_name:region`
- **Azure**: `azure:resource_group:storage_account:container`
- **GCP**: `gcp:bucket_name:region`

**Features**:
- Creates cloud storage with branch-specific naming
- Configures security settings (encryption, versioning, access controls)
- Sets environment variables for workflows
- Validates CLI authentication
- Handles existing resources gracefully

**Examples**:
```bash
# AWS S3 setup
./setup-cloud-storage.sh \
  --provider aws \
  --config "aws:mosip-state:us-east-1" \
  --branch main \
  --component infra

# Azure Storage setup
./setup-cloud-storage.sh \
  --provider azure \
  --config "azure:mosip-rg:mosipstate:terraform-state" \
  --branch main \
  --component base-infra

# GCP Cloud Storage setup
./setup-cloud-storage.sh \
  --provider gcp \
  --config "gcp:mosip-terraform-state:us-central1" \
  --branch main \
  --component observ-infra
```

### configure-backend.sh

**Purpose**: Generates appropriate `backend.tf` files based on provider and configuration for all supported combinations.

**Usage**:
```bash
./configure-backend.sh --type <type> --provider <provider> --component <component> [options]
```

**Parameters**:
- `--type` (required): Backend type (`local`, `remote`)
- `--provider` (required): Cloud provider (`aws`, `azure`, `gcp`)
- `--component` (required): Component (`base-infra`, `infra`, `observ-infra`)
- `--branch` (required for remote): Branch name for state key
- `--remote-config` (required for remote): Remote backend configuration string
- `--help`: Show help message

**Remote Configuration Formats**:
- **AWS**: `aws:bucket_name:region`
- **Azure**: `azure:rg_name:storage_account:container`
- **GCP**: `gcp:bucket_name`

**Examples**:

Local backend (all providers/components):
```bash
./configure-backend.sh --type local --provider aws --component infra
./configure-backend.sh --type local --provider azure --component base-infra
./configure-backend.sh --type local --provider gcp --component observ-infra
```

Remote backends (all providers/components):
```bash
# AWS S3 backend
./configure-backend.sh \
  --type remote \
  --provider aws \
  --component infra \
  --branch main \
  --remote-config "aws:mybucket:us-east-1"

# Azure Storage backend  
./configure-backend.sh \
  --type remote \
  --provider azure \
  --component base-infra \
  --branch main \
  --remote-config "azure:myRG:mystorageacct:terraform-state"

# GCP Cloud Storage backend
./configure-backend.sh \
  --type remote \
  --provider gcp \
  --component observ-infra \
  --branch main \
  --remote-config "gcp:mybucket"
```

### setup-s3-backend.sh

**Purpose**: AWS-specific S3 bucket creation and configuration for Terraform remote state storage (legacy script, use `setup-cloud-storage.sh` for new workflows).

**Usage**:
```bash
./setup-s3-backend.sh --bucket-base <name> --region <region> --branch <branch>
```

**Parameters**:
- `--bucket-base` (required): Base name for S3 bucket
- `--region` (optional): AWS region (default: us-east-1) 
- `--branch` (required): Branch name for bucket suffix
- `--help`: Show help message

**Features**:
- Creates S3 bucket with branch-specific naming (`bucket-base-branch`)
- Enables versioning for state file safety
- Configures server-side encryption (AES256)
- Blocks public access for security
- Sets environment variables for GitHub Actions

**Example**:
```bash
./setup-s3-backend.sh \
  --bucket-base mosip-terraform-state \
  --region us-east-1 \
  --branch main
```

### test-infrastructure.sh

**Purpose**: Comprehensive testing script that validates all scripts and workflow input combinations.

**Usage**:
```bash
./test-infrastructure.sh [--test-type <type>] [--provider <provider>] [--component <component>]
```

**Parameters**:
- `--test-type` (optional): Type of test (`scripts`, `paths`, `all`) - default: `all`
- `--provider` (optional): Cloud provider for specific tests - default: `aws`
- `--component` (optional): Component for specific tests - default: `infra`
- `--help`: Show help message

**Test Types**:
- `scripts`: Test script functionality locally
- `paths`: Test script paths from workflow directories
- `all`: Run both script and path tests plus workflow simulation

**Examples**:
```bash
# Run all tests (recommended)
./test-infrastructure.sh

# Test specific components
./test-infrastructure.sh --test-type scripts
./test-infrastructure.sh --test-type paths

# Test specific provider/component
./test-infrastructure.sh --provider azure --component base-infra
```

**What it tests**:
- All provider/component/backend combinations
- Script functionality and error handling
- Path resolution from workflow directories
- Backend configuration validation
- Workflow simulation for real-world scenarios

## Benefits

### KISS Principle Implementation
- **Separation of Concerns**: Each script handles one specific responsibility
- **Cloud Agnostic**: All major cloud providers supported with consistent interfaces
- **Component Agnostic**: All infrastructure components supported
- **Reusability**: Scripts can be used independently or in other workflows
- **Maintainability**: Complex logic is isolated and easily testable
- **Readability**: Workflow files remain clean and easy to understand

### Comprehensive Support
- **All Cloud Providers**: AWS, Azure, GCP with provider-specific optimizations
- **All Components**: base-infra, infra, observ-infra with appropriate configurations
- **All Backend Types**: local and remote with automatic switching
- **Branch Safety**: Branch-specific naming prevents conflicts
- **Environment Safety**: Separate configurations for different environments

## Summary

This scripts directory provides a comprehensive, cloud-agnostic, and maintainable solution for MOSIP Terraform infrastructure deployment that supports:

- **3 Cloud Providers**: AWS, Azure, GCP
- **3 Components**: base-infra, infra, observ-infra  
- **2 Backend Types**: local, remote
- **18 Total Combinations**: All validated and tested
- **KISS Principle**: Clean, simple, maintainable code
- **Comprehensive Testing**: Automated validation of all scenarios
- **Production Ready**: Security hardened and error resistant

## Scripts

### setup-s3-backend.sh

**Purpose**: Handles S3 bucket creation and configuration for Terraform remote state storage.

**Usage**:
```bash
./setup-s3-backend.sh --bucket-base <name> --region <region> --branch <branch>
```

**Parameters**:
- `--bucket-base` (required): Base name for S3 bucket
- `--region` (optional): AWS region (default: us-east-1) 
- `--branch` (required): Branch name for bucket suffix
- `--help`: Show help message

**Features**:
- Creates S3 bucket with branch-specific naming (`bucket-base-branch`)
- Enables versioning for state file safety
- Configures server-side encryption (AES256)
- Blocks public access for security
- Sets environment variables for GitHub Actions

**Example**:
```bash
./setup-s3-backend.sh \
  --bucket-base mosip-terraform-state \
  --region us-east-1 \
  --branch main
```

### configure-backend.sh

**Purpose**: Generates appropriate `backend.tf` files based on provider and configuration.

**Usage**:
```bash
./configure-backend.sh --type <type> --provider <provider> --component <component> [options]
```

**Parameters**:
- `--type` (required): Backend type - `local` or `remote`
- `--provider` (required): Cloud provider - `aws`, `azure`, or `gcp`
- `--component` (required): Component - `base-infra`, `infra`, or `observ-infra`
- `--branch` (required for remote): Branch name for state key
- `--remote-config` (required for remote): Remote backend configuration string
- `--help`: Show help message

**Remote Configuration Formats**:
- **AWS**: `aws:bucket_name:region`
- **Azure**: `azure:rg_name:storage_account:container`
- **GCP**: `gcp:bucket_name`

**Examples**:

Local backend:
```bash
./configure-backend.sh \
  --type local \
  --provider aws \
  --component infra
```

Remote AWS S3 backend:
```bash
./configure-backend.sh \
  --type remote \
  --provider aws \
  --component infra \
  --branch main \
  --remote-config "aws:mybucket:us-east-1"
```

Remote Azure backend:
```bash
./configure-backend.sh \
  --type remote \
  --provider azure \
  --component infra \
  --branch main \
  --remote-config "azure:myresourcegroup:mystorageaccount:terraform-state"
```

## Benefits

### KISS Principle Implementation
- **Separation of Concerns**: Each script handles one specific responsibility
- **Reusability**: Scripts can be used independently or in other workflows
- **Maintainability**: Complex logic is isolated and easily testable
- **Readability**: Workflow files remain clean and easy to understand

### Error Handling
- Scripts include comprehensive error checking
- Clear error messages with usage instructions
- Graceful handling of optional operations (e.g., S3 bucket configuration)

### Security Features
- S3 bucket security hardening (encryption, versioning, public access blocking)
- Validation of configuration parameters
- Safe defaults for missing optional parameters

## Integration with Workflows

These scripts are designed to be called from GitHub Actions workflows:

```yaml
- name: Setup S3 Backend
  run: |
    .github/scripts/setup-s3-backend.sh \
      --bucket-base "$BUCKET_BASE_NAME" \
      --region "$REGION" \
      --branch "${{ github.ref_name }}"

- name: Configure Backend
  run: |
    .github/scripts/configure-backend.sh \
      --type "${{ inputs.BACKEND_TYPE }}" \
      --provider "${{ inputs.CLOUD_PROVIDER }}" \
      --component "${{ inputs.TERRAFORM_COMPONENT }}" \
      --branch "${{ github.ref_name }}" \
      --remote-config "${{ inputs.REMOTE_BACKEND_CONFIG }}"
```

## Testing

### Comprehensive Testing Script

Use the included test script to verify all components work correctly:

```bash
# Run all tests (recommended)
.github/scripts/test-infrastructure.sh

# Test specific components
.github/scripts/test-infrastructure.sh --test-type scripts    # Test script functionality
.github/scripts/test-infrastructure.sh --test-type paths     # Test workflow paths
.github/scripts/test-infrastructure.sh --test-type all       # Run all tests

# Test specific provider/component
.github/scripts/test-infrastructure.sh --provider aws --component infra
```

### Manual Testing

Test individual scripts locally:

### Manual Testing

Test individual scripts locally:

```bash
# Test S3 setup (requires AWS credentials)
export AWS_PROFILE=your-profile
.github/scripts/setup-s3-backend.sh --bucket-base test-bucket --region us-east-1 --branch test

# Test backend configuration  
.github/scripts/configure-backend.sh --type local --provider aws --component infra
```

### Path Verification

The scripts use the correct relative paths from workflow directories:
- **From terraform implementations**: `../../../../.github/scripts/script-name.sh`
- **Working directory**: `terraform/implementations/{provider}/{component}`
- **Script location**: `.github/scripts/script-name.sh`

## Development

### Adding New Scripts

When adding new scripts:
1. Follow the same parameter parsing pattern
2. Include comprehensive help/usage functions
3. Add error handling with meaningful messages
4. Make scripts executable: `chmod +x script-name.sh`
5. Update this README with documentation
