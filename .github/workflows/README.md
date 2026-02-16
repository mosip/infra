# GitHub Actions Workflows Documentation

> **Complete guide to automated infrastructure and application deployment workflows**

## Overview

This directory contains GitHub Actions workflows for automated MOSIP deployment:
- **Terraform workflows** for infrastructure provisioning (AWS complete, Azure/GCP placeholders)
- **Helmsman workflows** for application deployment on provisioned infrastructure 
- **GPG encrypted state management** with branch isolation
- **Sequential workflow execution** with parallel optimization within Helmsman phase

## Available Workflows

| Workflow | Purpose | Trigger | State Management | PostgreSQL |
|----------|---------|---------|------------------|------------|
| `terraform.yml` | Deploy/Update Infrastructure | Manual Dispatch | GPG encrypted local | Integrated via Terraform |
| `terraform-destroy.yml` | Destroy Infrastructure | Manual Dispatch | Uses encrypted state | Handles PostgreSQL cleanup |
| `helmsman_external.yml` | Deploy Prerequisites & External Dependencies | Manual Dispatch | Uses deployed infra | **Parallel deployment** |
| `helmsman_mosip.yml` | Deploy MOSIP Services | Manual Dispatch | Uses deployed infra | Uses deployed PostgreSQL |
| `helmsman_testrigs.yml` | Deploy Test Rigs | Manual Dispatch | Uses deployed infra | Testing components |

## Cloud Provider Support

| Provider | Status | Implementation |
|----------|---------|----------------|
| **AWS** | **Complete** | Full infrastructure, VPC, RKE2, PostgreSQL integration |
| **Azure** | **Placeholder** | Basic structure - [community contributions welcome](../terraform/base-infra/azure/) |
| **GCP** | **Placeholder** | Basic structure - [community contributions welcome](../terraform/base-infra/gcp/) |

## Deployment Guide

### Step 1: Deploy Infrastructure with PostgreSQL

1. **Navigate**: Actions → "terraform plan / apply"
2. **Configure Parameters**:
 ```yaml
 CLOUD_PROVIDER: aws # Currently only AWS fully supported
 TERRAFORM_COMPONENT: base-infra # base-infra | infra | observ-infra 
 BACKEND_TYPE: local # local with GPG encryption (recommended)
 REMOTE_BACKEND_CONFIG: "" # Not used with local backend
 SSH_PRIVATE_KEY: SSH_PRIVATE_KEY # GitHub secret name
 TERRAFORM_APPLY: true # false = plan only
 ENABLE_STATE_LOCKING: false # Optional DynamoDB state locking
 ```
3. **Execute**: Click "Run workflow"
4. **PostgreSQL Configuration**: Set in `terraform/implementations/aws/infra/aws.tfvars`:
 ```hcl
 enable_postgresql_setup = true # External PostgreSQL via Terraform + Ansible
 ```

### Step 2: Deploy Prerequisites & External Dependencies (After Infrastructure Ready)

**Prerequisites: Complete Terraform infrastructure deployment first**

1. **Navigate**: Actions → "helmsman external dependencies"
2. **Configure**: Select deployed infrastructure environment
3. **Parallel Execution**: Prerequisites and External Dependencies deploy simultaneously
4. **Duration**: ~70-110 minutes (20% faster than sequential approach)

### Step 3: Deploy MOSIP Services (After Prerequisites Ready)

1. **Navigate**: Actions → "helmsman mosip services" 
2. **PostgreSQL Integration**: Automatically uses deployed PostgreSQL
3. **Duration**: ~25-35 minutes

### Step 4: Destroy Infrastructure (When Needed)

1. **Navigate**: Actions → "terraform destroy"
2. **Configure**: Use same parameters as deployment
3. **Confirm**: Set `TERRAFORM_DESTROY: true`
4. **PostgreSQL Cleanup**: Automatically handled
5. **Execute**: Click "Run workflow"

## PostgreSQL Integration

### Terraform Configuration (Not Workflow Parameter)
PostgreSQL is configured in Terraform variables, not as a workflow input:

```hcl
# terraform/implementations/aws/infra/aws.tfvars
enable_postgresql_setup = true # Enable external PostgreSQL
nginx_node_ebs_volume_size_2 = 200 # EBS volume size for PostgreSQL data
postgresql_version = "15" # PostgreSQL version
postgresql_port = "5433" # PostgreSQL port
```

### PostgreSQL Deployment Options
- **External Database** (`enable_postgresql_setup = true`): Production-ready PostgreSQL on dedicated instances via Terraform + Ansible
- **Container Database** (`enable_postgresql_setup = false`): In-cluster PostgreSQL for development via Helmsman

## Three-Component Architecture

```
Component Deployment Order
==========================

Step 1: Foundation (One-time)
├── Component: base-infra
├── Resources: VPC, Subnets, WireGuard
└── Purpose: Network foundation

Step 2: Management (Optional)
├── Component: observ-infra
├── Resources: Rancher UI, Keycloak
├── Dependencies: base-infra
└── Purpose: Cluster management

Step 3: Application (Repeatable)
├── Component: infra
├── Resources: MOSIP K8s clusters
├── Dependencies: base-infra
└── Purpose: MOSIP deployments
```

```mermaid
graph LR
 A[base-infra<br/>Foundation] --> B[observ-infra<br/>Management<br/>Optional]
 A --> C[infra<br/>MOSIP Clusters]
 B -.->|Import Clusters| C
 C --> D[Multiple MOSIP<br/>Deployments]
 
 style A fill:#e1f5fe,stroke:#01579b,stroke-width:2px,color:#000000
 style B fill:#fff3e0,stroke:#f57c00,stroke-width:2px,color:#000000
 style C fill:#f3e5f5,stroke:#4a148c,stroke-width:2px,color:#000000
 style D fill:#e8f5e8,stroke:#1b5e20,stroke-width:2px,color:#000000
```

| Component | Purpose | Deployment Order | Dependencies | Lifecycle |
|-----------|---------|------------------|--------------|-----------|
| **base-infra** | VPC, Networking, WireGuard VPN | 1st (Foundation) | None | One-time setup |
| **observ-infra** | Rancher UI, Keycloak, RBAC management | 2nd (Optional) | base-infra | One-time setup |
| **infra** | MOSIP Kubernetes clusters (RKE2, NGINX, NFS) | 3rd (Multiple) | base-infra | Multiple deployments |

## Workflow Execution Flow

```mermaid
graph TD
 START[GitHub Actions Trigger] --> VALIDATE[Validate Parameters]
 VALIDATE --> SETUP[Setup Terraform & Cloud Credentials]
 SETUP --> BACKEND[Configure Local Backend with GPG]
 
 BACKEND --> DECRYPT{Encrypted State Exists?}
 DECRYPT -->|Yes| DECRYPTSTATE[Decrypt State with GPG]
 DECRYPT -->|No| INIT[terraform init]
 DECRYPTSTATE --> INIT
 
 INIT --> PLAN[terraform plan]
 PLAN --> DECISION{Apply or Plan Only?}
 
 DECISION -->|Plan Only| OUTPUT[Show Plan Output]
 DECISION -->|Apply| APPLY[terraform apply]
 
 APPLY --> ENCRYPT[Encrypt State with GPG]
 ENCRYPT --> SUCCESS[Deployment Complete]
 OUTPUT --> COMPLETE[Workflow Complete]
 SUCCESS --> COMPLETE
 
 style START fill:#e8f5e8,stroke:#1b5e20,stroke-width:2px,color:#000000
 style APPLY fill:#f3e5f5,stroke:#4a148c,stroke-width:2px,color:#000000
 style SUCCESS fill:#e1f5fe,stroke:#01579b,stroke-width:2px,color:#000000
```

**Note**: PostgreSQL setup is handled by Terraform modules and Ansible during the `terraform apply` step based on `enable_postgresql_setup` configuration in `.tfvars` files, not as a separate workflow step.

## GPG Encrypted State Management

