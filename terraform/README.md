# MOSIP Terraform Infrastructure

<div align="center">

![MOSIP Infrastructure](../docs/_images/mosip-cloud-agnostic-banner.png)

*Terraform-based Infrastructure as Code for MOSIP Platform*

</div>

This directory contains **Terraform code** for deploying MOSIP (Modular Open Source Identity Platform) infrastructure. **Complete implementation is available for AWS**, while **Azure and GCP have placeholder structures** available for community contributions. The architecture separates infrastructure into three distinct components for clear isolation and management.

## Architecture Overview

**For detailed architecture diagrams and deployment flows, see: [ARCHITECTURE_DIAGRAMS.md](../docs/_images/ARCHITECTURE_DIAGRAMS.md)**

### Three-Component Architecture

<div align="center">

![MOSIP Three-Component Architecture](../docs/_images/mosip-rke2-architecture.svg)

*Cloud-Agnostic RKE2 Infrastructure Deployment Model*

</div>

The MOSIP infrastructure follows a clean three-component architecture with isolated state management using **local backend with GPG encryption**:

```mermaid
graph TB
 subgraph "GitHub Actions Orchestration"
 GHA[GitHub Actions<br/>Central Deployment Control]
 end
 
 subgraph "Multi-Cloud Infrastructure"
 subgraph "AWS Cloud"
 AWS_BASE[base-infra<br/>VPC + WireGuard]
 AWS_OBS[observ-infra<br/>Rancher + Keycloak]
 AWS_INFRA[infra<br/>MOSIP K8s Cluster]
 AWS_STATE[(AWS S3<br/>State Files)]
 end
 
 subgraph "Azure Cloud"
 AZ_BASE[base-infra<br/>VNet + WireGuard]
 AZ_OBS[observ-infra<br/>Rancher + Keycloak]
 AZ_INFRA[infra<br/>MOSIP RKE2 Cluster]
 AZ_STATE[(Azure Storage<br/>State Files)]
 end
 
 subgraph "GCP Cloud"
 GCP_BASE[base-infra<br/>VPC + WireGuard]
 GCP_OBS[observ-infra<br/>Rancher + Keycloak]
 GCP_INFRA[infra<br/>MOSIP RKE2 Cluster]
 GCP_STATE[(GCS<br/>State Files)]
 end
 end
 
 GHA --> AWS_BASE
 GHA --> AZ_BASE
 GHA --> GCP_BASE
 
 AWS_BASE --> AWS_OBS
 AWS_BASE --> AWS_INFRA
 AWS_OBS -.->|Import| AWS_INFRA
 AWS_BASE -.-> AWS_STATE
 AWS_OBS -.-> AWS_STATE
 AWS_INFRA -.-> AWS_STATE
 
 AZ_BASE --> AZ_OBS
 AZ_BASE --> AZ_INFRA
 AZ_OBS -.->|Import| AZ_INFRA
 AZ_BASE -.-> AZ_STATE
 AZ_OBS -.-> AZ_STATE
 AZ_INFRA -.-> AZ_STATE
 
 GCP_BASE --> GCP_OBS
 GCP_BASE --> GCP_INFRA
 GCP_OBS -.->|Import| GCP_INFRA
 GCP_BASE -.-> GCP_STATE
 GCP_OBS -.-> GCP_STATE
 GCP_INFRA -.-> GCP_STATE
 
 style GHA fill:#2196F3,stroke:#1976D2,stroke-width:2px,color:#fff
 style AWS_BASE fill:#e1f5fe,stroke:#01579b,stroke-width:2px,color:#000000
 style AWS_OBS fill:#fff3e0,stroke:#f57c00,stroke-width:2px,color:#000000
 style AWS_INFRA fill:#f3e5f5,stroke:#4a148c,stroke-width:2px,color:#000000
 style AZ_BASE fill:#e1f5fe,stroke:#01579b,stroke-width:2px,color:#000000
 style AZ_OBS fill:#fff3e0,stroke:#f57c00,stroke-width:2px,color:#000000
 style AZ_INFRA fill:#f3e5f5,stroke:#4a148c,stroke-width:2px,color:#000000
 style GCP_BASE fill:#e1f5fe,stroke:#01579b,stroke-width:2px,color:#000000
 style GCP_OBS fill:#fff3e0,stroke:#f57c00,stroke-width:2px,color:#000000
 style GCP_INFRA fill:#f3e5f5,stroke:#4a148c,stroke-width:2px,color:#000000
```

