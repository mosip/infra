# GitHub Actions Scripts Directory

This directory contains **utility scripts** used by GitHub Actions workflows to automate infrastructure deployment tasks. All scripts are designed for modularity, reusability, and maintainability.

## Purpose

These scripts handle complex operations that would otherwise make workflow files cluttered and hard to maintain. Each script has a specific responsibility and can be used independently or called from workflows.

## Current Scripts Overview

| Script | Purpose | Used By | Status |
|--------|---------|---------|---------|
| `configure-backend.sh` | Generate backend.tf files for Terraform | terraform.yml, terraform-destroy.yml | Active |
| `setup-cloud-storage.sh` | Setup remote storage across cloud providers | terraform.yml (remote backend) | Active |
| `encrypt-state.sh` | Encrypt Terraform state files with GPG | terraform.yml, terraform-destroy.yml | Active |
| `decrypt-state.sh` | Decrypt Terraform state files with GPG | terraform.yml, terraform-destroy.yml | Active |
| `setup-gpg.sh` | Configure GPG environment for encryption | terraform.yml, terraform-destroy.yml | Active |
| `cleanup-state-locking.sh` | Clean up DynamoDB state locks | terraform-destroy.yml | Active |
| `rancher-register-cluster.sh` | Register a cluster in Rancher / apply the import on a host | terraform.yml (configure) | Active |
| `rancher-grant-cluster-access.sh` | Grant team access to an imported cluster | terraform.yml (configure) | Active |
| `rancher-fetch-kubeconfig.sh` | Fetch kubeconfig from Rancher | terraform.yml (configure) | Active |
| `wg-env.sh` | WireGuard peer onboarding | wg-onboard.yml | Active |
| `test-state-locking.sh`, `test-cleanup-state-locking.sh` | Tests for the state-locking scripts | Manual testing | Active |

## Core Scripts

### configure-backend.sh

**Purpose**: Generates Terraform backend configuration files based on provider and backend type.

**Usage**:
```bash
./configure-backend.sh --type <local|remote> --provider <aws|azure|gcp> --component <component> [options]
```

**Key Features**:
- Supports local and remote backends
- Cloud-agnostic backend generation
- Custom state file naming for local backends
- Validation and error handling

### encrypt-state.sh / decrypt-state.sh

**Purpose**: GPG encryption and decryption of Terraform state files for secure local storage.

**Usage**:
```bash
# Encrypt state files
./encrypt-state.sh --backend-type local --passphrase <gpg-passphrase>

# Decrypt state files
./decrypt-state.sh --backend-type local --passphrase <gpg-passphrase>
```

**Key Features**:
- AES256 encryption with compression
- Automatic file detection and processing
- Git-safe encrypted storage
- Custom state file naming support

### setup-cloud-storage.sh

**Purpose**: Creates and configures remote storage (S3, Azure Storage, GCS) for Terraform state.

**Usage**:
```bash
./setup-cloud-storage.sh --provider <aws|azure|gcp> --config <config> --branch <branch>
```

**Configuration Formats**:
- **AWS**: `aws:bucket_base:region`
- **Azure**: `azure:resource_group:storage_account:container`
- **GCP**: `gcp:bucket_name:region`

### setup-gpg.sh

**Purpose**: Configures GPG environment for state file encryption in GitHub Actions.

**Usage**:
```bash
./setup-gpg.sh --passphrase <gpg-passphrase>
```

**Key Features**:
- GPG key import and configuration
- Batch mode setup for automation
- Trust database initialization

## Testing and Validation

The `infra checks` workflow (`.github/workflows/infra-checks.yml`) runs
`terraform fmt`/`validate`/`test`, the inventory generator's unit tests and an
Ansible syntax check on every pull request. `test-state-locking.sh` and
`test-cleanup-state-locking.sh` exercise the state-locking scripts manually.

## Utility Scripts

### cleanup-state-locking.sh

**Purpose**: Removes DynamoDB state locks when using remote backends.

**Usage**:
```bash
./cleanup-state-locking.sh --provider <provider> --table-name <dynamodb-table>
```

## Script Integration with Workflows

### Terraform Workflows Integration

**terraform-component.yml (called by terraform.yml and terraform-destroy.yml) uses these scripts**:
1. `setup-gpg.sh` - Configure GPG for state encryption
2. `decrypt-state.sh` - Decrypt existing state files
3. `configure-backend.sh` - Generate backend configuration
4. `setup-cloud-storage.sh` - Create remote storage (if remote backend)
5. `encrypt-state.sh` - Encrypt state files after operations

**On destroy it additionally uses**:
1. `setup-gpg.sh` - Configure GPG for state decryption
2. `decrypt-state.sh` - Decrypt state files for destroy operation
3. `configure-backend.sh` - Generate backend configuration
4. `cleanup-state-locking.sh` - Clean up state locks after destroy

### Script Dependencies

```mermaid
graph TD
 A[Workflow Start] --> B[setup-gpg.sh]
 B --> C{Backend Type?}
 C -->|Local| D[decrypt-state.sh]
 C -->|Remote| E[setup-cloud-storage.sh]
 D --> F[configure-backend.sh]
 E --> F
 F --> G[Terraform Operations]
 G --> H[encrypt-state.sh]
 G --> I[cleanup-state-locking.sh]
 H --> J[Workflow End]
 I --> J
```

## Directory Structure

```
.github/scripts/
├── README.md # This file - scripts documentation
├── configure-backend.sh # Backend configuration generation
├── setup-cloud-storage.sh # Remote storage setup
├── encrypt-state.sh # GPG state encryption
├── decrypt-state.sh # GPG state decryption
├── setup-gpg.sh # GPG environment setup
├── cleanup-state-locking.sh # State lock cleanup
├── rancher-register-cluster.sh # Rancher registration / import
├── rancher-grant-cluster-access.sh # Rancher team access
├── rancher-fetch-kubeconfig.sh # kubeconfig from Rancher
├── wg-env.sh, wg-peer-allocation.tsv # WireGuard onboarding
└── test-state-locking.sh, test-cleanup-state-locking.sh
```

## Usage from Workflows

Scripts are called from GitHub Actions workflows with proper error handling:

```yaml
- name: Setup GPG
 run: |
 chmod +x .github/scripts/setup-gpg.sh
 .github/scripts/setup-gpg.sh --passphrase "${{ secrets.GPG_PASSPHRASE }}"

- name: Decrypt State
 run: |
 chmod +x .github/scripts/decrypt-state.sh
 .github/scripts/decrypt-state.sh --backend-type local --passphrase "${{ secrets.GPG_PASSPHRASE }}"
```

## Script Development Guidelines

1. **Modularity**: Each script handles one specific task
2. **Error Handling**: All scripts use `set -e` and proper error checking
3. **Logging**: Clear, structured logging with script name prefixes
4. **Help Usage**: All scripts include `--help` option with usage information
5. **Validation**: Input validation and sanity checks
6. **Cloud Agnostic**: Support multiple cloud providers where applicable

---

**This directory provides the automation backbone for MOSIP infrastructure deployment workflows with secure, modular, and maintainable scripts.**