### Production-Grade Features
- **Zero-configuration GPG**: Uses GPG_PRIVATE_KEY secret automatically
- **AES256 encryption**: Local state files encrypted with GPG
- **Custom naming**: Pattern: `{provider}-{component}-{branch}-terraform.tfstate`
- **Git safety**: Encrypted state files tracked in repository
- **Branch isolation**: Complete separation of environment states

### State File Organization
```bash
# Repository Structure (Encrypted)
.terraform-state/
├── aws-base-infra-testgrid-terraform.tfstate.gpg
├── aws-infra-testgrid-terraform.tfstate.gpg
└── aws-observ-infra-testgrid-terraform.tfstate.gpg

# Decrypted for Terraform Use (Temporary)
terraform/base-infra/aws-base-infra-testgrid-terraform.tfstate
terraform/infra/aws-infra-testgrid-terraform.tfstate
terraform/observ-infra/aws-observ-infra-testgrid-terraform.tfstate
```

### GPG Key Management
```bash
# Required GitHub Secret
GPG_PRIVATE_KEY: |
 -----BEGIN PGP PRIVATE KEY BLOCK-----
 <your-gpg-private-key>
 -----END PGP PRIVATE KEY BLOCK-----
```

## Parameter Reference

### Required Parameters

| Parameter | Description | Values | Example |
|-----------|-------------|---------|---------|
| `CLOUD_PROVIDER` | Target cloud platform | `aws` (fully supported) \| `azure` \| `gcp` (placeholders) | `aws` |
| `TERRAFORM_COMPONENT` | Infrastructure component | `base-infra` \| `observ-infra` \| `infra` | `base-infra` |
| `BACKEND_TYPE` | State storage method | `local` (recommended) \| `remote` | `local` |
| `SSH_PRIVATE_KEY` | GitHub secret for SSH access | Secret name | `SSH_PRIVATE_KEY` |
| `GPG_PRIVATE_KEY` | GitHub secret for state encryption | Secret name | `GPG_PRIVATE_KEY` |

### Backend Configuration

#### Local Backend (Recommended)
```yaml
BACKEND_TYPE: local
# State files encrypted with GPG and stored in repository
# Custom naming: aws-infra-testgrid-terraform.tfstate
```

#### Remote Backend (Legacy Support) 
```yaml
BACKEND_TYPE: remote
REMOTE_BACKEND_CONFIG: aws:bucket-name:region
# Format: <cloud>:<bucket-name>:<region>
# Example: aws:mosip-terraform-bucket:us-west-2
```

### Optional Parameters

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `TERRAFORM_APPLY` | Execute apply after plan | `false` | `true` \| `false` |
| `TERRAFORM_DESTROY` | Destroy infrastructure | `false` | `true` \| `false` |
| `ENABLE_STATE_LOCKING` | Enable DynamoDB state locking | `false` | `true` \| `false` |

**Note**: PostgreSQL configuration is set in Terraform `.tfvars` files, not as workflow parameters.

## Security & Access Control

### Required GitHub Secrets
```yaml
# GPG Encryption for State Files
GPG_PRIVATE_KEY: |
 -----BEGIN PGP PRIVATE KEY BLOCK-----
 <your-gpg-private-key>
 -----END PGP PRIVATE KEY BLOCK-----

# SSH Access for jumpserver
SSH_PRIVATE_KEY: |
 -----BEGIN OPENSSH PRIVATE KEY-----
 <your-private-key-content>
 -----END OPENSSH PRIVATE KEY-----

# AWS Credentials (Complete Implementation)
AWS_ACCESS_KEY_ID: AKIA...
AWS_SECRET_ACCESS_KEY: wJalr...

# Azure Credentials (Placeholder Implementation)
AZURE_CLIENT_ID: 12345678-1234-1234-1234-123456789012
AZURE_CLIENT_SECRET: secret-value
AZURE_SUBSCRIPTION_ID: 12345678-1234-1234-1234-123456789012
AZURE_TENANT_ID: 12345678-1234-1234-1234-123456789012

# GCP Credentials (Placeholder Implementation)
GOOGLE_CREDENTIALS: |
 {
 "type": "service_account",
 "project_id": "your-project",
 ...
 }

# Optional: Slack notifications
SLACK_WEBHOOK_URL: https://hooks.slack.com/services/...
```

