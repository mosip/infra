# MOSIP Rapid Deployment

![MOSIP Infrastructure](docs/_images/mosip-cloud-agnostic-banner.png)

> **Complete MOSIP platform rapid deployment with infrastructure provisioning, dependency setup, and service deployment**

This repository provides a **3-step rapid deployment model** for MOSIP (Modular Open Source Identity Platform) with enhanced security features including GPG encryption for local backends and integrated PostgreSQL setup via Terraform modules.

## Complete Deployment Flow

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

> **Note:** Complete Terraform scripts are available only for **AWS**. For **Azure and GCP**, only placeholder structures are configured - community contributions are welcome to implement full functionality.

## Prerequisites

### Required Cloud Provider Account

- **AWS account** with appropriate permissions (fully supported)
- Azure or GCP account (placeholder implementations - community contributions needed)
- Service account/access keys with infrastructure creation rights

### Required Secrets for Rapid Deployment

> **Secret Configuration Types:**
> - **Repository Secrets**: Global secrets shared across all environments (set once in GitHub repo settings)
> - **Environment Secrets**: Environment-specific secrets (configured per deployment environment)

#### Terraform Secrets

**Repository Secrets** (configured in GitHub repository settings):
```yaml
# GPG Encryption (for local backend)
GPG_PASSPHRASE: "your-gpg-passphrase"  # Required for GPG encryption

# Cloud Provider Credentials
AWS_ACCESS_KEY_ID: "AKIA..."           # AWS Access Key ID
AWS_SECRET_ACCESS_KEY: "..."           # AWS Secret Access Key
```

**Environment Secrets** (configured per deployment environment):
```yaml
# WireGuard VPN (optional - for infrastructure access)
TF_WG_CONFIG: |
  [Interface]
  PrivateKey = terraform-private-key
  Address = 10.0.1.2/24
  
  [Peer]
  PublicKey = server-public-key
  Endpoint = your-server:51820
  AllowedIPs = 10.0.0.0/16

# Notifications (optional)
SLACK_WEBHOOK_URL: "https://hooks.slack.com/services/..."  # Slack notifications
GITHUB_TOKEN: "ghp_..."                                    # GitHub token for API access
```

#### Helmsman Secrets

**Environment Secrets** (configured per deployment environment):
```yaml
# Kubernetes Access
KUBECONFIG: "apiVersion: v1..."  # Complete kubeconfig file content

# WireGuard VPN Access (for cluster access)
CLUSTER_WIREGUARD_WG0: |
  [Interface]
  PrivateKey = helmsman-wg0-private-key
  Address = 10.0.0.2/24
  
  [Peer]
  PublicKey = cluster-public-key
  Endpoint = cluster-server:51820
  AllowedIPs = 10.0.0.0/16

# Secondary WireGuard Config (optional)
CLUSTER_WIREGUARD_WG1: |
  [Interface]
  PrivateKey = helmsman-wg1-private-key
  Address = 10.0.2.2/24
  
  [Peer]
  PublicKey = cluster-public-key-2
  Endpoint = cluster-server-2:51820
  AllowedIPs = 10.0.0.0/16
```

> **Note**: PostgreSQL secrets are no longer required! PostgreSQL setup is handled automatically by Terraform modules and Ansible scripts based on your `enable_postgresql_setup` configuration.

## Quick Start Guide

### 1. Fork and Setup Repository

```bash
# Fork the repository to your GitHub account
# Clone your fork
git clone https://github.com/YOUR_USERNAME/infra.git
cd infra
```

### 2. Configure GitHub Secrets

Navigate to your repository → **Settings** → **Secrets and variables** → **Actions**

**Configure Repository & Environment Secrets:**

Add the required secrets as follows:
- **Repository Secrets** (Settings > Secrets and variables > Actions > Repository secrets):
  - `GPG_PASSPHRASE`
  - `AWS_ACCESS_KEY_ID` 
  - `AWS_SECRET_ACCESS_KEY`

- **Environment Secrets** (Settings > Secrets and variables > Actions > Environment secrets):
  - All other secrets mentioned in the Prerequisites section above (KUBECONFIG, WireGuard configs, etc.)

### 3. Terraform Infrastructure Deployment

#### Step 3a: Base Infrastructure

1. **Update terraform variables:**

   ```bash
   # Edit terraform/base-infra/aws/terraform.tfvars (or azure/gcp)
   ```
