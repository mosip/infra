# Terraform Directory Structure

This document provides a comprehensive overview of the Terraform directory stru├── observ-infra/                        # 🔧 Observation Infrastructure (Rancher UI, Keycloak, Integration)ture for MOSI### 🔧 Observation Infrastructure (`observ-infra/`)

**Purpose**: Observation and integration tools infrastructure.

**Contains**:
- Minimal Kubernetes cluster for observation tools
- Rancher UI for cluster management and monitoring
- Keycloak for identity and access management
- Integration services between Rancher and Keycloak
- Lightweight resource allocation (cost-optimized)

**Usage**: Deploy after base-infra to create observation stack. Can be deployed independently of main infra.ture provisioning.

## Overview

The Terraform configuration is organized in a modular, cloud-agnostic structure that supports multiple cloud providers (AWS, Azure, GCP) with three distinct components:

- **base-infra**: Foundation infrastructure (VPC, networking, jumpserver with WireGuard)
- **infra**: Kubernetes cluster for MOSIP core services and external components
- **observ-infra**: Kubernetes cluster for management tools (Rancher UI, Keycloak, integrations)

## Three-Component Architecture

### 🏗️ base-infra
**Purpose**: Create foundational infrastructure and jumpserver automation
- VPC with public/private subnets
- Security groups and routing tables
- Jumpserver EC2 with automated setup (Docker, Ansible, k8s-infra repo)
- WireGuard VPN running in container for secure access
- DNS records and SSL certificates

### 🎯 infra 
**Purpose**: Kubernetes cluster for MOSIP application deployment
- Kubernetes cluster (EKS/AKS/GKE) with full resources
- Node groups optimized for MOSIP workloads
- Will deploy: MOSIP core services, databases, message queues, external components
- Production-grade instance types (t3a.2xlarge)
- High-availability configuration

### 🔧 observ-infra
**Purpose**: Kubernetes cluster for observation and integration tools
- Separate Kubernetes cluster with minimal resources
- Will deploy: Rancher UI, Keycloak, Rancher-Keycloak integration
- Minimal instance types (t3a.medium) for cost optimization
- Observation tools isolated from main workloads

## Directory Structure

