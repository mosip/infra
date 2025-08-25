# MOSIP Rapid Deployment Architecture

## Complete Deployment Flow Diagram

```mermaid
graph TB
    %% Prerequisites
    A[🍴 Fork Repository] --> B[🔐 Configure Secrets]
    B --> C{Choose Deployment Path}
    
    %% Terraform Path
    C -->|Infrastructure First| D[🏗️ Terraform: Base Infrastructure]
    D --> E[📊 Terraform: Observability Infrastructure<br/><small>Optional</small>]
    E --> F[🎯 Terraform: MOSIP Infrastructure<br/><small>+ External PostgreSQL Option</small>]
    F --> G[📝 Update Terraform Variables]
    G --> H[🚀 Run Terraform via GitHub Actions<br/><small>GPG Encrypted State</small>]
    
    %% Helmsman Path
    H --> I[⚙️ Configure Helmsman DSF Files]
    I --> J[🎛️ Helmsman: Prerequisites Deployment<br/><small>Monitoring, Istio, Logging</small>]
    J --> K[🔧 Helmsman: External Dependencies<br/><small>PostgreSQL, Keycloak, MinIO, Kafka</small>]
    K --> L{PostgreSQL Type?}
    
    %% PostgreSQL Decision
    L -->|External| M[🔑 Generate PostgreSQL Secrets<br/><small>via GitHub Actions</small>]
    L -->|Container| N[🐳 Use Containerized PostgreSQL]
    M --> O[🎯 Helmsman: MOSIP Services]
    N --> O
    
    %% Final Steps
    O --> P[🧪 Helmsman: Test Rigs<br/><small>Optional</small>]
    P --> Q[✅ Verify Deployment]
    Q --> R[🎉 Complete MOSIP Platform]
    
    %% Styling
    classDef terraform fill:#e3f2fd,stroke:#1976d2,stroke-width:2px
    classDef helmsman fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
    classDef actions fill:#fff3e0,stroke:#f57c00,stroke-width:2px
    classDef success fill:#e8f5e8,stroke:#388e3c,stroke-width:2px
    classDef decision fill:#fce4ec,stroke:#c2185b,stroke-width:2px
    
    class D,E,F,G,H terraform
    class I,J,K,O,P helmsman
    class M actions
    class R success
    class C,L decision
```

## Architecture Components

### 🏗️ Infrastructure Layer (Terraform)

```mermaid
graph LR
    subgraph "Cloud Provider"
        subgraph "Base Infrastructure"
            VPC[VPC/Virtual Network]
            NET[Subnets & Networking]
            SEC[Security Groups/NSGs]
            IGW[Internet Gateway]
        end
        
        subgraph "Observability Cluster (Optional)"
            RKE2_OBS[RKE2 Cluster]
            RANCHER[Rancher Management]
            MON[Monitoring Stack]
        end
        
        subgraph "MOSIP Cluster"
            RKE2_MOSIP[RKE2 Cluster]
            NODES[Worker Nodes]
            LB[Load Balancer]
        end
        
        subgraph "External PostgreSQL (Optional)"
            RDS[🆕 RDS/Azure DB/Cloud SQL]
            BACKUP[Automated Backups]
            ENCRYPT[🔒 Encryption at Rest]
        end
    end
    
    subgraph "State Management"
        GPG[🆕 GPG Encrypted State]
        BACKEND[Local Backend]
    end
    
    VPC --> NET
    NET --> SEC
    SEC --> IGW
    IGW --> RKE2_OBS
    IGW --> RKE2_MOSIP
    VPC --> RDS
    
    classDef new fill:#fff3e0,stroke:#f57c00,stroke-width:2px
    class RDS,ENCRYPT,GPG new
```

### 🎛️ Application Layer (Helmsman)

```mermaid
graph TD
    subgraph "Prerequisites DSF"
        ISTIO[Service Mesh - Istio]
        MON[Monitoring - Prometheus/Grafana]
        LOG[Logging - ELK Stack]
        ALERT[AlertManager]
    end
    
    subgraph "External Dependencies DSF"
        POSTGRES{PostgreSQL Options}
        POSTGRES -->|Container| PG_HELM[PostgreSQL Helm Chart]
        POSTGRES -->|External| PG_EXT[🆕 External Database Connection]
        
        KEYCLOAK[Keycloak - IAM]
        MINIO[MinIO - Object Storage]
        KAFKA[Kafka - Message Queue]
        ACTIVEMQ[ActiveMQ - Message Queue]
        SOFTHSM[SoftHSM - Security]
    end
    
    subgraph "MOSIP Core DSF"
        KERNEL[Kernel Services]
        IDA[Identity & Authentication]
        REGPROC[Registration Processor]
        REGCLIENT[Registration Client]
        RESIDENT[Resident Services]
        PARTNER[Partner Management]
    end
    
    subgraph "Test Rigs DSF"
        API_TEST[API Test Rig]
        DSL_TEST[DSL Test Rig]
        UI_TEST[UI Test Rig]
        PACKET[Packet Creator]
    end
    
    classDef new fill:#fff3e0,stroke:#f57c00,stroke-width:2px
    class PG_EXT new
```