2. **Configure base-infra variables:**

   ```hcl
   # Example for AWS
   region = "us-west-2"
   availability_zones = ["us-west-2a", "us-west-2b"]
   vpc_cidr = "10.0.0.0/16"
   environment = "production"
   ```
3. **Run base-infra via GitHub Actions:**

   - Go to **Actions** → **Terraform Base Infrastructure**
   - Click **Run workflow**
   - Select your branch and cloud provider
   - Choose action: `apply`

#### Step 3b: Observability Infrastructure (Optional)

1. **Update observ-infra variables:**

   ```hcl
   # terraform/observ-infra/aws/terraform.tfvars
   cluster_name = "mosip-observability"
   node_instance_type = "t3.large"
   min_nodes = 1
   max_nodes = 3
   ```
2. **Run observ-infra via GitHub Actions:**

   - Actions → **Terraform Observability Infrastructure**
   - Select cloud provider and run `apply`

#### Step 3c: MOSIP Infrastructure

1. **Update infra variables:**

   ```hcl
   # terraform/implementations/aws/infra/aws.tfvars
   cluster_name = "mosip-cluster"
   node_instance_type = "t3.xlarge"
   min_nodes = 3
   max_nodes = 10

   # PostgreSQL Configuration
   enable_postgresql_setup = true    # true = External PostgreSQL, false = Container PostgreSQL
   nginx_node_ebs_volume_size_2 = 200  # EBS volume size for PostgreSQL data (required if enable_postgresql_setup = true)
   postgresql_version = "15"         # PostgreSQL version
   postgresql_port = "5433"          # PostgreSQL port
   ```
2. **Run main infra via GitHub Actions:**

   - Actions → **Terraform Infrastructure**
   - Select cloud provider and run `apply`
   - If `enable_postgresql_setup = true`, Terraform will automatically:
     - Provision dedicated EBS volume for PostgreSQL
     - Install and configure PostgreSQL 15 via Ansible
     - Setup security and backup configurations
     - Make PostgreSQL ready for MOSIP services

### 4. Helmsman Deployment

#### Step 4a: Update DSF Configuration Files

```bash
cd Helmsman/dsf/
```

1. **Update prereq-dsf.yaml:**

   ```yaml
   # Configure monitoring, Istio, logging
   helmRepos:
     rancher-latest: "https://releases.rancher.com/server-charts/latest"

   apps:
     rancher-monitoring:
       enabled: true
       namespace: cattle-monitoring-system
   ```
2. **Update external-dsf.yaml:**

   ```yaml
   # Configure external dependencies
   apps:
     postgresql:
       # Set based on your Terraform configuration:
       enabled: false  # false if enable_postgresql_setup = true (external PostgreSQL via Terraform)
                      # true if enable_postgresql_setup = false (container PostgreSQL)
     minio:
       enabled: true
     kafka:
       enabled: true
   ```
3. **Update mosip-dsf.yaml:**

   ```yaml
   # Configure MOSIP services  
   apps:
     config-server:
       enabled: true
     artifactory:
       enabled: true
     kernel:
       enabled: true
   ```

#### Step 4b: Run Helmsman Deployments via GitHub Actions

1. **Deploy Prerequisites & External Dependencies (Parallel Deployment):**
   
   **Option A: Run Both Workflows Simultaneously (Recommended)**
   - Actions → **Helmsman External Dependencies** 
   - Select DSF file: `prereq-dsf.yaml`
   - Mode: `apply`
   
   **At the same time (in parallel):**
   - Actions → **Helmsman External Dependencies**
   - Select DSF file: `external-dsf.yaml` 
   - Mode: `apply`
   
   **Option B: Sequential Deployment (if preferred)**
   - First run: `prereq-dsf.yaml` → Mode: `apply`
   - Then run: `external-dsf.yaml` → Mode: `apply`

2. **Deploy MOSIP Services:**
   - Actions → **Helmsman Deployment**
   - Select DSF file: `mosip-dsf.yaml`
   - Mode: `apply`

3. **Deploy Test Rigs** (Optional):
   - Actions → **Helmsman Deployment**  
   - Select DSF file: `testrigs-dsf.yaml`
   - Mode: `apply`

### 5. Verify Deployment

```bash
# Check cluster status
kubectl get nodes
kubectl get namespaces

# Check MOSIP services
kubectl get pods -n mosip
kubectl get services -n istio-system
```

## Rapid Deployment Model