```
terraform/
├── README.md                             # General Terraform documentation
├── CLOUD_AGNOSTIC_README.md             # Cloud-agnostic implementation guide
├── WIREGUARD_AUTOMATION.md              # WireGuard automation documentation
│
├── base-infra/                          # 🏗️  Base Infrastructure (VPC, networking, jumpserver)
│   ├── main.tf                          # Cloud-agnostic main configuration
│   ├── variables.tf                     # Cloud-agnostic variable definitions
│   ├── outputs.tf                       # Base infrastructure outputs
│   │
│   ├── aws/                             # AWS-specific base infrastructure
│   │   ├── main.tf                      # AWS resources (VPC, subnets, jumpserver, etc.)
│   │   ├── variables.tf                 # AWS-specific variables
│   │   ├── outputs.tf                   # AWS-specific outputs
│   │   └── jumpserver-setup.sh.tpl     # 🤖 Automated jumpserver setup script
│   │
│   ├── azure/                           # Azure-specific base infrastructure
│   │   ├── main.tf                      # Azure resources (Resource Group, VNet, etc.)
│   │   ├── variables.tf                 # Azure-specific variables
│   │   └── outputs.tf                   # Azure-specific outputs
│   │
│   └── gcp/                             # GCP-specific base infrastructure
│       ├── main.tf                      # GCP resources (VPC, subnets, etc.)
│       ├── variables.tf                 # GCP-specific variables
│       └── outputs.tf                   # GCP-specific outputs
│
├── infra/                               # 🎯 Main Infrastructure (K8s cluster for MOSIP services)
│   ├── main.tf                          # Cloud-agnostic main configuration
│   ├── variables.tf                     # Cloud-agnostic variable definitions
│   ├── outputs.tf                       # Main infrastructure outputs
│   │
│   ├── aws/                             # AWS-specific main infrastructure
│   │   ├── main.tf                      # K8s cluster for MOSIP core services
│   │   ├── variables.tf                 # AWS-specific variables
│   │   └── outputs.tf                   # AWS-specific outputs
│   │
│   ├── azure/                           # Azure-specific main infrastructure
│   │   ├── main.tf                      # AKS cluster configuration
│   │   ├── variables.tf                 # Azure-specific variables
│   │   └── outputs.tf                   # Azure-specific outputs
│   │
│   └── gcp/                             # GCP-specific main infrastructure
│       ├── main.tf                      # GKE cluster configuration
│       ├── variables.tf                 # GCP-specific variables
│       └── outputs.tf                   # GCP-specific outputs
│
├── observ-infra/                        # 🔧 Management Infrastructure (K8s cluster for Rancher, Keycloak)
│   ├── main.tf                          # Cloud-agnostic main configuration
│   ├── variables.tf                     # Cloud-agnostic variable definitions
│   ├── outputs.tf                       # Management infrastructure outputs
│   │
│   ├── aws/                             # AWS-specific management infrastructure
│   │   ├── main.tf                      # K8s cluster for Rancher UI, Keycloak
│   │   ├── variables.tf                 # AWS-specific variables (minimal resources)
│   │   └── outputs.tf                   # AWS-specific outputs
│   │
│   ├── azure/                           # Azure-specific management infrastructure
│   │   ├── main.tf                      # AKS cluster for management tools
│   │   ├── variables.tf                 # Azure-specific variables
│   │   └── outputs.tf                   # Azure-specific outputs
│   │
│   └── gcp/                             # GCP-specific management infrastructure
│       ├── main.tf                      # GKE cluster for management tools
│       ├── variables.tf                 # GCP-specific variables
│       └── outputs.tf                   # GCP-specific outputs
│   │   └── outputs.tf                   # Azure-specific outputs
│   │
│   └── gcp/                             # GCP-specific main infrastructure
│       ├── main.tf                      # GKE cluster configuration
│       ├── variables.tf                 # GCP-specific variables
│       └── outputs.tf                   # GCP-specific outputs
│
├── observ-infra/                        # � Management Infrastructure (Rancher UI, Keycloak, Integration)
│   ├── main.tf                          # Cloud-agnostic main configuration
│   ├── variables.tf                     # Cloud-agnostic variable definitions
│   ├── outputs.tf                       # Management infrastructure outputs
│   │
│   ├── aws/                             # AWS-specific management infrastructure
│   │   ├── main.tf                      # EKS cluster for Rancher UI, Keycloak
│   │   ├── variables.tf                 # AWS-specific variables
│   │   └── outputs.tf                   # AWS-specific outputs
│   │
│   ├── azure/                           # Azure-specific management infrastructure
│   │   ├── main.tf                      # AKS cluster for Rancher UI, Keycloak
│   │   ├── variables.tf                 # Azure-specific variables
│   │   └── outputs.tf                   # Azure-specific outputs
│   │
│   └── gcp/                             # GCP-specific management infrastructure
│       ├── main.tf                      # GKE cluster for Rancher UI, Keycloak
│       ├── variables.tf                 # GCP-specific variables
│       └── outputs.tf                   # GCP-specific outputs
│
├── implementations/                     # 🌍 Environment-Specific Configurations
│   ├── aws/                             # AWS implementation examples
│   │   ├── base-infra/
│   │   │   ├── main.tf                  # References ../../../base-infra
│   │   │   ├── aws.tfvars              # 📋 AWS environment configuration
│   │   │   ├── terraform.tfvars        # Common Terraform settings
│   │   │   └── outputs.tf              # Implementation-specific outputs
│   │   │
│   │   ├── infra/
│   │   │   ├── main.tf                  # References ../../../infra
│   │   │   ├── aws.tfvars              # 📋 AWS cluster configuration
│   │   │   ├── terraform.tfvars        # Common Terraform settings
│   │   │   └── outputs.tf              # Implementation-specific outputs
│   │   │
│   │   └── observ-infra/
│   │       ├── main.tf                  # References ../../../observ-infra
│   │       ├── aws.tfvars              # 📋 AWS observation configuration
│   │       ├── terraform.tfvars        # Common Terraform settings
│   │       └── outputs.tf              # Implementation-specific outputs
│   │
│   ├── azure/                           # Azure implementation examples
│   │   ├── base-infra/
│   │   │   ├── main.tf
│   │   │   ├── azure.tfvars            # 📋 Azure environment configuration
│   │   │   └── outputs.tf
│   │   │
│   │   ├── infra/
│   │   │   ├── main.tf
│   │   │   ├── azure.tfvars            # 📋 Azure cluster configuration
│   │   │   └── outputs.tf
│   │   │
│   │   └── observ-infra/
│   │       ├── main.tf
│   │       ├── azure.tfvars            # 📋 Azure observation configuration
│   │       └── outputs.tf
│   │
│   └── gcp/                             # GCP implementation examples
│       ├── base-infra/
│       │   ├── main.tf
│       │   ├── gcp.tfvars              # 📋 GCP environment configuration
│       │   └── outputs.tf
│       │
│       ├── infra/
│       │   ├── main.tf
│       │   ├── gcp.tfvars              # 📋 GCP cluster configuration
│       │   └── outputs.tf
│       │
│       └── observ-infra/
│           ├── main.tf
│           ├── gcp.tfvars              # 📋 GCP observation configuration
│           └── outputs.tf
│
└── modules/                             # 🧩 Reusable Terraform Modules
    ├── aws/                             # AWS-specific modules
    │   ├── vpc/                         # VPC module
    │   ├── eks/                         # EKS module
    │   ├── rds/                         # RDS module
    │   └── ...                          # Other AWS modules
    │
    ├── azure/                           # Azure-specific modules
    │   ├── resource-group/              # Resource Group module
    │   ├── aks/                         # AKS module
    │   ├── sql-database/                # SQL Database module
    │   └── ...                          # Other Azure modules
    │
    └── gcp/                             # GCP-specific modules
        ├── vpc/                         # VPC module
        ├── gke/                         # GKE module
        ├── sql/                         # Cloud SQL module
        └── ...                          # Other GCP modules
```