**Component Relationships:**

- **base-infra**: Foundation layer (VPC, WireGuard jumpserver)
- **observ-infra**: Management layer (Rancher, Keycloak) - *Optional*
- **infra**: Application layer (MOSIP Kubernetes deployment + PostgreSQL setup)

### Terraform Directory Structure

```mermaid
graph TD
 A["terraform/"] --> B["base-infra/"]
 A --> C["infra/"]
 A --> D["observ-infra/"]
 A --> E["modules/"]
 A --> F["implementations/"]
 
 E --> E1["aws/"]
 E --> E2["azure/"]
 E --> E3["gcp/"]
 
 E1 --> E1A["aws-resource-creation/"]
 E1 --> E1B["nginx-setup/"]
 E1 --> E1C["rke2-cluster/"]
 E1 --> E1D["nfs-setup/"]
 E1 --> E1E["postgresql-setup/"]
 E1 --> E1F["rancher-keycloak-setup/"]
 
 F --> F1["aws/"]
 F --> F2["azure/"]
 F --> F3["gcp/"]
 
 F1 --> F1A["base-infra/"]
 F1 --> F1B["infra/"]
 F1 --> F1C["observ-infra/"]
 
 classDef root fill:#2196F3,stroke:#1976D2,stroke-width:2px,color:#fff
 classDef component fill:#e1f5fe,stroke:#01579b,stroke-width:2px,color:#000000
 classDef modules fill:#e8f5e8,stroke:#1b5e20,stroke-width:2px,color:#000000
 classDef impl fill:#fce4ec,stroke:#880e4f,stroke-width:2px,color:#000000
 
 class A root
 class B,C,D component
 class E,E1,E2,E3,E1A,E1B,E1C,E1D,E1E,E1F modules
 class F,F1,F2,F3,F1A,F1B,F1C impl
```

**Color Legend:**

- **Blue** - Root directory (terraform/)
- **Light Blue** - Component directories (base-infra/, infra/, observ-infra/)
- **Green** - Reusable modules (aws/, azure/, gcp/ modules)
- **Pink** - Cloud implementations (deployment configurations)

## Component Overview

### Base Infrastructure (base-infra)

- **Purpose**: Foundational networking and VPN access
- **Includes**: VPC/VNet, Subnets, Security Groups, Jumpserver, WireGuard VPN
- **Lifecycle**: Deploy once, rarely destroyed
- **State File**: `{cloud}-base-infra-terraform.tfstate`

### MOSIP Infrastructure (infra)

- **Purpose**: Core MOSIP services and external dependencies
- **Includes**: Kubernetes cluster for MOSIP core services, external PostgreSQL setup, databases, storage
- **PostgreSQL Integration**: External PostgreSQL 15 setup via Terraform + Ansible (configurable)
- **Workloads**: Authentication, Registration, Partner Management, etc.
- **Lifecycle**: Can be destroyed and recreated as needed
- **State File**: `{cloud}-infra-terraform.tfstate`

### Observation Infrastructure (observ-infra)

- **Purpose**: Observation and monitoring tools
- **Includes**: Minimal Kubernetes cluster for observation tools
- **Workloads**: Rancher UI, Keycloak, Integration services
- **Resources**: Minimal CPU/Memory configuration (different from infra)
- **Lifecycle**: Independent from MOSIP core services
- **State File**: `{cloud}-observ-infra-terraform.tfstate`

## Deployment Workflow

### Three-Phase Deployment Strategy