### Security Best Practices
- **GPG encryption**: All state files encrypted before commit
- **Least privilege access**: IAM roles with minimal required permissions
- **Secret rotation**: Regular rotation of access keys and GPG keys
- **Audit logging**: CloudTrail/Activity logs enabled for all operations
- **Network isolation**: Resources deployed in private subnets
- **Database security**: PostgreSQL with encrypted storage and secure access

## Workflow Examples

### Complete AWS Deployment with PostgreSQL
```yaml
# Deploy base infrastructure
CLOUD_PROVIDER: aws
TERRAFORM_COMPONENT: base-infra
BACKEND_TYPE: local
SSH_PRIVATE_KEY: SSH_PRIVATE_KEY
GPG_PRIVATE_KEY: GPG_PRIVATE_KEY
TERRAFORM_APPLY: true

# PostgreSQL configured in terraform/implementations/aws/infra/aws.tfvars:
# enable_postgresql_setup = true
```

### Multi-Environment Setup
```yaml
# Production deployment (main branch)
CLOUD_PROVIDER: aws
TERRAFORM_COMPONENT: infra
BACKEND_TYPE: local
# State: aws-infra-main-terraform.tfstate.gpg

# Staging deployment (staging branch) 
CLOUD_PROVIDER: aws
TERRAFORM_COMPONENT: infra
BACKEND_TYPE: local
# State: aws-infra-staging-terraform.tfstate.gpg
```

### Sequential Workflow Deployment
```yaml
# Step 1: Deploy Terraform infrastructure (must complete first)
Workflow: terraform.yml
 Component: base-infra → Deploy foundational infrastructure
 Component: observ-infra → Deploy monitoring cluster (optional)
 Component: infra → Deploy MOSIP cluster + PostgreSQL

# Step 2: Deploy Helmsman components (after Terraform complete)
Workflow: helmsman_external.yml → Parallel deployment:
 - Prerequisites: Monitoring, Istio, Logging
 - External Dependencies: PostgreSQL connection, MinIO, Keycloak, Kafka

# Step 3: Deploy MOSIP services (after external dependencies ready)
Workflow: helmsman_mosip.yml → Deploy MOSIP applications

# Optional: Deploy test components
Workflow: helmsman_testrigs.yml → Deploy testing infrastructure
```

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| **GPG Decryption Failed** | Invalid GPG private key | Verify GPG_PRIVATE_KEY secret is correct |
| **State File Not Found** | Missing encrypted state | Check .terraform-state/ directory for .gpg files |
| **Provider Auth Failed** | Invalid credentials | Check cloud provider secrets configuration |
| **Module Not Found** | Git access issues | Verify SSH key has repository access |
| **PostgreSQL Connection Failed** | Database not ready | Wait for Ansible PostgreSQL setup to complete |
| **Azure/GCP Placeholder Error** | Incomplete implementation | Use AWS or contribute to Azure/GCP modules |

### Debug Steps
1. **Check workflow logs**: Review GitHub Actions execution logs
2. **Validate GPG key**: Ensure GPG_PRIVATE_KEY secret is configured
3. **Verify cloud credentials**: Check AWS/Azure/GCP secrets
4. **Test connectivity**: Verify network access to cloud APIs
5. **State inspection**: Decrypt and inspect state files manually
6. **PostgreSQL logs**: Check Ansible output for database setup

### Cloud Provider Debugging

#### AWS (Full Support)
- Check IAM permissions for EC2, VPC, RDS
- Verify region availability and quota limits
- Test AWS CLI connectivity with provided credentials

#### Azure/GCP (Placeholder)
- Current implementations use `null_resource` placeholders
- No actual cloud resources are created
- Community contributions needed for full implementation

## Integration with Terraform Components

