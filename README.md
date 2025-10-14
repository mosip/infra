<div align="left">
 <img src="docs/_images/MOSIP_Black.svg" alt="MOSIP Logo" width="200"/>
</div>

# MOSIP Rapid Deployment

This repository provides a **3-step rapid deployment model** for MOSIP (Modular Open Source Identity Platform) with enhanced security features including GPG (GNU Privacy Guard) encryption for local backends and integrated PostgreSQL setup via Terraform modules.

## Architecture Overview

For detailed MOSIP platform architecture Diagram, visit: [MOSIP Platform Architecture](https://docs.mosip.io/1.2.0/setup/deploymentnew/v3-installation/1.2.0.2/overview-and-architecture#architecture-diagram)

**Terraform Architecture:**  
[View Terraform Architecture Diagram](docs/_images/terraform-light.draw.io.png)

**Helmsman Architecture:**  
[View Helmsman Architecture Diagram](docs/_images/updated-Helmsman.drawio.png)

**First Time Deploying? Start Here!**

We've created comprehensive beginner-friendly guides to help you succeed:

| Guide                                                                         | What You'll Learn                                                                          | When to Read                                        |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ | --------------------------------------------------- |
| **[Glossary](docs/GLOSSARY.md)**                                           | Plain-language explanations of all technical terms (AWS, Kubernetes, Terraform, VPN, etc.) | Before you start - understand the terminology       |
| **[Secret Generation Guide](docs/SECRET_GENERATION_GUIDE.md)**             | Step-by-step instructions to generate SSH keys, AWS credentials, GPG passwords, and more   | Before deployment - setup required secrets          |
| **[Workflow Guide](docs/WORKFLOW_GUIDE.md)**                               | Visual walkthrough of GitHub Actions workflows with screenshots and navigation help        | During deployment - run workflows correctly         |
| **[DSF Configuration Guide](docs/DSF_CONFIGURATION_GUIDE.md)**             | How to configure Helmsman files including clusterid and domain settings                    | Before Helmsman deployment - configure applications |
| **[Environment Destruction Guide](docs/ENVIRONMENT_DESTRUCTION_GUIDE.md)** | Safe teardown procedures, backup steps, and cost monitoring                                | After deployment - clean up resources               |

**Complete Documentation Index:** [View All Documentation](docs/README.md)

---

## Complete Deployment Flow

```mermaid
graph TB
 %% Prerequisites
 A[Fork Repository] --> B[Configure Secrets]
 B --> C[Select Cloud Provider]
 
 %% Infrastructure Phase
 C --> D[Terraform: base-infra<br/>VPC, Networking, WireGuard]
 D --> E{Deploy<br/>Observability?}
 E -->|Yes| F[Terraform: observ-infra<br/>Rancher UI, Monitoring]
 E -->|No| G[Terraform: infra<br/>MOSIP Infrastructure]
 F --> G
 
 %% Helmsman Deployment Phase
 G --> H[Helmsman: Prerequisites<br/>Monitoring, Istio, Logging]
 H --> I[Helmsman: External Deps<br/>PostgreSQL, Keycloak, MinIO]
 
 %% MOSIP Services
 I --> J[Helmsman: MOSIP Services]
 J --> K{Deploy<br/>Test Rigs?}
 K -->|Yes| L[Helmsman: Test Rigs<br/>API, UI, DSL Testing]
 K -->|No| M[Verify Deployment]
 L --> M
 
 %% Final Verification
 M --> N[Access MOSIP Platform]
 N --> O[Deployment Complete]
 
 %% Styling
 classDef prereq fill:#fff3e0,stroke:#ff8f00,stroke-width:2px
 classDef terraform fill:#e3f2fd,stroke:#1976d2,stroke-width:2px
 classDef helmsman fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
 classDef success fill:#e8f5e8,stroke:#388e3c,stroke-width:2px
 classDef decision fill:#fce4ec,stroke:#c2185b,stroke-width:2px
 
 class A,B,C prereq
 class D,F,G terraform
 class H,I,J,L helmsman
 class M,N,O success
 class E,K decision
```

> **Note:** Complete Terraform scripts are available only for **AWS**. For **Azure and GCP**, only placeholder structures are configured - community contributions are welcome to implement full functionality.

## Prerequisites

> **New to Cloud Deployment?** Check out our [Glossary](docs/GLOSSARY.md) for beginner-friendly explanations of all technical terms used in this guide!

> **Note:** As of now we support AWS based automated deployment. We are looking for community contribution around terraform modules and changes for other cloud service providers.

> **Important for Beginners**: Start with AWS deployment only. Azure and GCP implementations are not yet complete. You'll need:
>
> - An AWS account ([Create one here](https://aws.amazon.com/free/))
> - Basic understanding of cloud concepts ([See our Glossary](docs/GLOSSARY.md))
> - GitHub account for running automated workflows

### Required Cloud Provider Account

- **AWS account** with appropriate permissions (fully supported) - [How to create AWS account](https://aws.amazon.com/premiumsupport/knowledge-center/create-and-activate-aws-account/)
- Azure or GCP account (placeholder implementations - community contributions needed)
- Service account/access keys with infrastructure creation rights

### Required AWS Permissions

**Essential AWS IAM permissions required for complete MOSIP deployment:**

**Core Infrastructure Services:**

- **VPC Management**: VPC, Subnets, Internet Gateways, NAT Gateways, Route Tables
- **EC2 Services**: Instance management, Security Groups, Key Pairs, EBS Volumes
- **Route 53**: DNS management, Hosted Zones, Record Sets
- **IAM**: Role creation, Policy management, Instance Profiles

**Recommended IAM Policy:**

```json
{
 "Version": "2012-10-17",
 "Statement": [
 {
 "Effect": "Allow",
 "Action": [
 "ec2:*",
 "vpc:*",
 "route53:*",
 "iam:*",
 "s3:*"
 ],
 "Resource": "*"
 }
 ]
}
```

> **Security Note:** For production environments, consider using more restrictive policies with specific resource ARNs and condition statements.

### Required AWS Instance Types

**Default Instance Configuration:**

- **NGINX Instance Type**: `t3a.2xlarge` (Load balancer and reverse proxy)
- **Kubernetes Instance Type**: `t3a.2xlarge` (Control plane, ETCD, and worker nodes)

**Instance Family Details:**

- **t3a Instance Family**: AMD EPYC processors with burstable performance
- **2xlarge Configuration**: 8 vCPUs, 32 GiB RAM, up to 2,880 Mbps network performance
- **Use Cases**: Suitable for production workloads with moderate to high CPU utilization

**Alternative Instance Types:**

- **Development/Testing**: `t3a.large` (4 vCPUs, 16 GiB RAM) - for smaller environments
- **Production/High-Load**: `t3a.4xlarge` (16 vCPUs, 64 GiB RAM) - for high-traffic deployments
- **Cost-Optimized**: `t3.2xlarge` (Intel processors) or `t3a.xlarge` for budget constraints

**NGINX Instance Type Recommendations:**

- **With External PostgreSQL**: `t3a.2xlarge` (recommended for PostgreSQL hosting)
- **Without External PostgreSQL**: `t3a.xlarge` or `t3a.medium` (sufficient for load balancing only)

> **Configuration Note:** Instance types can be customized in `terraform/implementations/aws/infra/aws.tfvars` by modifying `k8s_instance_type` and `nginx_instance_type` variables.

### Required Secrets for Rapid Deployment

> **Need help generating secrets?** See our comprehensive [Secret Generation Guide](docs/SECRET_GENERATION_GUIDE.md) for step-by-step instructions with screenshots and examples!

> **Secret Configuration Types:**
>
> - **Repository Secrets**: Global secrets shared across all environments (set once in GitHub repo settings)
> - Think of these as "master keys" that work everywhere
> - Examples: AWS credentials, SSH keys
> - **Environment Secrets**: Environment-specific secrets (configured per deployment environment)
> - Think of these as "room keys" for specific environments
> - Examples: KUBECONFIG, WireGuard configs (different for each environment)
>
> **Still confused?** Read the [Secret Generation Guide](docs/SECRET_GENERATION_GUIDE.md) - it explains everything in plain language!

#### Terraform Secrets

> **How to generate each secret**: See [Secret Generation Guide](docs/SECRET_GENERATION_GUIDE.md) for detailed instructions

**Repository Secrets** (configured in GitHub repository settings):

```yaml
# GPG Encryption (for local backend)
GPG_PASSPHRASE: "your-gpg-passphrase" 
# What it's for: Encrypts Terraform state files to keep them secure
# How to generate: Create a strong 16+ character password
# Details: https://docs.github.com/en/actions/security-guides/encrypted-secrets
# Guide: See "GPG Passphrase" section in Secret Generation Guide

# Cloud Provider Credentials
AWS_ACCESS_KEY_ID: "AKIA..." 
# What it's for: Allows Terraform to create AWS resources
# How to get: AWS Console → IAM → Users → Security credentials → Create access key
# Details: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html
# Guide: See "AWS Credentials" section in Secret Generation Guide

AWS_SECRET_ACCESS_KEY: "..." 
# What it's for: Secret key that pairs with access key ID (like a password)
# IMPORTANT: Keep this SECRET! Never commit to Git or share publicly

# SSH Private Key (must match ssh_key_name in tfvars)
YOUR_SSH_KEY_NAME: | 
# Replace YOUR_SSH_KEY_NAME with actual ssh_key_name value from your tfvars
# What it's for: Allows secure access to EC2 instances
# How to generate: ssh-keygen -t rsa -b 4096 -C "your-email@example.com"
# Details: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent
# Guide: See "SSH Keys" section in Secret Generation Guide
 -----BEGIN RSA PRIVATE KEY-----
 your-ssh-private-key-content
 -----END RSA PRIVATE KEY-----
```

**Quick Secret Generation Checklist:**

- [ ] GPG Passphrase created (16+ characters)
- [ ] AWS Access Key ID obtained from IAM
- [ ] AWS Secret Access Key saved securely
- [ ] SSH key pair generated (public + private)
- [ ] SSH public key uploaded to AWS EC2 Key Pairs
- [ ] SSH private key added to GitHub secrets
- [ ] All secret names match exactly (case-sensitive!)

**Need step-by-step help?** [Secret Generation Guide](docs/SECRET_GENERATION_GUIDE.md)

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
SLACK_WEBHOOK_URL: "https://hooks.slack.com/services/..." # Slack notifications
```

#### Helmsman Secrets

**Environment Secrets** (configured per deployment environment):

> **Important**: These are generated AFTER infrastructure deployment, not before!
>
> ## Next Steps & Detailed Documentation

```yaml
# Kubernetes Access
KUBECONFIG: "apiVersion: v1..." 
# What it's for: Allows Helmsman to deploy applications to your Kubernetes cluster
# When available: After Terraform infra deployment completes
# Where to find: terraform/implementations/aws/infra/kubeconfig_<cluster-name>
# Guide: See "Kubernetes Config" section in Secret Generation Guide

# WireGuard VPN Access (for cluster access)
CLUSTER_WIREGUARD_WG0: |
# What it's for: Secure VPN connection to access private Kubernetes cluster
# When available: After base-infra deployment and WireGuard setup
# How to get: Follow WireGuard setup guide
# Details: See terraform/base-infra/WIREGUARD_SETUP.md
# Guide: See "WireGuard VPN" section in Secret Generation Guide
 [Interface]
 PrivateKey = helmsman-wg0-private-key
 Address = 10.0.0.2/24
 
 [Peer]
 PublicKey = cluster-public-key
 Endpoint = cluster-server:51820
 AllowedIPs = 10.0.0.0/16

# Secondary WireGuard Config (optional)
CLUSTER_WIREGUARD_WG1: |
# Optional: Additional WireGuard peer for redundancy
 [Interface]
 PrivateKey = helmsman-wg1-private-key
 Address = 10.0.2.2/24
 
 [Peer]
 PublicKey = cluster-public-key-2
 Endpoint = cluster-server-2:51820
 AllowedIPs = 10.0.0.0/16
```

**Deployment Order for Secrets:**

1. **Before starting**: Add Repository Secrets (GPG, AWS, SSH)
2. **After base-infra**: Add TF_WG_CONFIG environment secret
3. **After main infra**: Add KUBECONFIG, CLUSTER_WIREGUARD_WG0/WG1 environment secrets

**Need step-by-step help?** [Secret Generation Guide](docs/SECRET_GENERATION_GUIDE.md)

> **Note**: PostgreSQL secrets are no longer required! PostgreSQL setup is handled automatically by Terraform modules and Ansible scripts based on your `enable_postgresql_setup` configuration.

## Deployment Steps Guide

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

- **Repository Secrets** (Settings → Secrets and variables → Actions → Repository secrets):
- `GPG_PASSPHRASE`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `YOUR_SSH_KEY_NAME` (replace with actual ssh_key_name value from tfvars, e.g., `mosip-aws`)
- **Environment Secrets** (Settings → Secrets and variables → Actions → Environment secrets):
- All other secrets mentioned in the Prerequisites section above (KUBECONFIG, WireGuard configs, etc.)

### 3. Terraform Infrastructure Deployment

> **New to Terraform workflows?** Check our [Workflow Guide](docs/WORKFLOW_GUIDE.md) for visual step-by-step instructions on navigating GitHub Actions!

#### Understanding Terraform Apply vs Terraform Plan

Before running any Terraform workflow, understand these modes:

| Mode                                             | What It Does                                   | When to Use                                | Visual             |
| ------------------------------------------------ | ---------------------------------------------- | ------------------------------------------ | ------------------ |
| **Terraform Plan** (checkbox unchecked ☐) | Shows what WOULD happen without making changes | Testing configurations, previewing changes | ☐ Terraform apply |
| **Apply** (checkbox checked ✅)            | Actually creates/modifies infrastructure       | Real deployments, making actual changes    | ✅ Terraform apply |

**Tip**: Always run terraform plan first to preview changes, then run with apply checked to actually deploy!

#### Things to Know While Working with Terraform Workflows

For detailed information about GitHub Actions workflow parameters, terraform modes, and best practices, see: [Terraform Workflow Guide](docs/TERRAFORM_WORKFLOW_GUIDE.md)

#### Step 3a: Base Infrastructure

**What this creates:**

- Virtual Private Cloud (VPC) - Your private network in AWS
- Subnets - Subdivisions of your network
- Jump Server - Secure gateway to access other servers
- WireGuard VPN - Encrypted connection to your infrastructure
- Security Groups - Firewall rules for network security

**Time required:** 10-15 minutes

1. **Update terraform variables:**

```bash
 # Edit terraform/base-infra/aws/terraform.tfvars (or azure/gcp)
```

2. **Configure base-infra variables:**

```hcl
 # Example for AWS
 region = "us-west-2" # Choose AWS region close to your users
 availability_zones = ["us-west-2a", "us-west-2b"] # Multiple zones for high availability
 vpc_cidr = "10.0.0.0/16" # Private IP address range for your network
 environment = "production" # Name your environment
```

3. **Run base-infra via GitHub Actions:**

> **Detailed Navigation Guide**: See [Workflow Guide - Terraform Workflows](docs/WORKFLOW_GUIDE.md#workflow-1-base-infrastructure) for step-by-step screenshots

![Base Infrastructure Terraform Apply](docs/_images/base-infra-terraform-apply.png)

- **(1)** Go to **Actions** → **terraform plan/apply**
  - **Can't find it?** Look in the left sidebar under "All workflows"
  - Click **Run workflow** (green button on the right)
  - **Configure workflow parameters:**
- **(2)** **Branch**: Select your deployment branch (e.g., `release-0.1.0`)
  - **What's this?** The branch of code to use for deployment
- **(3)** **Cloud Provider**: Select `aws` (Azure/GCP are placeholder implementations)
  - **Important**: Only `aws` is fully functional
- **(4)** **Component**: Select `base-infra` (creates VPC, networking, jump server, WireGuard)
  - **What's this?** Which part of infrastructure to build
- **Backend**: Choose backend configuration:
  - **(5)** `local` - GPG-encrypted local state (recommended for development)
    - Stores state in your GitHub repository (encrypted)
  - **(6)** `s3` - Remote S3 backend (recommended for production)
    - Stores state in AWS S3 bucket (centralized)
- **(7)** **SSH_PRIVATE_KEY**: GitHub secret name containing SSH private key for instance access
  - Must match the `ssh_key_name` in your terraform.tfvars
- **Terraform apply**:
  - **(8)** ☐ **Unchecked** - Terraform plan (preview only, no changes made)
  - **(8)** ✅ **Checked** - Apply (actually creates infrastructure)
  - **First time?** Uncheck for terraform plan, then run again with checked

 **What You Should See:**

- ✅ Workflow running (yellow circle icon)
- ✅ Steps completing one by one
- ✅ Green checkmark when complete
- ✅ Infrastructure created in AWS

 **Component Details:**

- **VPC & Networking**: Creates secure network foundation
- **Jump Server**: Bastion host for secure access
- **WireGuard VPN**: Encrypted private network access
- **Security Groups**: Network access controls
- **Route Tables**: Network traffic routing

 **Need more help?** [Workflow Guide](docs/WORKFLOW_GUIDE.md)

#### Step 3b: WireGuard VPN Setup (Required for Private Network Access)

> **What is WireGuard?** A modern VPN that creates a secure, encrypted "tunnel" to access your private infrastructure. Think of it like a secure phone line that only you can use to call your servers! [Learn more](docs/GLOSSARY.md#wireguard)

**After base infrastructure deployment**, set up WireGuard VPN for secure access to private infrastructure:

> **Detailed Setup Guide:** [WireGuard Setup Documentation](terraform/base-infra/WIREGUARD_SETUP.md)
>
> **Secret Generation:** [How to generate WireGuard configs](docs/SECRET_GENERATION_GUIDE.md#4-wireguard-vpn-configuration)

**Quick Setup Overview:**

1. **SSH to Jump Server:** Access the deployed jump server

- Use the SSH key you created earlier
- Jump server IP is in Terraform outputs

2. **Configure Peers:** Assign and customize WireGuard peer configurations

- Create **peer1** configuration for Terraform access (your computer → infrastructure)
- Create **peer2** configuration for Helmsman access (GitHub Actions → cluster)
- Think of peers as "authorized devices" that can connect

3. **Install Client:** Set up WireGuard client on your PC/Mac

- **Windows**: [Download installer](https://www.wireguard.com/install/)
- **Mac**: Install from App Store or use `brew install wireguard-tools`
- **Linux**: `sudo apt install wireguard` (Ubuntu/Debian)

4. **Update Environment Secrets:** Add WireGuard configurations to your GitHub environment secrets:

- `TF_WG_CONFIG` - For Terraform infrastructure deployments
- `CLUSTER_WIREGUARD_WG0` - For Helmsman cluster access (peer1)
- `CLUSTER_WIREGUARD_WG1` - For Helmsman cluster access (peer2, optional)
- [How to add secrets to GitHub](docs/SECRET_GENERATION_GUIDE.md#7-how-to-add-secrets-to-github)

5. **Verify Connection:** Test private IP connectivity

```bash
 # Activate WireGuard tunnel
 # Then test connectivity
 ping 10.0.0.1 # Should work if VPN is connected
```

**Why WireGuard is Required:**

- **Private Network Access:** Connect to Kubernetes cluster via private IPs (not exposed to internet)
- **Enhanced Security:** Encrypted VPN tunnel for all infrastructure access (256-bit encryption)
- **Terraform Integration:** Required for subsequent infrastructure deployments
- **Helmsman Connectivity:** Enables secure cluster access for service deployments

**Visual Explanation:**

```
Without WireGuard:
Your Computer → ❌ Can't reach private servers

With WireGuard:
Your Computer → VPN Tunnel → ✅ Access private servers securely
```

> **Important:** Complete WireGuard setup and configure `TF_WG_CONFIG` environment secret before proceeding to MOSIP infrastructure deployment.
>
> **Need help?** Check the [detailed WireGuard guide](terraform/base-infra/WIREGUARD_SETUP.md) with screenshots!

#### Step 3c: MOSIP Infrastructure

1. **Update infra variables in `terraform/implementations/aws/infra/aws.tfvars`:**

 Complete configuration example with detailed explanations:

```hcl
 # Environment name (infra component)
 cluster_name = "soil38"
 # MOSIP's domain (ex: sandbox.xyz.net)
 cluster_env_domain = "soil38.mosip.net"
 # Email-ID will be used by certbot to notify SSL certificate expiry via email
 mosip_email_id = "chandra.mishra@technoforte.co.in"
 # SSH login key name for AWS node instances (ex: my-ssh-key)
 ssh_key_name = "mosip-aws"
 # The AWS region for resource creation
 aws_provider_region = "ap-south-1"

 # Specific availability zones for VM deployment (optional)
 # If empty, uses all available AZs in the region
 # Example: ["ap-south-1a", "ap-south-1b"] for specific AZs
 # Example: [] for all available AZs in the region
 specific_availability_zones = []

 # The instance type for Kubernetes nodes (control plane, worker, etcd)
 k8s_instance_type = "t3a.2xlarge"
 # The instance type for Nginx server (load balancer)
 nginx_instance_type = "t3a.2xlarge"
 # The Route 53 hosted zone ID
 zone_id = "Z090954828SJIEL6P5406"

 ## UBUNTU 24.04
 # The Amazon Machine Image ID for the instances
 ami = "ami-0ad21ae1d0696ad58"

 # Repo K8S-INFRA URL
 k8s_infra_repo_url = "https://github.com/mosip/k8s-infra.git"
 # Repo K8S-INFRA branch
 k8s_infra_branch = "MOSIP-42914"
 # NGINX Node's Root volume size
 nginx_node_root_volume_size = 24
 # NGINX node's EBS volume size
 nginx_node_ebs_volume_size = 300
 # NGINX node's second EBS volume size (optional - set to 0 to disable)
 nginx_node_ebs_volume_size_2 = 200 # Enable second EBS volume for PostgreSQL testing
 # Kubernetes nodes Root volume size
 k8s_instance_root_volume_size = 64

 # Control-plane, ETCD, Worker
 k8s_control_plane_node_count = 3
 # ETCD, Worker
 k8s_etcd_node_count = 3
 # Worker
 k8s_worker_node_count = 2

 # RKE2 Version Configuration
 rke2_version = "v1.28.9+rke2r1"

 # Rancher Import Configuration
 enable_rancher_import = false

 # Security group CIDRs
 network_cidr = "10.0.0.0/8" # Use your actual VPC CIDR
 WIREGUARD_CIDR = "10.0.0.0/8" # Use your actual WireGuard VPN CIDR

 # Rancher Import URL
 rancher_import_url = "\"kubectl apply -f https://rancher.mosip.net/v3/import/dzshvnb6br7qtf267zsrr9xsw6tnb2vt4x68g79r2wzsnfgvkjq2jk_c-m-b5249w76.yaml\""
 # DNS Records to map
 subdomain_public = ["resident", "prereg", "esignet", "healthservices", "signup"]
 subdomain_internal = ["admin", "iam", "activemq", "kafka", "kibana", "postgres", "smtp", "pmp", "minio", "regclient", "compliance"]

 # PostgreSQL Configuration (used when second EBS volume is enabled)
 enable_postgresql_setup = true # Enable PostgreSQL setup for main infra
 postgresql_version = "15"
 storage_device = "/dev/nvme2n1"
 mount_point = "/srv/postgres"
 postgresql_port = "5433"

 # MOSIP Infrastructure Repository Configuration
 mosip_infra_repo_url = "https://github.com/mosip/mosip-infra.git"
 mosip_infra_branch = "develop"

 # VPC Configuration - Existing VPC to use (discovered by Name tag)
 vpc_name = "mosip-boxes"
```

 **Key Configuration Variables Explained:**

| Variable                         | Description                                | Example Value                               |
| -------------------------------- | ------------------------------------------ | ------------------------------------------- |
| `cluster_name`                 | Unique identifier for your MOSIP cluster   | `"soil38"`                                |
| `cluster_env_domain`           | Domain name for MOSIP services access      | `"soil38.mosip.net"`                      |
| `mosip_email_id`               | Email for SSL certificate notifications    | `"admin@example.com"`                     |
| `ssh_key_name`                 | AWS EC2 key pair name for SSH access       | `"mosip-aws"`                             |
| `aws_provider_region`          | AWS region for resource deployment         | `"ap-south-1"`                            |
| `zone_id`                      | Route 53 hosted zone ID for DNS management | `"Z090954828SJIEL6P5406"`                 |
| `k8s_instance_type`            | EC2 instance type for Kubernetes nodes     | `"t3a.2xlarge"`                           |
| `nginx_instance_type`          | EC2 instance type for load balancer        | `"t3a.2xlarge"`                           |
| `ami`                          | Amazon Machine Image ID (Ubuntu 24.04)     | `"ami-0ad21ae1d0696ad58"`                 |
| `enable_postgresql_setup`      | External PostgreSQL setup via Terraform    | `true` (external) / `false` (container) |
| `nginx_node_ebs_volume_size_2` | EBS volume size for PostgreSQL data (GB)   | `200`                                     |
| `postgresql_version`           | PostgreSQL version to install              | `"15"`                                    |
| `postgresql_port`              | PostgreSQL service port                    | `"5433"`                                  |
| `vpc_name`                     | Existing VPC name tag to use               | `"mosip-boxes"`                           |

> **Important Notes:**
>
> - Ensure `cluster_name` and `cluster_env_domain` match values used in Helmsman DSF files
> - Set `enable_postgresql_setup = true` for production deployments with external PostgreSQL
> - Set `enable_postgresql_setup = false` for development deployments with containerized PostgreSQL
> - The `nginx_node_ebs_volume_size_2` is required when `enable_postgresql_setup = true`
> - **SSH Key Configuration**: The `ssh_key_name` value must match the repository secret name containing your SSH private key (e.g., if `ssh_key_name = "mosip-aws"`, create repository secret named `mosip-aws` with your SSH private key content)

**Component Details:**

- **infra**: Creates MOSIP Kubernetes cluster, PostgreSQL (if enabled), networking, and application infrastructure

**PostgreSQL Configuration in `aws.tfvars`:**

```hcl
# PostgreSQL Configuration (used when second EBS volume is enabled)
enable_postgresql_setup = true # Enable PostgreSQL setup for main infra
postgresql_version = "15"
storage_device = "/dev/nvme2n1"
mount_point = "/srv/postgres"
postgresql_port = "5433"

# NGINX node's second EBS volume size (required for PostgreSQL)
nginx_node_ebs_volume_size_2 = 200 # Enable second EBS volume for PostgreSQL
```

**If `enable_postgresql_setup = true`, Terraform will automatically:**

- Provision dedicated EBS volume for PostgreSQL on nginx node
- Install and configure PostgreSQL 15 via Ansible playbooks
- Setup security configurations and user access controls
- Configure backup and recovery mechanisms
- Make PostgreSQL ready for MOSIP services connectivity
- No manual PostgreSQL secret management required!

#### Rancher Import Configuration (Optional)

If you have deployed **observ-infra** (Rancher management cluster), you can import your main infra cluster into Rancher for centralized monitoring and management.

**Step 1: Generate Rancher Import URL**

1. **Access Rancher UI:**

   ```
   https://rancher.your-domain.net
   ```

   Login with credentials from observ-infra deployment.
2. **Navigate to Cluster Import:**

   ```
   Rancher UI → Cluster Management → Import Existing
   ```
3. **Select Import Method:**

   ```
   Click: "Import any Kubernetes cluster" → Generic
   ```
4. **Configure Cluster Import:**

   ```
   Cluster Name: soil38 (use your cluster_name from aws.tfvars)

   Click: "Create"
   ```
5. **Copy the kubectl apply command:**

   Rancher will generate a command like:

   ```bash
   kubectl apply -f https://rancher.mosip.net/v3/import/dzshvnb6br7qtf267zsrr9xsw6tnb2vt4x68g79r2wzsnfgvkjq2jk_c-m-b5249w76.yaml
   ```

**Step 3: Update aws.tfvars**

Add the generated command to your `aws.tfvars` file:

```hcl
# Enable Rancher import
enable_rancher_import = true

# Paste the kubectl apply command from Rancher UI
# IMPORTANT: Use proper escaping - wrap the entire command in quotes with escaped inner quotes
rancher_import_url = "\"kubectl apply -f https://rancher.mosip.net/v3/import/dzshvnb6br7qtf267zsrr9xsw6tnb2vt4x68g79r2wzsnfgvkjq2jk_c-m-b5249w76.yaml\""
```

**⚠️ Critical: Proper String Escaping**

The `rancher_import_url` requires special escaping to avoid Terraform indentation errors:

✅ **Correct format:**

```hcl
rancher_import_url = "\"kubectl apply -f https://rancher.example.com/v3/import/TOKEN.yaml\""
```

❌ **Wrong format (will cause errors):**

```hcl
rancher_import_url = "kubectl apply -f https://rancher.example.com/v3/import/TOKEN.yaml"
```

**Step 4: Deploy/Update Main Infra**

After updating `aws.tfvars`, deploy or update your main infra cluster:

2. **Run main infra via GitHub Actions:**

![Infrastructure Terraform Apply](docs/_images/infra-terraform-apply.png)

- **(1)** Go to **Actions** → **terraform plan/apply**
- **(2)** Click **Run workflow**
- **(3)** **Configure workflow parameters:**
- **(4)** **Branch**: Select your deployment branch (e.g., `release-0.1.0`)
- **(5)** **Cloud Provider**: Select `aws` (Azure/GCP are placeholder implementations)
- **(6)** **Component**: Select `infra` (MOSIP application infrastructure)
- **(7)** **Backend**: Choose backend configuration:
  - `local` - GPG-encrypted local state (recommended for development)
  - `s3` - Remote S3 backend (recommended for production)
- **(8)** **SSH_PRIVATE_KEY**: GitHub secret name containing SSH private key for instance access
  - Must match the `ssh_key_name` in your terraform.tfvars
- **(9)** **Action**: Select `apply` to deploy infrastructure

**Verify Rancher Import (Only if rancher_import = true):**

> **Note:** Skip this entire section if you deployed without Rancher UI (`rancher_import = false`)

After deployment completes:

1. Go to Rancher UI: `https://rancher.your-domain.net`
2. Navigate to: **Cluster Management**
3. Your cluster should appear in the list with status: **Active**
4. Click on the cluster name to view:
   - Node status
   - Pod metrics
   - Resource utilization
   - Monitoring dashboards

**Troubleshooting Rancher Import:**

If import fails, check:

```bash
# Verify cluster is accessible
kubectl get nodes

# Check if rancher-agent pods are running
kubectl get pods -n cattle-system

# View rancher-agent logs
kubectl logs -n cattle-system -l app=cattle-cluster-agent

# Common issues:
# 1. Network connectivity between clusters
# 2. Firewall rules blocking Rancher server access
# 3. Incorrect import URL or expired token
```

To regenerate import URL if needed:

1. Go to Rancher UI → Cluster Management
2. Find your cluster (it may show as "Unavailable")
3. Click ⋮ (three dots) → Edit Config
4. Copy the new registration command

   ```
   Cluster Name: soil38 (use your cluster_name from aws.tfvars)

   ```

### 4. Helmsman Deployment

> **What is DSF?** DSF (Desired State File) is like a recipe that tells Helmsman what applications to install and how to configure them. [Learn more](docs/GLOSSARY.md#dsf-desired-state-file)
>
> **Detailed DSF Guide:** [DSF Configuration Guide](docs/DSF_CONFIGURATION_GUIDE.md) - Comprehensive guide with examples and explanations!

#### Step 4a: Update DSF Configuration Files

1. **Clone the repository (if not already done):**

```bash
 git clone https://github.com/mosip/infra.git
 cd infra/Helmsman
```

2. **Navigate to DSF configuration directory:**

```bash
 cd dsf/
```

3. **Update prereq-dsf.yaml:**

> **IMPORTANT CONFIGURATION:** This file requires **clusterid** configuration **only if you're using Rancher UI** (when `rancher_import = true`)! See [DSF Configuration Guide - clusterid](docs/DSF_CONFIGURATION_GUIDE.md#critical-configuration-clusterid)

 **Critical Updates Required:**

- **clusterid Configuration (OPTIONAL - only if using Rancher):**
- **When needed?** Only if `rancher_import = true` in your terraform configuration
- **Skip if:** Deploying without Rancher UI (`rancher_import = false`) - ignore this entire section
- **What is this?** Unique identifier for your Rancher-managed cluster
- **Why needed?** Monitoring dashboards won't work without it in Rancher deployments
- **How to find:** See [DSF Guide - Finding clusterid](docs/DSF_CONFIGURATION_GUIDE.md#how-to-find-your-clusterid)
- **Location in file:** Around line 40-45
- **What to change:**

```yaml
 set:
 grafana.global.cattle.clusterId: "c-m-pbrcfglw" # ← REPLACE THIS
 global.cattle.clusterId: "c-m-pbrcfglw" # ← REPLACE THIS
```

- **Domain Validation (Double-check):**
- `<sandbox>` → your cluster name (e.g., `soil38`)
- `sandbox.xyz.net` → your domain name (e.g., `soil38.mosip.net`)
- **Why?** Every service needs to know its web address
- **Chart Versions:** Verify and update to latest stable versions
- Check [MOSIP Helm Repository](https://mosip.github.io/mosip-helm) for latest versions
- **Namespace Configuration:** Ensure proper namespace isolation
- **What is namespace?** Like separate folders for different applications

> **Note:** Maintain consistency with your Terraform configuration:
>
> - `<sandbox>` should match `cluster_name` in `aws.tfvars`
> - `sandbox.xyz.net` should match `cluster_env_domain` in `aws.tfvars`
> - These MUST be identical or deployment will fail!

```yaml
 # Configure monitoring, Istio, logging
 helmRepos:
 rancher-latest: "https://releases.rancher.com/server-charts/latest"

 apps:
 rancher-monitoring:
 enabled: true
 namespace: cattle-monitoring-system
 # DON'T FORGET: Update clusterid here! See above
```

 **Need detailed help?** [DSF Configuration Guide - Prerequisites](docs/DSF_CONFIGURATION_GUIDE.md#prerequisites-dsf-configuration)

4. **Update external-dsf.yaml:**

 **Critical Updates Required:**

- **Domain Validation (Double-check):**
- `<sandbox>` → your cluster name (e.g., `soil`)
- `sandbox.xyz.net` → your domain name (e.g., `soil.mosip.net`)
- **Chart Versions:** Update Helm chart versions to latest stable releases
- **Database Branch:** Verify correct branch for DB scripts and schema
- **PostgreSQL Configuration:** Match with Terraform `enable_postgresql_setup` setting

> **Note:** Maintain consistency with your Terraform configuration:
>
> - `<sandbox>` should match `cluster_name` in `aws.tfvars`
> - `sandbox.xyz.net` should match `cluster_env_domain` in `aws.tfvars`

- **Configure reCAPTCHA keys:**

1. **Create reCAPTCHA keys for each domain:**

- Go to [Google reCAPTCHA Admin](https://www.google.com/recaptcha/admin/create)
- Create reCAPTCHA v2 ("I'm not a robot" Checkbox) for each domain:
- **PreReg domain**: `prereg.your-domain.net` (e.g., `prereg.soil.mosip.net`)
- **Admin domain**: `admin.your-domain.net` (e.g., `admin.soil.mosip.net`)
- **Resident domain**: `resident.your-domain.net` (e.g., `resident.soil.mosip.net`)

2. **Update captcha-setup.sh arguments in external-dsf.yaml (around line 315):**

```yaml
 hooks:
 postInstall: "$WORKDIR/hooks/captcha-setup.sh PREREG_SITE_KEY PREREG_SECRET_KEY ADMIN_SITE_KEY ADMIN_SECRET_KEY RESIDENT_SITE_KEY RESIDENT_SECRET_KEY"
```

 **Arguments order:**

- **Argument 1**: PreReg site key
- **Argument 2**: PreReg secret key
- **Argument 3**: Admin site key
- **Argument 4**: Admin secret key
- **Argument 5**: Resident site key
- **Argument 6**: Resident secret key

3. **Example configuration:**

```yaml
 hooks:
 postInstall: "$WORKDIR/hooks/captcha-setup.sh 6LfkAMwrAAAAAATB1WhkIhzuAVMtOs9VWabODoZ_ 6LfkAMwrAAAAAHQAT93nTGcLKa-h3XYhGoNSG-NL 6LdNAcwrAAAAAETGWvz-3I12vZ5V8vPJLu2ct9CO 6LdNAcwrAAAAAE4iWGJ-g6Dc2HreeJdIwAl5h1iL 6LdRAcwrAAAAAFUEHHKK5D_bSrwAPqdqAJqo4mCk 6LdRAcwrAAAAAOeVl6yHGBCBA8ye9GsUOy4pi9s9"
```

```yaml
 # Configure external dependencies
 apps:
 postgresql:
 # Set based on your Terraform configuration:
 enabled: false # false if enable_postgresql_setup = true (external PostgreSQL via Terraform)
 # true if enable_postgresql_setup = false (container PostgreSQL)
 minio:
 enabled: true
 kafka:
 enabled: true
```

5. **Update mosip-dsf.yaml:**

 **Critical Updates Required:**

- **Domain Validation (Double-check):**
- `<sandbox>` → your cluster name (e.g., `soil`)
- `sandbox.xyz.net` → your domain name (e.g., `soil.mosip.net`)
- **Chart Versions:** Update MOSIP service chart versions to compatible releases
- **Database Branch:** Ensure correct MOSIP DB scripts branch matches deployment version
- **Service Dependencies:** Verify all required external services are properly configured
- **Resource Limits:** Adjust CPU/memory limits based on environment requirements

> **Note:** Maintain consistency with your Terraform configuration:
>
> - `<sandbox>` should match `cluster_name` in `aws.tfvars`
> - `sandbox.xyz.net` should match `cluster_env_domain` in `aws.tfvars`

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

6. **Update testrigs-dsf.yaml (if deploying test environment):**

 **Critical Updates Required:**

- **Domain Validation (Double-check):**
- `<sandbox>` → your cluster name (e.g., `soil`)
- `sandbox.xyz.net` → your domain name (e.g., `soil.mosip.net`)
- **Test Chart Versions:** Update test rig chart versions to match MOSIP service versions
- **Database Branch:** Ensure test DB scripts use correct branch
- **Test Configuration:** Update test endpoints, API versions, and test data paths
- **Resource Allocation:** Configure appropriate test environment resource limits

> **Critical Validation Checklist for All DSF Files:**
>
> **Domain Configuration (Validate Twice):**
>
> - `<sandbox>` → your cluster name (e.g., `soil`)
> - `sandbox.xyz.net` → your domain name (e.g., `soil.mosip.net`)
> - Verify domain DNS resolution is working
> - Ensure SSL certificate coverage for all subdomains
>
> **Version Management:**
>
> - **Chart Versions**: Update all Helm chart versions to latest compatible releases
> - **Database Branch**: Verify DB scripts branch matches your MOSIP deployment version
> - **Service Versions**: Ensure MOSIP service versions are compatible across all DSF files
>
> **Configuration Consistency:**
>
> - `<sandbox>` must match `cluster_name` in `terraform/implementations/aws/infra/aws.tfvars`
> - `sandbox.xyz.net` must match `cluster_env_domain` in `terraform/implementations/aws/infra/aws.tfvars`
> - PostgreSQL settings must align with `enable_postgresql_setup` in Terraform configuration
>
> **Environment-Specific Updates:**
>
> - Resource limits and requests based on environment capacity
> - Storage class configurations for persistent volumes
> - Ingress controller and load balancer settings
> - Security context and RBAC configurations

#### Step 4b: Configure Repository Secrets for Helmsman

**After updating all DSF files**, configure the required repository secrets for Helmsman deployments:

1. **Update Repository Branch Configuration:**

- Ensure your repository is configured to use the correct branch for Helmsman workflows
- Verify GitHub Actions have access to your deployment branch

2. **Configure KUBECONFIG Secret:**

 **Locate the Kubernetes config file:**

```bash
 # After Terraform infrastructure deployment completes, find the kubeconfig file in:
 terraform/implementations/aws/infra/
```

**Example kubeconfig file location:**

```
 terraform/implementations/aws/infra/kubeconfig_<cluster-name>
 terraform/implementations/aws/infra/<cluster-name>-role.yaml
```

 **Add KUBECONFIG as Environment Secret:**

- Go to your GitHub repository → Settings → Environments
- Select or create environment for your branch (e.g., `release-0.1.0`, `main`, `develop`)
- Click "Add secret" under Environment secrets
- Name: `KUBECONFIG`
- Value: Copy the entire contents of the kubeconfig file from `terraform/implementations/aws/infra/`

 **Branch Environment Configuration:- Ensure the environment name matches your deployment branch

- Configure environment protection rules if needed
- Verify Helmsman workflows reference the correct environment

3. **Required Environment Secrets for Helmsman:**

 **Environment Secrets (branch-specific):**

```yaml
 # Kubernetes Access (Environment Secret)
 KUBECONFIG: "<contents-of-kubeconfig-file>"

 # WireGuard Cluster Access for Helmsman
 CLUSTER_WIREGUARD_WG0: "peer1-wireguard-config" # Helmsman cluster access (peer1)
 CLUSTER_WIREGUARD_WG1: "peer2-wireguard-config" # Helmsman cluster access (peer2)
```

4. **Verify Secret Configuration:**

- Ensure KUBECONFIG is configured as environment secret for your branch
- Verify repository secrets are properly configured
- Test repository access from GitHub Actions
- Verify KUBECONFIG provides cluster access

> **Important:**
>
> - **KUBECONFIG**: Must be added as Environment Secret tied to your deployment branch name
> - **Branch Environment**: Ensure environment name matches your branch (e.g., `release-0.1.0`)
> - **File Source**: KUBECONFIG file is generated after successful Terraform infrastructure deployment

#### Step 4c: Run Helmsman Deployments via GitHub Actions

> **Need visual guidance?** See [Workflow Guide - Helmsman Workflows](docs/WORKFLOW_GUIDE.md#helmsman-workflows) for detailed step-by-step instructions!

The Helmsman deployment process follows a specific sequence with automated triggers and error handling mechanisms:

> **Important**: Always use `apply` mode for Helmsman deployments. The `dry-run` mode will fail due to dependencies on shared configmaps and secrets from other namespaces that are not available during dry-run validation.
>
> **Why does dry-run fail?** Helmsman checks if resources exist before deployment. In dry-run mode, these resources aren't created yet, so validation fails. Think of it like checking if ingredients are in the kitchen before actually cooking - but in dry-run mode, the ingredients haven't been bought yet!

**Understanding Workflow Names:**

| Actual Workflow Name in GitHub                     | Where to Find           |
| -------------------------------------------------- | ----------------------- |
| "Deploy External services of mosip using Helmsman" | Actions → Left sidebar |
| "Deploy MOSIP services using Helmsman"             | Actions → Left sidebar |
| "Deploy Testrigs of mosip using Helmsman"          | Actions → Left sidebar |

> **Can't find the workflow?** Look for keywords like "External", "MOSIP", or "Deploy" in the left sidebar. See [Workflow Guide](docs/WORKFLOW_GUIDE.md#understanding-workflow-basics) for navigation help!

1. **Deploy Prerequisites & External Dependencies:**

> **Detailed Steps:** [Workflow Guide - Prerequisites &amp; External Dependencies](docs/WORKFLOW_GUIDE.md#workflow-1-prerequisites--external-dependencies)

![Deploy External Services - Helmsman](docs/_images/helmsman-external-services.png)

- **(1)** Actions → **"Deploy External services of mosip using Helmsman"** (or "Helmsman External Dependencies")
  - **Can't find it?** Search for "External" in the workflows list
- **(2)** **Select Run workflow**
- **(3)** **Select Branch**
- This workflow handles both deployments in parallel:
  - **Prerequisites**: `prereq-dsf.yaml` (monitoring, Istio, logging)
  - **External Dependencies**: `external-dsf.yaml` (databases, message queues, storage)
- **(4)** **Mode**: `apply` (required - dry-run will fail!)
  - **Important:** DO NOT select dry-run mode for Helmsman
  - **Time required:** 20-40 minutes
  - **Automatic Trigger**: Upon successful completion, this workflow automatically triggers the MOSIP services deployment

 **What You Should See:**

- ✅ Monitoring stack deploying (Prometheus, Grafana)
- ✅ Istio service mesh installing
- ✅ PostgreSQL database starting (if container mode)
- ✅ MinIO storage deploying
- ✅ Kafka message queue starting

> **Note**: The `helmsman_external.yml` workflow deploys both prereq and external dependencies in parallel for optimal deployment time.

2. **Deploy MOSIP Services (Automated):**

- **Automatically triggered** after successful completion of step 1
- Workflow: **Deploy MOSIP services using Helmsman** (`helmsman_mosip.yml`)
- DSF file: `mosip-dsf.yaml`
- Mode: `apply` (required - dry-run will fail due to namespace dependencies)

 **Error Handling:**

- If the automatic trigger fails, manually trigger: Actions → **Deploy MOSIP services using Helmsman**

3. **Verify All Pods are Running:**

 Before proceeding to test rigs, ensure all MOSIP services are properly deployed:

```bash
 # Check all MOSIP pods are running
 kubectl get pods -A
 kubectl get pods -n keycloak
 kubectl get pods -n postgres
 
 # Ensure no pods are in pending/error state
 kubectl get pods --all-namespaces | grep -v Running | grep -v Completed
```

4. **Handle Onboarding Failures (If Required):**

> **⚠️ Important**: The partner-onboarder pod will run successfully, but you must check the onboarding reports in MinIO to verify if all partners were onboarded correctly. Failed onboardings must be manually re-executed before deploying test rigs.

**When to check and rerun onboarding:**

- After the partner-onboarder pod completes (check MinIO reports for failures)
- When onboarding reports show failed partner registrations
- Before deploying test rigs to ensure all prerequisites are met

**How to check onboarding status and rerun if needed:** Refer to the comprehensive [MOSIP Onboarding Guide](docs/ONBOARDING_GUIDE.md) for detailed troubleshooting and retry procedures.

5. **Deploy Test Rigs (Manual):**

![Deploy Test Rigs - Helmsman](docs/_images/helmsman-testrigs.png)

- **Prerequisites**: All pods from steps 1-2 must be in `Running` state and onboarding completed successfully
- **(1)** Actions → **Deploy Testrigs of mosip using Helmsman** (`helmsman_testrigs.yml`)
- **(2)** workflow - **select Run workflow in right side**
- **(3)** Branch - **Select Branch**
- **(4)** Mode: `apply` (required - dry-run will fail due to namespace dependencies)

**Post-Deployment Steps:**

After test rigs deployment completes:

1. **Update cron schedules**: Update the cron time for all CronJobs in the `dslrig`, `apitestrig`, and `uitestrig` namespaces as needed
2. **Trigger DSL orchestrator**:

   ```bash
   kubectl create job --from=cronjob/cronjob-dslorchestrator-full dslrig-manual-run -n dslrig
   ```

   > **Note**: This job will run for more than 3 hours. Monitor progress with:
   >
   > ```bash
   > kubectl logs -f job/dslrig-manual-run -n dslrig
   > ```
   >

### 6. Verify Deployment

```bash
# Check cluster status
kubectl get nodes
kubectl get namespaces

# Check MOSIP services
kubectl get pods -A
kubectl get services -n istio-system
```

---

## Environment Destruction and Cleanup

For safe teardown procedures and complete cleanup steps, see our [Environment Destruction Guide](docs/ENVIRONMENT_DESTRUCTION_GUIDE.md).

---

## Next Steps & Detailed Documentation

The Quick Start Guide provides the essential deployment flow. For comprehensive configuration options, troubleshooting, and advanced features, refer to the detailed component documentation:

#### **Terraform Infrastructure Documentation**

- **Location**: [`terraform/README.md`](terraform/README.md)
- **Contents**: Detailed variable explanations, multi-cloud configurations, state management, security best practices
- **Use Cases**: Custom infrastructure configurations, production deployments, troubleshooting infrastructure issues

#### **Helmsman Deployment Documentation**

- **Location**: [`Helmsman/dsf/README.md`](Helmsman/dsf/README.md)
- **Contents**: Complete DSF configuration reference, hook scripts, environment management, customization options
- **Use Cases**: Custom service configurations, environment-specific deployments, service scaling and tuning

#### **WireGuard VPN Setup Guide**

- **Location**: [`terraform/base-infra/WIREGUARD_SETUP.md`](terraform/base-infra/WIREGUARD_SETUP.md)
- **Contents**: Step-by-step VPN configuration, multi-peer setup, client installation, troubleshooting
- **Use Cases**: Private network access, secure infrastructure connectivity, peer management

#### **Component-Specific Guides**

- **GitHub Actions Workflows**: [`.github/workflows/`](.github/workflows/) - Complete CI/CD pipeline documentation
- **Security Configurations**: See respective component READMEs for security hardening options

> **Pro Tip**: Each component directory contains detailed documentation tailored to that specific technology stack. Start with this Quick Start Guide, then dive into component-specific docs as needed.

## Known Limitations

### 1. Docker Registry Rate Limits

**Issue**: Docker Hub imposes rate limits on anonymous pulls which can cause deployment failures.

**Symptoms:**

- Image pulling takes excessively long
- "ErrImagePull" deployment errors
- Pods stuck in "ContainerCreating" state for 3+ minutes
- Rate limit error messages from Docker Hub

### 2. Manual Intervention Requirements

**Issue**: Partner onboarding process requires manual execution after the first automated attempt via Helmsman.

**Impact**: Additional administrator intervention needed to complete onboarding workflow.

**Details:**

- **Failed Onboarding Recovery**: If partner onboarding fails during the automated MOSIP deployment, manual re-onboarding is required before proceeding to test rig deployment
- **Pre-Test Rig Requirements**: All pods must be verified as running and stable before triggering test rig deployments
- **Manual Verification Steps**: Administrator must check pod status across all namespaces (mosip, keycloak, postgres) before proceeding with test rigs

**Required Actions:**

1. Monitor deployment logs for onboarding failures
2. Execute manual re-onboarding procedures for failed cases
3. Verify all services are operational before test rig deployment
4. Ensure no pods remain in pending or error states

### 3. AWS Infrastructure Capacity

**Issue**: AWS may have insufficient instance capacity in specific availability zones for requested instance types.

**Symptoms:** "InsufficientInstanceCapacity" errors during EC2 instance creation.

### 4. Service Dependencies

**Issue**: Deployment success depends on external service availability.

**Critical Services:**

- GitHub (for Actions workflows and repository access)
- Let's Encrypt (for SSL certificate generation)

---

## Troubleshooting Guides

### Docker Registry Issues

**Error Examples:**

```
Error: ErrImagePull
Failed to pull image "docker.io/mosipid/pre-registration-batchjob:1.2.0.3": failed to pull and unpack image "docker.io/mosipid/pre-registration-batchjob:1.2.0.3": failed to copy: httpReadSeeker: failed open: unexpected status code https://registry-1.docker.io/v2/mosipid/pre-registration-batchjob/manifests/sha256:a934cab79ac1cb364c8782b56cfec987c460ad74acc7b45143022d97bb09626a: 429 Too Many Requests - Server message: toomanyrequests: You have reached your unauthenticated pull rate limit. https://www.docker.com/increase-rate-limit
```

**Solutions:**

1. **Docker Hub Authentication**: Configure Docker Hub credentials in your cluster
2. **Retry Deployments**: Re-run failed Helmsman deployments after waiting period
3. **Manual Pod Restart**: If any pod remains in "ContainerCreating" state for more than 3 minutes:

```bash
 # Delete the stuck pod to trigger recreation
 kubectl delete pod <pod-name> -n <namespace>

 # Check pod status
 kubectl get pods -n <namespace> -w
```

4. **Mirror Registries**: Use alternative container registries or mirrors
5. **Rate Limit Increase**: Consider Docker Hub paid plans for higher limits

### AWS Capacity Issues

**Error Example:**

```
Error: creating EC2 Instance: InsufficientInstanceCapacity: We currently do not have sufficient t3a.2xlarge capacity in the Availability Zone you requested (ap-south-1a). Our system will be working on provisioning additional capacity. You can currently get t3a.2xlarge capacity by not specifying an Availability Zone in your request or choosing ap-south-1b, ap-south-1c.
status code: 500, request id: 0b0423e2-0906-4096-a03c-41df5c00f5a8
```

**Solution**: Configure Terraform to use all available availability zones in `aws.tfvars`:

```hcl
# Specific availability zones for VM deployment (optional)
# If empty, uses all available AZs in the region
# Example: ["ap-south-1a", "ap-south-1b"] for specific AZs
# Example: [] for all available AZs in the region
specific_availability_zones = [] # Use empty array to allow all AZs
```

**Best Practice**: Always set `specific_availability_zones = []` to allow AWS to select from all available zones with capacity.

### Partner Onboarding

**Manual Steps Required**: Partner onboarding requires administrator intervention after initial Helmsman deployment.

**Solution**: Plan for manual partner onboarding steps in your deployment timeline.

**Documentation**: [MOSIP Partner Onboarding Guide](https://github.com/mosip/mosip-infra/tree/v1.2.0.2/deployment/v3/mosip/partner-onboarder)

### Service Status Verification

**Pre-deployment Checklist**: Verify essential services are operational before starting deployment.

**Required Service Status:**

- **GitHub Status**: [https://githubstatus.com](https://githubstatus.com) - Must be **GREEN**
- **Let's Encrypt Status**: [https://letsencrypt.status.io](https://letsencrypt.status.io) - Must be **GREEN**

**Deployment Impact**: Service outages can cause failures in:

- GitHub Actions workflows
- Repository access and downloads
- SSL certificate generation and renewal

**Action**: Wait for all services to show "All Systems Operational" before beginning deployment.

---

### Getting Help

- **GitHub Issues**: Report bugs and request features
- **Documentation**: Comprehensive guides in component directories
- **Community**: MOSIP community support channels

---

## License

This project is licensed under the [Mozilla Public License 2.0](LICENSE).

---

*For detailed technical documentation, refer to the component-specific README files linked above.*
