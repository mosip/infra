# GitHub Actions Terraform Workflows

> **Automated infrastructure deployment with remote state management**

## Overview

Production-ready Terraform automation supporting:
- **Automated S3 state management** with encryption & versioning
- **Multi-cloud deployments** (AWS, Azure, GCP)
- **Branch-based environments** (main, staging, dev)
- **Component-based architecture** (base-infra, infra, observ-infra)

## Available Workflows

| Workflow | Purpose | Trigger | State Management |
|----------|---------|---------|------------------|
| `terraform.yml` | Deploy/Update Infrastructure | Manual Dispatch | Creates S3 buckets |
| `terraform-destroy.yml` | Destroy Infrastructure | Manual Dispatch | Uses existing buckets |

## Deployment Guide

### Step 1: Deploy Infrastructure

1. **Navigate**: Actions → "terraform plan / apply"
2. **Configure Parameters**:
   ```yaml
   CLOUD_PROVIDER: aws                    # aws | azure | gcp
   TERRAFORM_COMPONENT: base-infra        # base-infra | infra | observ-infra  
   BACKEND_TYPE: remote                   # local | remote (recommended)
   REMOTE_BACKEND_CONFIG: aws:mosip-terraform-bucket:us-west-2
   SSH_PRIVATE_KEY: SSH_PRIVATE_KEY       # GitHub secret name
   TERRAFORM_APPLY: true                  # false = plan only
   ```
3. **Execute**: Click "Run workflow"

### Step 2: Destroy Infrastructure (When Needed)

1. **Navigate**: Actions → "terraform destroy"
2. **Configure**: Use same parameters as deployment
3. **Confirm**: Set `TERRAFORM_DESTROY: true`
4. **Execute**: Click "Run workflow"

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
    SETUP --> S3CHECK{S3 Backend Exists?}
    
    S3CHECK -->|No| CREATES3[Create S3 Bucket<br/>Enable Encryption<br/>Enable Versioning<br/>Block Public Access]
    S3CHECK -->|Yes| INIT[terraform init]
    CREATES3 --> INIT
    
    INIT --> PLAN[terraform plan]
    PLAN --> DECISION{Apply or Plan Only?}
    
    DECISION -->|Plan Only| OUTPUT[Show Plan Output]
    DECISION -->|Apply| APPLY[terraform apply]
    
    APPLY --> SUCCESS[Deployment Complete]
    OUTPUT --> COMPLETE[Workflow Complete]
    SUCCESS --> COMPLETE
    
    style START fill:#e8f5e8,stroke:#1b5e20,stroke-width:2px,color:#000000
    style CREATES3 fill:#fff3e0,stroke:#f57c00,stroke-width:2px,color:#000000
    style APPLY fill:#f3e5f5,stroke:#4a148c,stroke-width:2px,color:#000000
    style SUCCESS fill:#e1f5fe,stroke:#01579b,stroke-width:2px,color:#000000
```

## Automated S3 State Management

### Production-Grade Features
- **Zero-configuration setup**: S3 buckets created automatically
- **AES256 encryption**: Server-side encryption enabled by default
- **Versioning enabled**: Complete state file history and rollback
- **Public access blocked**: Security best practices enforced
- **Consistent tagging**: Environment and component identification

### State File Organization
```bash
# Production Environment
mosip-terraform-bucket-main/
├── aws-base-infra-main-terraform.tfstate
├── aws-infra-main-terraform.tfstate
└── aws-observ-infra-main-terraform.tfstate

# Staging Environment
mosip-terraform-bucket-staging/
├── aws-base-infra-staging-terraform.tfstate
├── aws-infra-staging-terraform.tfstate
└── aws-observ-infra-staging-terraform.tfstate
```

## Parameter Reference

### Required Parameters

| Parameter | Description | Values | Example |
|-----------|-------------|---------|---------|
| `CLOUD_PROVIDER` | Target cloud platform | `aws` \| `azure` \| `gcp` | `aws` |
| `TERRAFORM_COMPONENT` | Infrastructure component | `base-infra` \| `observ-infra` \| `infra` | `base-infra` |
| `BACKEND_TYPE` | State storage method | `local` \| `remote` | `remote` |
| `SSH_PRIVATE_KEY` | GitHub secret for SSH access | Secret name | `SSH_PRIVATE_KEY` |

### Backend Configuration

#### Remote Backend (Production)
```yaml
REMOTE_BACKEND_CONFIG: aws:bucket-name:region
# Format: <cloud>:<bucket-name>:<region>
# Example: aws:mosip-terraform-bucket:us-west-2
```

#### Local Backend (Development Only)  
```yaml
BACKEND_TYPE: local
# State files stored in git repository
# Not recommended for production use
```

### Optional Parameters

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `TERRAFORM_APPLY` | Execute apply after plan | `false` | `true` \| `false` |
| `TERRAFORM_DESTROY` | Destroy infrastructure | `false` | `true` \| `false` |

## Security & Access Control

### Required GitHub Secrets
```yaml
# SSH Access for jumpserver
SSH_PRIVATE_KEY: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  <your-private-key-content>
  -----END OPENSSH PRIVATE KEY-----