### Step 1: Infrastructure Creation (Terraform)

**Create cloud infrastructure using Terraform with enhanced security**

**New Features:**

- **GPG Encryption** for local Terraform state backend
- **Optional External PostgreSQL** support in infrastructure components
- **Enhanced State Management** with encryption

**Infrastructure Components:**

1. **base-infra** - Foundation infrastructure (VPC, networking, security)
2. **observ-infra** - Management cluster with Rancher UI (Optional)
3. **infra** - MOSIP application clusters with optional external PostgreSQL

**GitHub Actions Integration:**

- Automated infrastructure provisioning with GPG encrypted state
- Branch-based environment isolation
- Optional Rancher cluster import automation
- **AWS fully supported** - Azure and GCP placeholder implementations (community contributions welcome)

**[Complete Terraform Documentation](terraform/README.md)**

---

### Step 2: External Dependencies & Monitoring (Helmsman)

**Deploy prerequisites and external dependencies using Helmsman**

**Deployment Sequence (Parallel Deployment Supported):**

1. **prereq-dsf** - Deploy prerequisites (monitoring, Istio, logging)
2. **external-dsf** - Deploy external dependencies (databases, message queues, storage)

> **Performance Tip**: prereq-dsf and external-dsf can be deployed **in parallel** since they don't have dependencies on each other. This reduces total deployment time by ~40%.

**What gets deployed:**

**Prerequisites (prereq-dsf):**

- **Monitoring stack** (Rancher monitoring, Grafana, AlertManager)
- **Logging infrastructure** (Cattle logging system)
- **Service mesh** (Istio) and networking components

**External Dependencies (external-dsf):**

- **Databases** (PostgreSQL with initialization or external connection)
- **Identity & Access** (Keycloak)
- **Security** (SoftHSM, ClamAV antivirus)
- **Object Storage** (MinIO)
- **Message Queues** (ActiveMQ, Kafka with UI)
- **Supporting services** (S3, message gateways, CAPTCHA, landing page)

**[Complete Helmsman Documentation](Helmsman/README.md)**

---

### Step 3: MOSIP Core Services & Testing (Helmsman + GitHub Actions)

**Deploy MOSIP core services and testing infrastructure**

**MOSIP Core Deployment:**

1. **mosip-dsf** - Deploy MOSIP core services (Identity, Authentication, etc.)

**PostgreSQL Integration:**

- **External PostgreSQL**: Automatically configured by Terraform modules (no manual secret management required)
- **Container PostgreSQL**: Deployed via Helmsman external-dsf configuration

**Testing Infrastructure (GitHub Actions):**

- **testrigs-dsf** - Automated deployment of testing suite:
  - **API Test Rig** - API testing automation
  - **DSL Test Rig** - Domain-specific language testing
  - **UI Test Rig** - User interface testing automation

**[Helmsman DSF Documentation](Helmsman/dsf/README.md)**

---

## GitHub Actions Automation

### Infrastructure Automation

- **terraform.yml** - Automated infrastructure provisioning
- **terraform-destroy.yml** - Infrastructure cleanup automation

### Application Deployment Automation

- **helmsman_external.yml** - External dependencies deployment
- **helmsman_mosip.yml** - MOSIP core services deployment
- **helmsman_testrigs.yml** - Testing infrastructure deployment

**[GitHub Actions Documentation](.github/workflows/README.md)**

---

## Architecture Overview

### Infrastructure Layer (Terraform)

```
terraform/
├── base-infra/          # Foundation infrastructure (VPC, networking, security)
├── observ-infra/        # Management cluster with Rancher UI (Optional)
├── infra/               # MOSIP Kubernetes clusters
├── modules/             # Reusable Terraform modules
│   ├── aws/             # AWS-specific modules
│   ├── azure/           # Azure-specific modules
│   └── gcp/             # GCP-specific modules
└── implementations/     # Cloud-specific implementations
    ├── aws/             # AWS deployment configurations
    ├── azure/           # Azure deployment configurations
    └── gcp/             # GCP deployment configurations
```

### Application Layer (Helmsman)

```
Helmsman/
├── dsf/                 # Desired State Files for deployments
│   ├── prereq-dsf.yaml  # Prerequisites (monitoring, Istio, logging)
│   ├── external-dsf.yaml # External dependencies (PostgreSQL, Keycloak, MinIO, ActiveMQ, Kafka)
│   ├── mosip-dsf.yaml   # MOSIP core services (Identity, Auth, Registration)
│   └── testrigs-dsf.yaml # Testing suite (API, DSL, UI test rigs)
├── hooks/               # Deployment automation scripts
└── utils/               # Utilities and configurations
    ├── istio-addons/    # Service mesh components
    ├── logging/         # Logging stack configurations
    └── monitoring/      # Monitoring and alerting setup
```

