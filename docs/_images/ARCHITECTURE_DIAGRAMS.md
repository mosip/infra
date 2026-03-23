# High-Level Architecture Overview

> **Note:** Complete Terraform scripts are available for **AWS only**. Azure and GCP currently have placeholder structures only — community contributions are welcome to implement full functionality.

## Deployment Flow & Dependencies

```mermaid
graph TD
 A[Start Deployment] --> B{Choose Cloud Provider}
 B -->|AWS| C[AWS Deployment]
 B -->|Azure| D[Azure Deployment] 
 B -->|GCP| E[GCP Deployment]
 
 C --> F[1. Deploy base-infra<br/>VPC + WireGuard<br/>One-time setup]
 D --> G[1. Deploy base-infra<br/>VNet + WireGuard<br/>One-time setup]
 E --> H[1. Deploy base-infra<br/>VPC + WireGuard<br/>One-time setup]
 
 F --> I{Deploy observ-infra?}
 G --> J{Deploy observ-infra?}
 H --> K{Deploy observ-infra?}
 
 I -->|Yes| L[2. Deploy observ-infra<br/>Rancher + Keycloak]
 I -->|No| M[3. Deploy infra<br/>RKE2 + NGINX + NFS]
 J -->|Yes| N[2. Deploy observ-infra<br/>Rancher + Keycloak]
 J -->|No| O[3. Deploy infra<br/>RKE2 + NGINX + NFS]
 K -->|Yes| P[2. Deploy observ-infra<br/>Rancher + Keycloak]
 K -->|No| Q[3. Deploy infra<br/>RKE2 + NGINX + NFS]
 
 L --> M
 N --> O
 P --> Q
 
 M --> R[MOSIP Cluster Ready]
 O --> S[MOSIP Cluster Ready]
 Q --> T[MOSIP Cluster Ready]
 
 L -.->|Optional Import| R
 N -.->|Optional Import| S
 P -.->|Optional Import| T
 
 R --> R1[4. Deploy Prerequisites + External Deps]
 S --> S1[4. Deploy Prerequisites + External Deps]
 T --> T1[4. Deploy Prerequisites + External Deps]
 
 R1 --> R2[5. Deploy MOSIP Services]
 S1 --> S2[5. Deploy MOSIP Services]
 T1 --> T2[5. Deploy MOSIP Services]
 
 R2 --> RE{Deploy eSignet Stack?}
 S2 --> SE{Deploy eSignet Stack?}
 T2 --> TE{Deploy eSignet Stack?}
 RE -->|Yes| R3[6. Deploy eSignet Stack]
 SE -->|Yes| S3[6. Deploy eSignet Stack]
 TE -->|Yes| T3[6. Deploy eSignet Stack]
 
 R3 --> RT{Deploy Test Rigs?}
 S3 --> ST{Deploy Test Rigs?}
 T3 --> TT{Deploy Test Rigs?}
 RE -->|No| RT
 SE -->|No| ST
 TE -->|No| TT
 RT -->|Yes| R4[7. Deploy Test Rigs]
 ST -->|Yes| S4[7. Deploy Test Rigs]
 TT -->|Yes| T4[7. Deploy Test Rigs]
 
 style F fill:#e1f5fe,stroke:#01579b,color:#000000
 style G fill:#e1f5fe,stroke:#01579b,color:#000000
 style H fill:#e1f5fe,stroke:#01579b,color:#000000
 style L fill:#fff3e0,stroke:#f57c00,color:#000000
 style N fill:#fff3e0,stroke:#f57c00,color:#000000
 style P fill:#fff3e0,stroke:#f57c00,color:#000000
 style M fill:#f3e5f5,stroke:#4a148c,color:#000000
 style O fill:#f3e5f5,stroke:#4a148c,color:#000000
 style Q fill:#f3e5f5,stroke:#4a148c,color:#000000
 style R3 fill:#e0f2f1,stroke:#00695c,color:#000000
 style S3 fill:#e0f2f1,stroke:#00695c,color:#000000
 style T3 fill:#e0f2f1,stroke:#00695c,color:#000000
```

## Terraform Module Structure

