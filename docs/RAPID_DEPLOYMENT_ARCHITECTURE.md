# MOSIP Rapid Deployment Architecture - Updated

## Complete Deployment Flow Diagram (Updated)

```mermaid
graph TB
    %% Prerequisites
    A[Fork Repository] --> B[Configure Secrets]
    B --> C[Select Cloud Provider<br/>AWS/Azure/GCP]
    
    %% Infrastructure Phase
    C --> D[Terraform: Base Infrastructure<br/>VPC, Networking, Jumpserver, WireGuard]
    D --> E{Deploy Observability?}
    E -->|Yes| F[Terraform: Observability Infrastructure<br/>Rancher UI, Keycloak, Monitoring]
    E -->|No| G[Configure PostgreSQL Setup]
    F --> G[Configure PostgreSQL Setup]
    
    %% PostgreSQL Configuration
    G --> H{PostgreSQL Deployment Choice}
    H -->|Production| I[Set enable_postgresql_setup = true<br/>External PostgreSQL via Terraform]
    H -->|Development| J[Set enable_postgresql_setup = false<br/>Container PostgreSQL via Helmsman]
    
    %% Terraform Infrastructure Deployment
    I --> K[Terraform: MOSIP Infrastructure<br/>+ Auto PostgreSQL Setup via Ansible]
    J --> L[Terraform: MOSIP Infrastructure<br/>Kubernetes Cluster Only]
    K --> M[Run Terraform via GitHub Actions<br/>GPG Encrypted State Management]
    L --> M
    
    %% Helmsman Configuration
    M --> N{PostgreSQL Setup Complete?}
    N -->|External PostgreSQL| O[Configure Helmsman DSF Files<br/>postgresql.enabled = false]
    N -->|Container PostgreSQL| P[Configure Helmsman DSF Files<br/>postgresql.enabled = true]
    
    %% Helmsman Deployment Phase
    O --> Q[Helmsman: Prerequisites<br/>Monitoring, Istio, Logging]
    P --> Q
    Q --> R[Helmsman: External Dependencies<br/>PostgreSQL containers, Keycloak, MinIO, Kafka]
    
    %% MOSIP Services
    R --> S[Helmsman: MOSIP Core Services<br/>Registration, Authentication, ID Repository]
    S --> T{Deploy Test Rigs?}
    T -->|Yes| U[Helmsman: Test Rigs<br/>API Testing, UI Testing, DSL Testing]
    T -->|No| V[Verify Deployment]
    U --> V
    
    %% Final Verification
    V --> W[Access MOSIP Platform<br/>Web UI, APIs, Admin Console]
    W --> X[Complete MOSIP Platform<br/>Ready for Production]
    
    %% Styling
    classDef prereq fill:#fff3e0,stroke:#ff8f00,stroke-width:2px
    classDef terraform fill:#e3f2fd,stroke:#1976d2,stroke-width:2px
    classDef helmsman fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
    classDef postgres fill:#c8e6c9,stroke:#2e7d32,stroke-width:2px
    classDef success fill:#e8f5e8,stroke:#388e3c,stroke-width:2px
    classDef decision fill:#fce4ec,stroke:#c2185b,stroke-width:2px
    classDef config fill:#f1f8e9,stroke:#689f38,stroke-width:2px
    
    class A,B,C prereq
    class D,F,I,J,K,L,M terraform
    class O,P,Q,R,S,U helmsman
    class G,H,N postgres
    class V,W,X success
    class E,H,N,T decision
    class G,O,P config
```

## Architecture Components

### Infrastructure Layer (Terraform)

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
            RDS[RDS/Azure DB/Cloud SQL]
            BACKUP[Automated Backups]
            ENCRYPT[Encryption at Rest]
        end
    end
    
    subgraph "State Management"
        GPG[GPG Encrypted State]
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

### Application Layer (Helmsman)

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
        POSTGRES -->|External| PG_EXT[External Database Connection]
        
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

### Automation Layer (GitHub Actions)

```mermaid
graph TB
    subgraph "Infrastructure Workflows"
        TF_PLAN[terraform plan/apply]
        TF_DESTROY[terraform destroy]
        GPG_ENCRYPT[GPG State Encryption]
    end
    
    subgraph "Application Workflows"
        HELM_PREREQ[helmsman prereq]
        HELM_EXT[helmsman external]
        HELM_MOSIP[helmsman mosip]
        HELM_TEST[helmsman testrigs]
    end
    
    subgraph "Security Workflows"
        GPG_ENCRYPT_ONLY[GPG State Encryption]
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
    HELM_EXT --> HELM_MOSIP
    
    classDef new fill:#fff3e0,stroke:#f57c00,stroke-width:2px
    class GPG_ENCRYPT,GPG_ENCRYPT_ONLY,WG_SETUP,KUBECTL_SETUP new
```

## Security Architecture

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

### PostgreSQL Integration (Updated Approach)
```mermaid
sequenceDiagram
    participant TF as Terraform
    participant ANS as Ansible
    participant NODE as PostgreSQL Node
    participant HELM as Helmsman
    
    TF->>TF: Check enable_postgresql_setup
    alt enable_postgresql_setup = true
        TF->>NODE: Provision EBS volume & PostgreSQL node
        TF->>ANS: Execute PostgreSQL setup script
        ANS->>NODE: Install PostgreSQL 15
        ANS->>NODE: Configure security & networking
        ANS->>NODE: Setup data directories
        NODE->>TF: PostgreSQL ready (no secrets needed)
    else enable_postgresql_setup = false
        TF->>HELM: Skip PostgreSQL infrastructure
        HELM->>HELM: Deploy PostgreSQL container
    end
    TF->>HELM: Infrastructure ready
    HELM->>HELM: Deploy MOSIP services with PostgreSQL
```

## Deployment Options Matrix (Updated)

| Component | Containerized | External/Managed | Configuration |
|-----------|--------------|------------------|---------------|
| **PostgreSQL** | Kubernetes Container | Terraform + Ansible Auto-setup | `enable_postgresql_setup = false/true` |
| **Monitoring** | Prometheus/Grafana | Cloud Provider Native | Via Helmsman DSF |
| **Storage** | MinIO | S3/Blob/GCS | Via Helmsman DSF |
| **Load Balancer** | Nginx/Traefik | ALB/Azure LB/GCP LB | Via Terraform |

### PostgreSQL Configuration Summary

| Approach | Use Case | Configuration | Secrets Management |
|----------|----------|---------------|-------------------|
| **External PostgreSQL** | Production, Staging | `enable_postgresql_setup = true` | **Handled by Ansible** |
| **Container PostgreSQL** | Development, Testing | `enable_postgresql_setup = false` | **Handled by Kubernetes** |

## Multi-Cloud Support

### Current Support
- **AWS** - Complete implementation
- **Azure** - Complete implementation  
- **GCP** - Complete implementation

### Community Contributions Welcome
- **Oracle Cloud** - Placeholder available
- **IBM Cloud** - Placeholder available
- **DigitalOcean** - Placeholder available
- **Linode** - Placeholder available

## Environment Isolation

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

## Scalability & Performance

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