### GitHub Actions Workflow Sequence
```mermaid
sequenceDiagram
 participant User
 participant Terraform Workflows
 participant Helmsman Workflows
 participant AWS Infrastructure
 participant PostgreSQL
 
 User->>Terraform Workflows: 1. Deploy base-infra
 Terraform Workflows->>AWS Infrastructure: Create VPC, WireGuard
 AWS Infrastructure-->>User: Base infrastructure ready
 
 User->>Terraform Workflows: 2. Deploy infra + PostgreSQL
 Terraform Workflows->>AWS Infrastructure: Create RKE2 cluster
 Terraform Workflows->>PostgreSQL: Setup PostgreSQL 15 via Ansible
 AWS Infrastructure-->>User: MOSIP cluster + PostgreSQL ready
 
 User->>Helmsman Workflows: 3. Deploy Prerequisites (parallel)
 User->>Helmsman Workflows: 3. Deploy External Dependencies (parallel)
 Helmsman Workflows-->>AWS Infrastructure: Install Prerequisites & Dependencies
 AWS Infrastructure-->>User: Prerequisites & Dependencies ready (70-110 min)
 
 User->>Helmsman Workflows: 4. Deploy MOSIP Services
 Helmsman Workflows->>PostgreSQL: Connect to external database
 AWS Infrastructure-->>User: MOSIP platform operational
```

### Workflow Execution Order

1. **Terraform Workflows** (Sequential - Infrastructure Setup):
 - `terraform.yml` → Deploy base-infra
 - `terraform.yml` → Deploy observ-infra (optional)
 - `terraform.yml` → Deploy infra + PostgreSQL

2. **Helmsman Workflows** (Can run in parallel after Terraform complete):
 - `helmsman_external.yml` → Prerequisites + External Dependencies (simultaneous)
 - `helmsman_mosip.yml` → MOSIP Services (after external dependencies ready)
 - `helmsman_testrigs.yml` → Test components (optional)

### Parallel Deployment Architecture
```mermaid
graph TD
 A[Terraform Infrastructure Complete] --> B[Helmsman Workflows Triggered]
 
 B --> C[Prerequisites Workflow]
 B --> D[External Dependencies Workflow]
 
 C -->|Parallel| E[Monitoring Stack]
 C -->|Parallel| F[Istio Service Mesh]
 C -->|Parallel| G[Logging Infrastructure]
 
 D -->|Parallel| H[PostgreSQL Connection]
 D -->|Parallel| I[MinIO Storage]
 D -->|Parallel| J[Keycloak IAM]
 D -->|Parallel| K[Kafka Messaging]
 
 E --> L[MOSIP Services Deployment]
 F --> L
 G --> L
 H --> L
 I --> L
 J --> L
 K --> L
 
 style A fill:#e1f5fe,stroke:#01579b,stroke-width:2px,color:#000000
 style B fill:#e8f5e8,stroke:#1b5e20,stroke-width:2px,color:#000000
 style C fill:#fff3e0,stroke:#f57c00,stroke-width:2px,color:#000000
 style D fill:#fff3e0,stroke:#f57c00,stroke-width:2px,color:#000000
 style L fill:#f3e5f5,stroke:#4a148c,stroke-width:2px,color:#000000
```

**Sequential Dependency**: Terraform workflows must complete before Helmsman workflows 
**Parallel Optimization**: Prerequisites and External Dependencies run simultaneously via separate Helmsman workflows

---

## Support & Best Practices

**Workflow Maintenance**: Keep workflows updated with latest Terraform versions 
**State Management**: GPG encrypted state with branch-based isolation 
**Security Reviews**: Regular rotation of GPG keys and cloud credentials 
**PostgreSQL Management**: Automated setup via Terraform + Ansible integration 
**Performance Optimization**: Use parallel deployment for 20% faster setup times 

## Cloud Provider Contribution Guide

**AWS** - Production ready with full feature set 
**Azure** - [Placeholder implementation](../terraform/base-infra/azure/main.tf) - contributions welcome 
**GCP** - [Placeholder implementation](../terraform/base-infra/gcp/main.tf) - contributions welcome 

**Community contributions needed for Azure and GCP implementations**

**Professional infrastructure automation with enterprise-grade security, PostgreSQL integration, and parallel deployment capabilities**