## Key Components

### 🏗️ Base Infrastructure (`base-infra/`)

**Purpose**: Foundation infrastructure including networking, security groups, and jumpserver.

**Contains**:
- VPC/VNet/Network setup
- Subnets (public/private)
- Internet Gateway/NAT Gateway
- Security Groups/NSGs/Firewall Rules
- Jumpserver EC2/VM with automated WireGuard setup
- DNS and routing configuration

**Usage**: Deploy first to establish the basic networking foundation.

### 🎯 Main Infrastructure (`infra/`)

**Purpose**: Kubernetes clusters and associated services.

**Contains**:
- EKS/AKS/GKE cluster configuration
- Node groups/Node pools
- Cluster add-ons (CNI, DNS, etc.)
- IRSA/Managed Identity/Workload Identity
- Storage classes and persistent volumes

**Usage**: Deploy after base-infra to create Kubernetes clusters.

### � Management Infrastructure (`observ-infra/`)

**Purpose**: Management and integration tools infrastructure.

**Contains**:
- Minimal Kubernetes cluster for management tools
- Rancher UI for cluster management and monitoring
- Keycloak for identity and access management
- Integration services between Rancher and Keycloak
- Lightweight resource allocation (cost-optimized)

**Usage**: Deploy after base-infra to create management stack. Can be deployed independently of main infra.

### 🌍 Implementations (`implementations/`)

**Purpose**: Environment-specific configurations and variable files.

**Contains**:
- Environment-specific `.tfvars` files
- Small `main.tf` files that reference the main modules
- Custom outputs for specific environments
- Environment-specific overrides

**Usage**: Copy and customize for your specific deployment needs.

### 🧩 Modules (`modules/`)

**Purpose**: Reusable, composable Terraform modules.

**Contains**:
- Cloud-specific service modules
- Best-practice configurations
- Parameterized resource definitions
- Standard tagging and naming conventions

**Usage**: Referenced by main infrastructure configurations.

## Deployment Workflow

### 1. Base Infrastructure Deployment

```bash
# Navigate to implementation directory
cd terraform/implementations/aws/base-infra/

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -var-file="aws.tfvars"

# Apply base infrastructure
terraform apply -var-file="aws.tfvars"
```

### 2. Main Infrastructure Deployment

```bash
# Navigate to implementation directory
cd terraform/implementations/aws/infra/

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -var-file="aws.tfvars"

# Apply main infrastructure
terraform apply -var-file="aws.tfvars"
```

### 3. Observation Infrastructure Deployment

```bash
# Navigate to implementation directory
cd terraform/implementations/aws/observ-infra/

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -var-file="aws.tfvars"

# Apply observation infrastructure
terraform apply -var-file="aws.tfvars"
```