```mermaid
sequenceDiagram
 participant User
 participant GitHub Actions
 participant Cloud Provider
 participant Terraform State
 
 Note over User,Terraform State: Phase 1: Base Infrastructure (One-time)
 User->>GitHub Actions: Trigger terraform.yml<br/>(base-infra)
 GitHub Actions->>Cloud Provider: Deploy VPC, Jumpserver, WireGuard
 Cloud Provider-->>Terraform State: Store base-infra state
 GitHub Actions-->>User: Base infrastructure ready
 
 Note over User,Terraform State: Phase 2: MOSIP Infrastructure (Repeatable)
 User->>GitHub Actions: Trigger terraform.yml<br/>(infra)
 GitHub Actions->>Cloud Provider: Deploy K8s for MOSIP core/external services
 Cloud Provider-->>Terraform State: Store infra state
 GitHub Actions-->>User: MOSIP infrastructure ready
 
 Note over User,Terraform State: Phase 3: Observation Infrastructure (Independent)
 User->>GitHub Actions: Trigger terraform.yml<br/>(observ-infra)
 GitHub Actions->>Cloud Provider: Deploy K8s for Rancher UI, Keycloak
 Cloud Provider-->>Terraform State: Store observ-infra state
 GitHub Actions-->>User: Observation infrastructure ready
 
 Note over User,Terraform State: Phase 4: Safe Destruction (When needed)
 User->>GitHub Actions: Trigger terraform-destroy.yml<br/>(infra or observ-infra)
 GitHub Actions->>Cloud Provider: Destroy selected resources
 Cloud Provider-->>Terraform State: Clear selected state
 GitHub Actions-->>User: Resources destroyed, base intact
```

## Quick Start Guide

### Prerequisites

1. **GitHub Secrets Configuration** (per cloud):
 ```yaml
 # AWS (Complete Implementation)
 AWS_ACCESS_KEY_ID: your-aws-access-key
 AWS_SECRET_ACCESS_KEY: your-aws-secret-key

 # Azure (Placeholder Implementation) 
 AZURE_CLIENT_ID: your-azure-client-id
 AZURE_CLIENT_SECRET: your-azure-client-secret
 AZURE_SUBSCRIPTION_ID: your-azure-subscription-id
 AZURE_TENANT_ID: your-azure-tenant-id

 # GCP (Placeholder Implementation)
 GOOGLE_CREDENTIALS: your-gcp-service-account-json

 # Common Requirements
 YOUR_SSH_KEY_NAME: your-ssh-private-key-content
 WG_CONFIG: wireguard-configuration
 
 # GPG Encryption (Required for State Management)
 GPG_PRIVATE_KEY: |
 -----BEGIN PGP PRIVATE KEY BLOCK-----
 your-gpg-private-key-content
 -----END PGP PRIVATE KEY BLOCK-----
 
 # Optional
 SLACK_WEBHOOK_URL: slack-webhook-for-notifications
 ```

2. **GPG Key Setup** (for state file encryption):
 ```bash
 # Generate GPG key pair (if you don't have one)
 gpg --full-generate-key
 
 # Export private key for GitHub secret
 gpg --armor --export-secret-keys your-key-id
 
 # Export public key (for team sharing)
 gpg --armor --export your-key-id
 ```

3. **No Remote State Storage Required**:
 - **Local Backend**: State files encrypted with GPG and stored in repository
 - **No S3/Azure Storage/GCS needed**: Eliminates remote storage dependencies
 - **Enhanced Security**: GPG encryption provides better access control than cloud storage

### Step 1: Deploy Base Infrastructure

```bash
# Via GitHub Actions UI:
# 1. Go to Actions → terraform plan / apply
# 2. Select:
# - CLOUD_PROVIDER: aws
# - TERRAFORM_COMPONENT: base-infra
# - SSH_PRIVATE_KEY: YOUR_SSH_KEY_NAME
# - TERRAFORM_APPLY: true
```

### Step 2: Deploy MOSIP Infrastructure

```bash
# Via GitHub Actions UI:
# 1. Go to Actions → terraform plan / apply 
# 2. Select:
# - CLOUD_PROVIDER: aws
# - TERRAFORM_COMPONENT: infra
# - SSH_PRIVATE_KEY: YOUR_SSH_KEY_NAME
# - TERRAFORM_APPLY: true
```

### Step 3: Deploy Observation Infrastructure (Optional)

```bash
# Via GitHub Actions UI:
# 1. Go to Actions → terraform plan / apply 
# 2. Select:
# - CLOUD_PROVIDER: aws
# - TERRAFORM_COMPONENT: observ-infra
# - SSH_PRIVATE_KEY: YOUR_SSH_KEY_NAME
# - TERRAFORM_APPLY: true
```

### Step 4: Access Your MOSIP Deployment

After successful deployment, access your MOSIP services:

```bash
# MOSIP Services (from infra)
https://your-domain.mosip.net # MOSIP Landing Page
https://api.your-domain.mosip.net # API Gateway
https://admin.your-domain.mosip.net # Admin Console

# Observation Services (from observ-infra)
https://rancher.your-domain.mosip.net # Rancher UI
https://keycloak.your-domain.mosip.net # Keycloak Management
```

## Directory Structure

```
terraform/
├── README.md # This file
├── base-infra/ # Foundational infrastructure
│ ├── main.tf # Cloud selector for base infrastructure
│ ├── variables.tf # Common base infrastructure variables
│ ├── outputs.tf # Common base infrastructure outputs
│ ├── aws/ # AWS base infrastructure
│ │ ├── main.tf # AWS VPC, subnets, jumpserver, WireGuard
│ │ ├── variables.tf # AWS-specific base variables
│ │ └── outputs.tf # AWS base infrastructure outputs
│ ├── azure/ # Azure base infrastructure (placeholder)
│ └── gcp/ # GCP base infrastructure (placeholder)
├── infra/ # MOSIP infrastructure interface
│ ├── main.tf # Cloud selector for MOSIP infrastructure
│ ├── variables.tf # Common MOSIP variables
│ ├── outputs.tf # Common MOSIP outputs
│ ├── aws/ # AWS MOSIP infrastructure interface
│ │ ├── main.tf # Calls AWS modules for MOSIP services
│ │ ├── variables.tf # AWS-specific MOSIP variables
│ │ └── outputs.tf # AWS MOSIP outputs
│ ├── azure/ # Azure MOSIP infrastructure (placeholder)
│ └── gcp/ # GCP MOSIP infrastructure (placeholder)
├── observ-infra/ # Observation infrastructure interface
│ ├── main.tf # Cloud selector for observation infrastructure
│ ├── variables.tf # Common observation variables
│ ├── outputs.tf # Common observation outputs
│ ├── aws/ # AWS observation infrastructure interface
│ │ ├── main.tf # Calls AWS modules for Rancher UI, Keycloak
│ │ ├── variables.tf # AWS-specific observation variables
│ │ └── outputs.tf # AWS observation outputs
│ ├── azure/ # Azure observation infrastructure (placeholder)
│ └── gcp/ # GCP observation infrastructure (placeholder)
├── modules/ # Reusable infrastructure modules
│ ├── aws/ # AWS-specific modules
│ │ ├── main.tf # AWS module interface
│ │ ├── variables.tf # AWS module variables
│ │ ├── outputs.tf # AWS module outputs
│ │ ├── aws-resource-creation/ # Core AWS resources
│ │ ├── nginx-setup/ # NGINX load balancer setup
│ │ ├── rke2-cluster/ # RKE2 Kubernetes cluster
│ │ ├── nfs-setup/ # NFS storage setup
│ │ ├── postgresql-setup/ # External PostgreSQL 15 database setup
│ │ └── rancher-keycloak-setup/ # Rancher UI + Keycloak integration
│ ├── azure/ # Azure modules (placeholder)
│ └── gcp/ # GCP modules (placeholder)
├── implementations/ # Deployable configurations
│ ├── aws/ # AWS implementations
│ │ ├── base-infra/ # AWS base infrastructure deployment
│ │ │ ├── main.tf # Points to base-infra/aws
│ │ │ ├── variables.tf # AWS base configuration
│ │ │ ├── outputs.tf # AWS base outputs
│ │ │ └── aws.tfvars # AWS base configuration values
│ │ ├── infra/ # AWS MOSIP infrastructure deployment
│ │ │ ├── main.tf # Points to infra/aws
│ │ │ ├── variables.tf # AWS MOSIP configuration
│ │ │ ├── outputs.tf # AWS MOSIP outputs
│ │ │ └── aws.tfvars # AWS MOSIP configuration values
│ │ └── observ-infra/ # AWS observation infrastructure deployment
│ │ ├── main.tf # Points to observ-infra/aws
│ │ ├── variables.tf # AWS observation configuration
│ │ ├── outputs.tf # AWS observation outputs
│ │ └── aws.tfvars # AWS observation configuration values
│ ├── azure/ # Azure implementations
│ │ ├── base-infra/ # Azure base infrastructure
│ │ ├── infra/ # Azure MOSIP infrastructure
│ │ └── observ-infra/ # Azure observation infrastructure
│ └── gcp/ # GCP implementations
│ ├── base-infra/ # GCP base infrastructure
│ ├── infra/ # GCP MOSIP infrastructure
│ └── observ-infra/ # GCP observation infrastructure
```

