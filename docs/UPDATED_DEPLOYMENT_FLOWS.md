# MOSIP Infrastructure Deployment Flows - Updated Architecture

## Complete Infrastructure & Application Deployment Flow

```mermaid
graph TD
    A[Repository Setup] --> B[Configure GitHub Secrets]
    B --> C[Terraform: Base Infrastructure]
    C --> D{Deploy Observability?}
    D -->|Yes| E[Terraform: Observability Infrastructure]
    D -->|No| F[Terraform: MOSIP Infrastructure]
    E --> F[Terraform: MOSIP Infrastructure]
    
    F --> G[Configure Terraform Variables]
    G --> H{enable_postgresql_setup?}
    
    H -->|true| I[Terraform Auto-deploys External PostgreSQL]
    H -->|false| J[Configure Container PostgreSQL in Helmsman]
    
    I --> K[Run Terraform Infrastructure Workflow]
    J --> K[Run Terraform Infrastructure Workflow]
    
    K --> L[Update Helmsman DSF Configuration]
    L --> M[Deploy Prerequisites via Helmsman]
    M --> N[Deploy External Dependencies via Helmsman]
    N --> O[Deploy MOSIP Core Services via Helmsman]
    O --> P{Deploy Test Rigs?}
    P -->|Yes| Q[Deploy Test Rigs via Helmsman]
    P -->|No| R[MOSIP Platform Ready]
    Q --> R[MOSIP Platform Ready]
```

## PostgreSQL Deployment Decision Flow

```mermaid
graph TD
    A[Configure PostgreSQL in Terraform] --> B{Production or Development?}
    
    B -->|Production| C[Set enable_postgresql_setup = true]
    B -->|Development/Testing| D[Set enable_postgresql_setup = false]
    
    C --> E[Configure EBS Volume Size]
    E --> F[Set PostgreSQL Version & Port]
    F --> G[Run Terraform Workflow]
    G --> H[Terraform Provisions Infrastructure]
    H --> I[Ansible Installs & Configures PostgreSQL 15]
    I --> J[PostgreSQL Ready on External Node]
    J --> K[Update external-dsf.yaml: postgresql.enabled = false]
    K --> L[Deploy MOSIP Services]
    
    D --> M[Update external-dsf.yaml: postgresql.enabled = true]
    M --> N[Deploy Container PostgreSQL via Helmsman]
    N --> O[PostgreSQL Ready in Kubernetes]
    O --> L[Deploy MOSIP Services]
```

## Terraform Infrastructure Provisioning Flow

```mermaid
graph TD
    A[GitHub Actions Trigger] --> B[Environment Setup]
    B --> C[Configure Backend & State Management]
    C --> D[Pre-Operation Cleanup]
    D --> E[Decrypt Existing State Files]
    E --> F[VPN & Network Setup]
    F --> G[Terraform Operations]
    
    G --> H[Terraform Init & Validate]
    H --> I[Terraform Plan]
    I --> J[Terraform Apply]
    
    J --> K{enable_postgresql_setup?}
    K -->|true| L[Provision PostgreSQL EBS Volume]
    K -->|false| M[Skip PostgreSQL Infrastructure]
    
    L --> N[Create PostgreSQL Node]
    N --> O[Execute Ansible PostgreSQL Setup]
    O --> P[Configure PostgreSQL 15]
    P --> Q[Setup PostgreSQL Security]
    Q --> R[PostgreSQL Ready]
    
    M --> S[Infrastructure Complete]
    R --> S[Infrastructure Complete]
    
    S --> T[Encrypt & Commit State Files]
    T --> U[Infrastructure Ready for Helmsman]
```

## Helmsman Application Deployment Flow

```mermaid
graph TD
    A[Infrastructure Ready] --> B[Configure DSF Files]
    
    B --> C[Phase 1: Parallel Prerequisites & External Dependencies]
    C --> D[Deploy Monitoring Stack]
    C --> E[Deploy PostgreSQL Decision]
    
    D --> F[Deploy Istio Service Mesh] 
    E --> I{PostgreSQL Configuration}
    
    F --> G[Deploy Logging Infrastructure]
    I -->|External via Terraform| J[Skip PostgreSQL Container]
    I -->|Container via Helmsman| K[Deploy PostgreSQL Container]
    
    G --> H[Prerequisites Complete]
    J --> L[Deploy MinIO Object Storage]
    K --> L[Deploy MinIO Object Storage]
    
    H --> M[Wait for External Dependencies]
    L --> N[Deploy Keycloak Identity Management]
    N --> O[Deploy Kafka Message Queue]
    O --> P[Deploy ActiveMQ]
    P --> Q[Deploy Supporting Services]
    Q --> R[External Dependencies Complete]
    
    M --> S[Phase 2: MOSIP Core Services]
    R --> S[Phase 2: MOSIP Core Services]
    S --> T[Deploy Config Server]
    T --> U[Deploy Artifactory]
    U --> V[Deploy Kernel Services]
    V --> W[Deploy Identity Services]
    W --> X[Deploy Authentication Services]
    X --> Y[Deploy Registration Services]
    Y --> Z[MOSIP Core Complete]
    
    Z --> AA{Deploy Test Rigs?}
    AA -->|Yes| BB[Deploy API Test Rig]
    AA -->|No| CC[Deployment Complete]
    BB --> DD[Deploy DSL Test Rig]
    DD --> EE[Deploy UI Test Rig]
    EE --> CC[Deployment Complete]
```

## State Management & Security Flow