## File Descriptions

### Configuration Files

| File | Purpose | Content |
|------|---------|---------|
| `main.tf` | Primary Terraform configuration | Resource definitions, module calls |
| `variables.tf` | Variable definitions | Input parameters with types and descriptions |
| `outputs.tf` | Output definitions | Values to expose after deployment |
| `*.tfvars` | Variable values | Environment-specific configuration values |
| `terraform.tf` | Terraform settings | Provider versions, backend configuration |

### Special Files

| File | Purpose | Description |
|------|---------|-------------|
| `jumpserver-setup.sh.tpl` | 🤖 Automation script | User data template for automated jumpserver setup |
| `WIREGUARD_AUTOMATION.md` | 📖 Documentation | WireGuard automation guide |
| `CLOUD_AGNOSTIC_README.md` | 📖 Documentation | Cloud-agnostic implementation guide |

## Customization Guide

### Adding a New Environment

1. **Copy implementation template**:
   ```bash
   cp -r terraform/implementations/aws terraform/implementations/aws-prod
   ```

2. **Update variable files**:
   ```bash
   # Edit environment-specific values
   vim terraform/implementations/aws-prod/base-infra/aws.tfvars
   vim terraform/implementations/aws-prod/infra/aws.tfvars
   ```

3. **Deploy in sequence**:
   ```bash
   # Base infrastructure first
   cd terraform/implementations/aws-prod/base-infra
   terraform apply -var-file="aws.tfvars"
   
   # Main infrastructure second
   cd ../infra
   terraform apply -var-file="aws.tfvars"
   ```

### Adding a New Cloud Provider

1. **Create provider-specific directories**:
   ```bash
   mkdir -p terraform/base-infra/newcloud
   mkdir -p terraform/infra/newcloud
   mkdir -p terraform/implementations/newcloud
   mkdir -p terraform/modules/newcloud
   ```

2. **Implement provider-specific resources**:
   - Add provider configuration
   - Create networking resources
   - Implement compute resources
   - Add provider-specific modules

3. **Update main configurations**:
   - Add provider conditionals in main `main.tf` files
   - Update variable files with provider-specific options
   - Add provider-specific outputs

### Modifying WireGuard Setup

The WireGuard automation can be customized by:

1. **Editing the template**:
   ```bash
   vim terraform/base-infra/aws/jumpserver-setup.sh.tpl
   ```

2. **Updating variables**:
   ```bash
   vim terraform/implementations/aws/base-infra/aws.tfvars
   ```

3. **Adding new features**:
   - Modify the user data script
   - Add new variables for configuration
   - Update outputs for new information

## Best Practices

### File Organization
- Keep cloud-agnostic code in root directories
- Place cloud-specific code in provider subdirectories
- Use descriptive file names and consistent structure
- Maintain separate variable files for different environments

### Variable Management
- Define variables in appropriate scope (cloud-agnostic vs. provider-specific)
- Use descriptive variable names and comprehensive descriptions
- Set appropriate defaults and validation rules
- Document variable dependencies and relationships

### Module Design
- Create reusable modules for common patterns
- Use clear input/output interfaces
- Implement proper error handling and validation
- Follow cloud provider best practices

### State Management
- Use remote state storage (S3, Azure Storage, GCS)
- Implement state locking
- Separate state files by environment
- Regular state file cleanup and maintenance

## Troubleshooting

### Common Issues

1. **Provider Authentication**:
   - Ensure cloud provider credentials are configured
   - Check IAM/RBAC permissions
   - Verify provider version compatibility

2. **State Management**:
   - Check state file permissions
   - Verify backend configuration
   - Handle state locks appropriately

3. **Variable Validation**:
   - Verify all required variables are set
   - Check variable types and formats
   - Validate cross-dependencies

4. **Resource Dependencies**:
   - Ensure proper resource ordering
   - Check explicit dependencies
   - Validate outputs are available

### Debugging Commands

```bash
# Enable detailed logging
export TF_LOG=DEBUG

# Validate configuration
terraform validate

# Check formatting
terraform fmt -check

# Show current state
terraform show

# List resources
terraform state list

# Import existing resources
terraform import <resource_type>.<name> <resource_id>
```

This directory structure provides a scalable, maintainable approach to infrastructure as code while supporting multiple cloud providers and deployment environments.