# AWS Credentials
AWS_ACCESS_KEY_ID: AKIA...
AWS_SECRET_ACCESS_KEY: wJalr...

# Azure Credentials (if using Azure)
AZURE_CLIENT_ID: 12345678-1234-1234-1234-123456789012
AZURE_CLIENT_SECRET: secret-value
AZURE_SUBSCRIPTION_ID: 12345678-1234-1234-1234-123456789012
AZURE_TENANT_ID: 12345678-1234-1234-1234-123456789012

# GCP Credentials (if using GCP)
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
- **Least privilege access**: IAM roles with minimal required permissions
- **Secret rotation**: Regular rotation of access keys and service account keys  
- **Audit logging**: CloudTrail/Activity logs enabled for all operations
- **Network isolation**: Resources deployed in private subnets
- **Encryption at rest**: All state files encrypted with AES256

## Workflow Examples

### Basic Deployment
```yaml
# Deploy base infrastructure on AWS
CLOUD_PROVIDER: aws
TERRAFORM_COMPONENT: base-infra
BACKEND_TYPE: remote
REMOTE_BACKEND_CONFIG: aws:mosip-terraform-bucket:us-west-2
SSH_PRIVATE_KEY: SSH_PRIVATE_KEY
TERRAFORM_APPLY: true
```

### Multi-Environment Setup
```yaml
# Production deployment
CLOUD_PROVIDER: aws
TERRAFORM_COMPONENT: infra
BACKEND_TYPE: remote
REMOTE_BACKEND_CONFIG: aws:mosip-terraform-bucket-prod:us-west-2
TERRAFORM_APPLY: true

# Staging deployment  
CLOUD_PROVIDER: aws
TERRAFORM_COMPONENT: infra
BACKEND_TYPE: remote
REMOTE_BACKEND_CONFIG: aws:mosip-terraform-bucket-staging:us-west-2
TERRAFORM_APPLY: true
```

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| **S3 Access Denied** | Insufficient IAM permissions | Verify IAM policy includes S3 and DynamoDB access |
| **State Lock Error** | Concurrent executions | Wait for other workflow to complete or manually unlock |
| **Provider Auth Failed** | Invalid credentials | Check GitHub secrets configuration |
| **Module Not Found** | Git access issues | Verify SSH key has repository access |
| **Backend Init Failed** | S3 bucket issues | Check bucket exists and has proper permissions |

### Debug Steps
1. **Check workflow logs**: Review GitHub Actions execution logs
2. **Validate credentials**: Ensure all required secrets are configured
3. **Verify permissions**: Check IAM/RBAC permissions for cloud resources
4. **Test connectivity**: Verify network access to cloud APIs
5. **State inspection**: Use `terraform show` to inspect current state

## Integration with Terraform Components

### Deployment Sequence
```mermaid
sequenceDiagram
    participant User
    participant GitHub Actions
    participant S3 Backend
    participant Cloud Provider
    
    User->>GitHub Actions: Trigger workflow (base-infra)
    GitHub Actions->>S3 Backend: Create/verify bucket
    GitHub Actions->>Cloud Provider: Deploy VPC, WireGuard
    Cloud Provider-->>S3 Backend: Store state
    GitHub Actions-->>User: Base infrastructure ready
    
    User->>GitHub Actions: Trigger workflow (observ-infra)
    GitHub Actions->>S3 Backend: Load base-infra state
    GitHub Actions->>Cloud Provider: Deploy Rancher, Keycloak
    Cloud Provider-->>S3 Backend: Store state
    GitHub Actions-->>User: Management ready
    
    User->>GitHub Actions: Trigger workflow (infra)
    GitHub Actions->>S3 Backend: Load existing states
    GitHub Actions->>Cloud Provider: Deploy MOSIP cluster
    Cloud Provider-->>S3 Backend: Store state
    GitHub Actions-->>User: MOSIP infrastructure ready
```

---

## Support & Best Practices

**Workflow Maintenance**: Keep workflows updated with latest Terraform versions  
**State Management**: Regular state file backups and validation  
**Security Reviews**: Periodic review of IAM permissions and secrets  
**Documentation**: Keep parameter documentation current with infrastructure changes

**Professional infrastructure automation with enterprise-grade security and reliability**