### 🤖 Automation Layer (GitHub Actions)

```mermaid
graph TB
    subgraph "Infrastructure Workflows"
        TF_PLAN[terraform plan/apply]
        TF_DESTROY[terraform destroy]
        GPG_ENCRYPT[🆕 GPG State Encryption]
    end
    
    subgraph "Application Workflows"
        HELM_PREREQ[helmsman prereq]
        HELM_EXT[helmsman external]
        HELM_MOSIP[helmsman mosip]
        HELM_TEST[helmsman testrigs]
    end
    
    subgraph "🆕 Security Workflows"
        PG_SECRETS[PostgreSQL Secret Generation]
        WG_SETUP[WireGuard VPN Setup]
        KUBECTL_SETUP[kubectl & kubeconfig Setup]
    end
    
    subgraph "Triggers"
        MANUAL[workflow_dispatch]
        BRANCH[Branch-based Environments]
        SCHEDULE[Scheduled Runs]
    end
    
    TF_PLAN --> GPG_ENCRYPT
    GPG_ENCRYPT --> HELM_PREREQ
    HELM_EXT --> PG_SECRETS
    PG_SECRETS --> HELM_MOSIP
    
    classDef new fill:#fff3e0,stroke:#f57c00,stroke-width:2px
    class GPG_ENCRYPT,PG_SECRETS,WG_SETUP,KUBECTL_SETUP new
```

## 🔐 Security Architecture

### GPG Encryption Flow
```mermaid
sequenceDiagram
    participant GA as GitHub Actions
    participant GPG as GPG System
    participant STATE as Terraform State
    participant CLOUD as Cloud Storage
    
    GA->>GPG: Load GPG Private Key
    GA->>GPG: Decrypt existing state (if exists)
    GA->>STATE: Run Terraform operations
    STATE->>GPG: Encrypt new state
    GPG->>CLOUD: Store encrypted state
    GA->>GA: Clean up sensitive data
```

### PostgreSQL Secret Management
```mermaid
sequenceDiagram
    participant GA as GitHub Actions
    participant WG as WireGuard
    participant K8S as Kubernetes
    participant PG as PostgreSQL
    
    GA->>GA: Check deployment type
    GA->>WG: Setup VPN connection
    GA->>K8S: Validate cluster access
    GA->>K8S: Generate PostgreSQL secrets
    K8S->>PG: Apply database credentials
    GA->>GA: Cleanup sensitive files
```

## 📊 Deployment Options Matrix

| Component | Containerized | External/Managed | Hybrid |
|-----------|--------------|------------------|---------|
| **PostgreSQL** | ✅ Helm Chart | 🆕 RDS/Azure DB/Cloud SQL | ⚡ Both Options |
| **Monitoring** | ✅ Prometheus/Grafana | ☁️ Cloud Provider Native | 🔄 Integrated |
| **Storage** | ✅ MinIO | ☁️ S3/Blob/GCS | 🔄 Multi-tier |
| **Load Balancer** | ✅ Nginx/Traefik | ☁️ ALB/Azure LB/GCP LB | ⚖️ Hybrid |

## 🌐 Multi-Cloud Support

### Current Support
- ✅ **AWS** - Complete implementation
- ✅ **Azure** - Complete implementation  
- ✅ **GCP** - Complete implementation

### Community Contributions Welcome
- 🚧 **Oracle Cloud** - Placeholder available
- 🚧 **IBM Cloud** - Placeholder available
- 🚧 **DigitalOcean** - Placeholder available
- 🚧 **Linode** - Placeholder available

## 🔄 Environment Isolation

```mermaid
graph LR
    subgraph "Branch Strategy"
        MAIN[main - Production]
        DEV[develop - Development]  
        FEAT[feature/* - Feature Testing]
        ENV[environment/* - Environment Specific]
    end
    
    subgraph "Automated Isolation"
        MAIN --> PROD_ENV[Production Environment]
        DEV --> DEV_ENV[Development Environment]
        FEAT --> TEST_ENV[Feature Test Environment]
        ENV --> CUSTOM_ENV[Custom Environment]
    end
    
    subgraph "Resource Separation"
        PROD_ENV --> PROD_RES[Dedicated Resources]
        DEV_ENV --> DEV_RES[Shared Resources]
        TEST_ENV --> TEMP_RES[Temporary Resources]
    end
```

## 📈 Scalability & Performance

### Infrastructure Scaling
- **Horizontal Pod Autoscaling (HPA)** for MOSIP services
- **Cluster Autoscaling** for Kubernetes nodes  
- **Database scaling** via external managed services
- **Load balancing** with cloud-native solutions

### Performance Optimization
- **Resource requests and limits** properly configured
- **Persistent volume** optimization for databases
- **Network policies** for secure communication
- **Monitoring and alerting** for proactive scaling

---

*This architecture supports rapid deployment while maintaining enterprise-grade security, scalability, and reliability.*