### Automation Layer (GitHub Actions)

```
.github/workflows/
├── terraform.yml        # Infrastructure provisioning workflow
├── terraform-destroy.yml # Infrastructure cleanup workflow
├── helmsman_external.yml # External dependencies deployment
├── helmsman_mosip.yml   # MOSIP core services deployment
└── helmsman_testrigs.yml # Testing infrastructure deployment
```

> **Note**: PostgreSQL secrets are automatically handled by Terraform modules - no separate workflow required!

---

## Quick Start Guide

### 1. Fork & Configure Repository

```bash
# Fork this repository to your GitHub account
# Configure required GitHub secrets
# Create environment-specific branch (optional)
```

### 2. Deploy Infrastructure

```bash
# Navigate to GitHub Actions
# Run "terraform plan / apply" workflow
# Select target cloud provider and environment
# Monitor deployment progress
```

### 3. Deploy Dependencies & MOSIP

```bash
# Run "helmsman external" workflow (prerequisites + external dependencies in parallel)
# Run "helmsman mosip" workflow (core MOSIP services)  
# Run "helmsman testrigs" workflow (testing infrastructure)
```

### 4. Access MOSIP Platform

```bash
# Access Rancher UI (if observ-infra deployed)
# Access MOSIP services via configured domain
# Run automated tests via deployed test rigs
```

---

## Detailed Documentation

| Component                | Purpose                     | Documentation                                                               |
| ------------------------ | --------------------------- | --------------------------------------------------------------------------- |
| **Terraform**      | Infrastructure provisioning | [terraform/README.md](terraform/README.md)                                     |
| **Helmsman**       | Application deployment      | [Helmsman/README.md](Helmsman/README.md)                                       |
| **GitHub Actions** | CI/CD automation            | [.github/workflows/README.md](.github/workflows/README.md)                     |
| **Architecture**   | Visual diagrams             | [docs/_images/ARCHITECTURE_DIAGRAMS.md](docs/_images/ARCHITECTURE_DIAGRAMS.md) |

---

## Optional Components

### Rancher Management (observ-infra)

- **Purpose**: Centralized Kubernetes cluster management
- **Features**: Multi-cluster UI, RBAC, monitoring dashboards
- **Deployment**: Optional during infrastructure provisioning
- **Import**: MOSIP clusters can be optionally imported to Rancher

### Advanced Monitoring

- **Infrastructure monitoring** via cloud-native tools
- **Application monitoring** via Prometheus/Grafana
- **Log aggregation** via ELK/EFK stack
- **Alerting** via AlertManager integration

---

## Support & Troubleshooting

### Common Issues

- **Infrastructure failures**: Check Terraform logs in GitHub Actions
- **Deployment failures**: Review Helmsman logs and Kubernetes events
- **Access issues**: Verify DNS configuration and SSL certificates
- **Test failures**: Check test rig logs and service dependencies

### Community Contributions

**Help expand multi-cloud support!**

- **AWS**: Fully implemented and production-ready
- **Azure**: Placeholder structures available - [contribute here](terraform/base-infra/azure/)
- **GCP**: Placeholder structures available - [contribute here](terraform/base-infra/gcp/)

**What needs to be implemented:**
- VPC/VNet/Network creation and configuration
- Security groups and firewall rules  
- Load balancer and compute instance provisioning
- Storage and networking resource management
- Cloud-specific PostgreSQL integration

**Contribution areas:**
- `terraform/base-infra/{azure,gcp}/` - Base infrastructure modules
- `terraform/infra/{azure,gcp}/` - MOSIP cluster infrastructure  
- `terraform/observ-infra/{azure,gcp}/` - Monitoring infrastructure
- `terraform/modules/{azure,gcp}/` - Reusable cloud modules

### Getting Help

- **GitHub Issues**: Report bugs and request features
- **Documentation**: Comprehensive guides in component directories
- **Community**: MOSIP community support channels

---

## License

This project is licensed under the [Mozilla Public License 2.0](LICENSE).

---

*For detailed technical documentation, refer to the component-specific README files linked above.*