## State Management

### Local Backend with GPG Encryption

**Modern Secure Approach**: Instead of remote S3/Azure/GCS backends, MOSIP uses **local backend with GPG encryption** for enhanced security and simplicity:

```
Encrypted State Management
===========================

Local State Files (Encrypted with GPG):
├── .terraform-state/
│ ├── aws-base-infra-testgrid-terraform.tfstate.gpg ← Encrypted
│ ├── aws-infra-testgrid-terraform.tfstate.gpg ← Encrypted 
│ └── aws-observ-infra-testgrid-terraform.tfstate.gpg ← Encrypted

Temporary Decrypted Files (During Operations):
├── terraform/base-infra/
│ └── aws-base-infra-testgrid-terraform.tfstate ← Temporary
├── terraform/infra/
│ └── aws-infra-testgrid-terraform.tfstate ← Temporary
└── terraform/observ-infra/
 └── aws-observ-infra-testgrid-terraform.tfstate ← Temporary
```

### GPG Encryption Benefits

- **Enhanced Security**: State files encrypted with AES256 before storage
- **Git-Safe Storage**: Encrypted files safely committed to repository
- **Access Control**: Only users with GPG private key can access state
- **Branch Isolation**: State files include branch name for separation
- **No Remote Dependencies**: No need for S3 buckets or cloud storage setup
- **Simplified Deployment**: Automatic encryption/decryption in workflows

### Custom State File Naming

State files use descriptive naming pattern: `{provider}-{component}-{branch}-terraform.tfstate`

```
Examples:
├── aws-base-infra-main-terraform.tfstate.gpg # Production base infrastructure
├── aws-infra-staging-terraform.tfstate.gpg # Staging MOSIP cluster 
├── aws-observ-infra-development-terraform.tfstate.gpg # Dev monitoring cluster
└── azure-infra-testgrid-terraform.tfstate.gpg # Test environment
```

### Isolated State Files

Each cloud provider and component combination maintains its own encrypted state file:

```
Encrypted State File Isolation Structure
=========================================

AWS Encrypted States (.gpg files):
├── aws-base-infra-{branch}-terraform.tfstate.gpg (VPC, Jumpserver, WireGuard)
├── aws-infra-{branch}-terraform.tfstate.gpg (K8s for MOSIP Core/External)
└── aws-observ-infra-{branch}-terraform.tfstate.gpg (K8s for Rancher UI, Keycloak)

Azure Encrypted States (.gpg files):
├── azure-base-infra-{branch}-terraform.tfstate.gpg (VNet, Jumpserver, WireGuard) 
├── azure-infra-{branch}-terraform.tfstate.gpg (RKE2 for MOSIP Core/External)
└── azure-observ-infra-{branch}-terraform.tfstate.gpg (RKE2 for Rancher UI, Keycloak)

GCP Encrypted States (.gpg files):
├── gcp-base-infra-{branch}-terraform.tfstate.gpg (VPC, Jumpserver, WireGuard)
├── gcp-infra-{branch}-terraform.tfstate.gpg (RKE2 for MOSIP Core/External)
└── gcp-observ-infra-{branch}-terraform.tfstate.gpg (RKE2 for Rancher UI, Keycloak)
```

### Benefits of GPG Encrypted Isolated States

- **Enhanced Security**: All state files encrypted before storage
- **Branch Isolation**: Each branch has separate encrypted state files 
- **No Cloud Dependencies**: No need for S3/Azure Storage/GCS setup
- **Access Control**: Only users with GPG private key can decrypt states
- **Git-Safe Storage**: Encrypted states safely committed to repository
- **No Cross-Cloud Interference**: Each cloud is completely isolated
- **Safe Partial Destruction**: Destroy MOSIP or observation infrastructure without affecting base
- **Independent Scaling**: Scale each cloud deployment independently
- **Component Isolation**: MOSIP services and observation tools are separate
- **Reduced Blast Radius**: Errors in one component don't affect others
- **Parallel Development**: Teams can work on different clouds and components simultaneously

## GitHub Actions Workflows

### terraform.yml - Infrastructure Deployment

**Inputs:**