```mermaid
graph TB
 subgraph "Terraform Directory Structure"
 subgraph "implementations/"
 subgraph "aws/"
 AWS_BASE[base-infra/<br/>Foundation setup]
 AWS_OBS[observ-infra/<br/>Management cluster]
 AWS_INF[infra/<br/>MOSIP clusters]
 end
 subgraph "azure/"
 AZ_BASE[base-infra/<br/>Foundation setup]
 AZ_OBS[observ-infra/<br/>Management cluster]
 AZ_INF[infra/<br/>MOSIP clusters]
 end
 subgraph "gcp/"
 GCP_BASE[base-infra/<br/>Foundation setup]
 GCP_OBS[observ-infra/<br/>Management cluster]
 GCP_INF[infra/<br/>MOSIP clusters]
 end
 end
 
 subgraph "modules/"
 subgraph "AWS Modules"
 AWS_VPC[aws-resource-creation/<br/>VPC, subnets, security]
 AWS_RKE[rke2-cluster/<br/>Kubernetes setup]
 AWS_NGINX[nginx-setup/<br/>Load balancer]
 AWS_NFS[nfs-setup/<br/>Storage]
 end
 subgraph "Azure Modules"
 AZ_VNET[azure-resource-creation/<br/>VNet, NSG, security]
 AZ_RKE[rke2-cluster/<br/>Kubernetes setup]
 AZ_LB[lb-setup/<br/>Load balancer]
 AZ_STOR[storage-setup/<br/>Storage]
 end
 subgraph "GCP Modules"
 GCP_VPC_MOD[gcp-resource-creation/<br/>VPC, firewall]
 GCP_RKE[rke2-cluster/<br/>Kubernetes setup]
 GCP_LB[lb-setup/<br/>Load balancer]
 GCP_STOR[storage-setup/<br/>Storage]
 end
 end
 end
 
 AWS_BASE --> AWS_VPC
 AWS_OBS --> AWS_RKE
 AWS_INF --> AWS_RKE
 AWS_INF --> AWS_NGINX
 AWS_INF --> AWS_NFS
 
 AZ_BASE --> AZ_VNET
 AZ_OBS --> AZ_RKE
 AZ_INF --> AZ_RKE
 AZ_INF --> AZ_LB
 AZ_INF --> AZ_STOR
 
 GCP_BASE --> GCP_VPC_MOD
 GCP_OBS --> GCP_RKE
 GCP_INF --> GCP_RKE
 GCP_INF --> GCP_LB
 GCP_INF --> GCP_STOR
 
 style AWS_BASE fill:#e1f5fe,stroke:#01579b,color:#000000
 style AWS_OBS fill:#fff3e0,stroke:#f57c00,color:#000000
 style AWS_INF fill:#f3e5f5,stroke:#4a148c,color:#000000
 style AZ_BASE fill:#e1f5fe,stroke:#01579b,color:#000000
 style AZ_OBS fill:#fff3e0,stroke:#f57c00,color:#000000
 style AZ_INF fill:#f3e5f5,stroke:#4a148c,color:#000000
 style GCP_BASE fill:#e1f5fe,stroke:#01579b,color:#000000
 style GCP_OBS fill:#fff3e0,stroke:#f57c00,color:#000000
 style GCP_INF fill:#f3e5f5,stroke:#4a148c,color:#000000
```

## State File Isolation

### Branch-Based Isolation
```
State Management Structure
==========================

Production (main branch):
├── mosip-terraform-bucket-main/
│ ├── aws-base-infra-main-terraform.tfstate
│ ├── aws-observ-infra-main-terraform.tfstate
│ ├── aws-infra-main-terraform.tfstate
│ ├── azure-base-infra-main-terraform.tfstate
│ ├── azure-observ-infra-main-terraform.tfstate
│ ├── azure-infra-main-terraform.tfstate
│ ├── gcp-base-infra-main-terraform.tfstate
│ ├── gcp-observ-infra-main-terraform.tfstate
│ └── gcp-infra-main-terraform.tfstate

Staging (staging branch):
├── mosip-terraform-bucket-staging/
└── ... (same pattern for staging environment)

Development (dev branch):
├── mosip-terraform-bucket-dev/
└── ... (same pattern for dev environment)
```

### Cloud-Specific State Backends
```
AWS: S3 Bucket + DynamoDB Locking
├── Bucket: mosip-terraform-bucket-{branch}
├── Locking: DynamoDB table for state coordination
└── Versioning: Enabled for rollback capability

Azure: Storage Account + Container Isolation
├── Account: mosipterraform{branch}storage
├── Container: terraform-state-{component}
└── Versioning: Blob versioning enabled

GCP: Google Cloud Storage + Versioning
├── Bucket: mosip-terraform-bucket-{branch}
├── Objects: {cloud}-{component}-{branch}-terraform.tfstate
└── Versioning: Object versioning enabled
```

## Component Summary

| Component | Purpose | Key Resources | Cloud Services | Lifecycle |
|-----------|---------|---------------|----------------|-----------|
| **base-infra** | Foundation & VPN | VPC, Subnets, Jumpserver, WireGuard | Network, Compute, Security | One-time setup |
| **observ-infra** | Cluster Management | Rancher UI, Keycloak, RBAC | Lightweight K8s, Load Balancer | Optional, Independent |
| **infra** | MOSIP Applications | RKE2, NGINX, NFS, Databases | Full K8s, Storage, Networking | Multiple deployments |

## Architecture Benefits

- **Modular Design**: Independent component lifecycle management
- **Multi-Cloud Ready**: Full AWS implementation, Azure/GCP placeholders for community contributions
- **Security First**: Built-in VPN, encryption, and access controls
- **State Isolation**: Complete separation of environments and components
- **Centralized Management**: Optional Rancher UI for cluster oversight
- **Scalable**: Support for multiple MOSIP deployments
- **Production Ready**: Reliability and operational excellence

---

**Professional architecture designed for MOSIP deployments with modular components, state isolation, and multi-cloud support**