```mermaid
graph TD
    A[Terraform Workflow Start] --> B[Pre-Operation Cleanup]
    B --> C{Local or Remote Backend?}
    
    C -->|Local| D[Check for Encrypted State Files]
    C -->|Remote| E[Configure Cloud Storage Backend]
    
    D --> F{Encrypted State Files Found?}
    F -->|Yes| G[Decrypt with GPG]
    F -->|No| H[Fresh Deployment]
    
    G --> I[Custom State File Names Preserved]
    I --> J[aws-infra-testgrid-terraform.tfstate]
    
    E --> K[S3/Azure/GCS Backend Configuration]
    K --> L[State Locking Setup]
    
    H --> M[Generate Backend Configuration]
    J --> M[Generate Backend Configuration]
    L --> M[Generate Backend Configuration]
    
    M --> N[Terraform Operations]
    N --> O[Post-Operation State Management]
    
    O --> P{Local Backend?}
    P -->|Yes| Q[Encrypt State with Custom Names]
    P -->|No| R[State Managed in Cloud]
    
    Q --> S[Commit Encrypted Files Only]
    R --> T[No Local State Files]
    S --> U[Deployment Complete]
    T --> U[Deployment Complete]
```

## Multi-Cloud Infrastructure Pattern

```mermaid
graph TD
    A[Cloud-Agnostic Configuration] --> B{Select Cloud Provider}
    
    B -->|AWS| C[AWS Terraform Modules<br/>Complete Implementation]
    B -->|Azure| D[Azure Terraform Modules<br/>Placeholder - Community Contributions Welcome]
    B -->|GCP| E[GCP Terraform Modules<br/>Placeholder - Community Contributions Welcome]
    
    C --> F[AWS-Specific Infrastructure]
    D --> G[Azure-Specific Infrastructure<br/>TODO: Implementation Needed]  
    E --> H[GCP-Specific Infrastructure<br/>TODO: Implementation Needed]
    
    F --> I[AWS EBS for PostgreSQL Storage]
    G --> J[Azure Disk for PostgreSQL Storage<br/>Placeholder]
    H --> K[GCP Persistent Disk for PostgreSQL Storage<br/>Placeholder]
    
    I --> L[Unified PostgreSQL Module]
    J --> L[Unified PostgreSQL Module]
    K --> L[Unified PostgreSQL Module]
    
    L --> M[Cloud-Agnostic Ansible Configuration]
    M --> N[PostgreSQL 15 Installation]
    N --> O[Standard PostgreSQL Configuration]
    O --> P[Ready for MOSIP Services]
```

## Component Integration Matrix

```mermaid
graph TD
    A[MOSIP Platform] --> B[Infrastructure Layer]
    A --> C[Application Layer]
    A --> D[Data Layer]
    
    B --> E[Terraform Modules]
    E --> F[AWS/Azure/GCP Resources]
    E --> G[Kubernetes Clusters]
    E --> H[Networking & Security]
    
    C --> I[Helmsman DSF]
    I --> J[Prerequisites]
    I --> K[External Dependencies]
    I --> L[MOSIP Core Services]
    
    D --> M{PostgreSQL Deployment}
    M -->|External| N[Terraform + Ansible PostgreSQL]
    M -->|Container| O[Kubernetes PostgreSQL]
    
    N --> P[Dedicated Storage]
    N --> Q[Production Configuration]
    O --> R[Container Storage]
    O --> S[Development Configuration]
    
    F --> T[Platform Foundation]
    G --> T[Platform Foundation]
    H --> T[Platform Foundation]
    J --> U[Service Dependencies]
    K --> U[Service Dependencies]
    P --> U[Service Dependencies]
    R --> U[Service Dependencies]
    L --> V[MOSIP Application]
    T --> V[MOSIP Application]
    U --> V[MOSIP Application]
```

## Deployment Timeline & Dependencies

| Phase | Component | Dependencies | Duration | PostgreSQL Impact | **Parallel** |
|-------|-----------|--------------|----------|-------------------|--------------|
| 1 | Base Infrastructure | Cloud Credentials | 5-10 min | N/A | No |
| 2 | Observability (Optional) | Base Infrastructure | 10-15 min | N/A | No |
| 3 | MOSIP Infrastructure | Base/Observ Infrastructure | 15-25 min | PostgreSQL installed if enabled | No |
| 4a | Prerequisites | MOSIP Infrastructure | 10-15 min | N/A | **Yes** |
| 4b | External Dependencies | MOSIP Infrastructure | 15-20 min | Container PostgreSQL if not external | **Yes** |
| 5 | MOSIP Core Services | Prerequisites + External Dependencies | 20-30 min | Uses configured PostgreSQL | No |
| 6 | Test Rigs (Optional) | MOSIP Core | 10-15 min | N/A | No |

**Total Deployment Time**: 
- **Sequential**: 85-130 minutes 
- **With Parallel Prerequisites/External**: 70-110 minutes (**~20% faster!**)

## Key Benefits of Updated Architecture

### **Simplified PostgreSQL Management**
- **No separate workflow** for PostgreSQL secrets
- **Terraform handles everything** - infrastructure + configuration
- **Ansible ensures consistency** across environments
- **Simple enable/disable flag** in Terraform variables

### **Enhanced Security & State Management**
- **GPG encryption** for local state files
- **Custom state file naming** preserved through encryption
- **Modern Terraform backend** configuration
- **No deprecated command-line flags**

### **Streamlined Deployment Flow**
- **Fewer manual steps** required
- **Automated dependency resolution**
- **Better error recovery** mechanisms
- **Consistent multi-cloud approach**

---

*This document reflects the updated architecture with integrated PostgreSQL management and enhanced security features.*