- `CLOUD_PROVIDER`: aws | azure | gcp
- `TERRAFORM_COMPONENT`: base-infra | infra | observ-infra
- `SSH_PRIVATE_KEY`: GitHub secret name
- `TERRAFORM_APPLY`: true/false

**Workflow Features:**

- Dynamic backend configuration per cloud
- Component-specific warnings and validations
- Isolated working directories
- Support for all three components
- Comprehensive logging and status reporting

### terraform-destroy.yml - Infrastructure Destruction

**Inputs:**

- `CLOUD_PROVIDER`: aws | azure | gcp
- `TERRAFORM_COMPONENT`: infra | observ-infra (base-infra protected)
- `SSH_PRIVATE_KEY`: GitHub secret name
- `TERRAFORM_DESTROY`: true (required for confirmation)

**Safety Features:**

- Critical warnings for base-infra destruction
- Explicit confirmation required
- Automatic cleanup of state files after successful destruction
- Detailed destruction planning before execution

## Key Benefits

### True Cloud Agnostic

- Deploy to AWS, Azure, and GCP with identical interfaces
- Switch clouds without changing core logic
- Multi-cloud deployments for high availability

### Modular Architecture

- Clear separation between base and application infrastructure
- Reusable modules across different deployments
- Easy to extend with new cloud providers

### Safe Operations

- Isolated state management prevents accidental interference
- Explicit confirmation required for destructive operations
- Comprehensive validation and error handling

### Scalable Design

- Support for multiple environments per cloud
- Easy to add new components and modules
- Consistent patterns across all clouds

### Developer Friendly

- Intuitive directory structure
- Comprehensive documentation and examples
- GitHub Actions integration for CI/CD

## Advanced Usage

### Multi-Cloud Deployment

Deploy the same MOSIP infrastructure across multiple clouds:

```
Deployment Sequence:
# Deploy to AWS
terraform.yml → CLOUD_PROVIDER: aws, TERRAFORM_COMPONENT: base-infra
terraform.yml → CLOUD_PROVIDER: aws, TERRAFORM_COMPONENT: infra

# Deploy to Azure 
terraform.yml → CLOUD_PROVIDER: azure, TERRAFORM_COMPONENT: base-infra
terraform.yml → CLOUD_PROVIDER: azure, TERRAFORM_COMPONENT: infra

# Deploy to GCP
terraform.yml → CLOUD_PROVIDER: gcp, TERRAFORM_COMPONENT: base-infra
terraform.yml → CLOUD_PROVIDER: gcp, TERRAFORM_COMPONENT: infra
```

### Environment-Specific Deployments

Create multiple environments by duplicating implementation directories:

```
implementations/
├── aws/
│ ├── base-infra/ # Shared base infrastructure
│ ├── infra-prod/ # Production environment
│ ├── infra-staging/ # Staging environment 
│ └── infra-dev/ # Development environment
```

### Custom Module Development

Add new modules following the established pattern:

```
modules/
├── aws/
│ ├── your-custom-module/
│ │ ├── main.tf
│ │ ├── variables.tf
│ │ └── outputs.tf
```

## Troubleshooting

### Common Issues

1. **State File Conflicts**

 ```
 Error: Resource already exists in state
 ```

 **Solution**: Ensure you're not mixing old and new directory structures
2. **Backend Configuration Issues**

 ```
 Error: Backend configuration changed
 ```

 **Solution**: Run `terraform init -reconfigure` in the implementation directory
3. **Missing Dependencies**

 ```
 Error: base-infra resources not found
 ```

 **Solution**: Deploy base-infra before application infrastructure

### Debugging Tips

- Enable Terraform logging: Set `TF_LOG=DEBUG` in workflow
- Check state file location in cloud storage
- Verify cloud provider credentials and permissions
- Review implementation directory tfvars files

## Support and Contributing

### Getting Help

- Review [GitHub Actions Workflows](../.github/workflows/README.md) for CI/CD details
- Open issues for bugs or feature requests

### Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/your-feature`
3. Follow the established directory structure and naming conventions
4. Test changes with both plan and apply operations
5. Submit pull request with detailed description

## License

This project is licensed under the [Mozilla Public License 2.0](../LICENSE).

---

**Built for the MOSIP Community**

*Enabling secure, scalable, and cloud-agnostic identity infrastructure worldwide.*
