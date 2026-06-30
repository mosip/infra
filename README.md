<div align="left">
 <img src="docs/_images/MOSIP_Black.svg" alt="MOSIP Logo" width="200"/>
</div>

# MOSIP Rapid Deployment

This repository provides a **3-step rapid deployment model** for MOSIP (Modular Open Source Identity Platform) with enhanced security features including GPG (GNU Privacy Guard) encryption for local backends and integrated PostgreSQL setup via Terraform modules.

### Key Components:

- **Terraform** provisions the complete cloud infrastructure including VPCs, RKE2 Kubernetes clusters, databases, and networking components with a high-level declarative approach.
- **Helmsman** deploys and manages all MOSIP services and applications on Kubernetes using Helm charts, providing centralized control through Desired State Files (DSF).

## Architecture Overview

For detailed MOSIP platform architecture Diagram, visit: [MOSIP Platform Architecture](https://docs.mosip.io/1.2.0/setup/deploymentnew/v3-installation/1.2.0.2/overview-and-architecture#architecture-diagram)

**Terraform Architecture:**
[View Terraform Architecture Diagram](docs/_images/terraform-light.draw.io.png)

**Helmsman Architecture:**
[View Helmsman Architecture Diagram](docs/_images/updated-Helmsman.drawio.png)

---

## Complete Deployment Flow

```mermaid
%%{init: {'theme': 'neutral'}}%%
graph TB
    %% Prerequisites
    A[Fork Repository] --> B[Configure Secrets]
    B --> C[Select Cloud Provider]

    %% Infrastructure Phase
    C --> D[Terraform: base-infra<br/>VPC, Networking, WireGuard]
    D --> OBS{Deploy<br/>Observability?}
    OBS -->|Yes| F[Terraform: observ-infra<br/>Rancher UI + Keycloak]
    OBS -->|No| PS
    F --> PS

    %% Terraform Profile Selection
    PS{Select Terraform<br/>Profile}
    PS -->|esignet-standalone| TF_ES[Terraform: infra<br/>profile: esignet-standalone]
    PS -->|mosip| TF_MP[Terraform: infra<br/>profile: mosip]

    %% ── eSignet Standalone Flow — Helmsman profile: esignet ─────
    TF_ES --> ES_EXT[Helmsman: Prereqs + External<br/>profile: esignet-standalone]
    ES_EXT --> ES_ESIGNET[Helmsman: eSignet Standalone<br/>4 parallel namespaces]

    ES_ESIGNET --> NS1[esignet mock plugin]
    ES_ESIGNET --> NS2[mosip-identity plugin]
    ES_ESIGNET --> NS4[sunbird-rc plugin]

    NS1 --> ES_TRIGS[Helmsman: Testrigs]
    NS2 --> ES_TRIGS
    NS4 --> ES_TRIGS

    %% ── MOSIP Platform Flow — Helmsman profile selection ────────
    TF_MP --> MP_VER{Helmsman<br/>Profile}
    MP_VER -->|mosip-platform-1.2.0.x| MP_EXT[Helmsman: Prereqs + External]
    MP_VER -->|mosip-platform-1.2.1.x| MP_EXT
    MP_EXT --> MP_MOSIP[Helmsman: MOSIP Core<br/>auto-triggered]
    MP_MOSIP --> MP_ESIGNET[Helmsman: eSignet<br/>with MOSIP platform]
    MP_ESIGNET --> MP_TRIGS[Helmsman: Testrigs]

    %% Final Verification
    ES_TRIGS --> V[Verify Deployment]
    MP_TRIGS --> V
    V --> DONE[Deployment Complete]

    %% Styling — transparent fills for readability in both light and dark themes
    classDef prereq fill:none,stroke:#ff8f00,stroke-width:2px
    classDef terraform fill:none,stroke:#1976d2,stroke-width:2px
    classDef helmsman fill:none,stroke:#7b1fa2,stroke-width:2px
    classDef mosip fill:none,stroke:#3949ab,stroke-width:2px
    classDef ns fill:none,stroke:#558b2f,stroke-width:1px
    classDef success fill:none,stroke:#388e3c,stroke-width:2px
    classDef decision fill:none,stroke:#c2185b,stroke-width:2px

    class A,B,C prereq
    class D,F,TF_ES,TF_MP terraform
    class ES_EXT,ES_ESIGNET,ES_TRIGS helmsman
    class MP_EXT,MP_MOSIP,MP_ESIGNET,MP_TRIGS mosip
    class NS1,NS2,NS3,NS4 ns
    class V,DONE success
    class OBS,PS,MP_VER decision
```

> **Note:** Complete Terraform scripts are available only for **AWS**. For **Azure and GCP**, only placeholder structures are configured - community contributions are welcome to implement full functionality.

**Important:** If you deploy `observ-infra` (Rancher + Keycloak for platform management), you **must** run the Keycloak–Rancher SAML integration workflow after `observ-infra` deployment completes and before deploying MOSIP infra. This configures Keycloak as the identity provider for Rancher operator access. See [Step 3cb: Keycloak ⇄ Rancher integration (CI)](#step-3cb-keycloak--rancher-integration-ci--if-using-observ-infra) section below for workflow details and how to trigger it.

## Prerequisites

**First Time Deploying? Start Here!**

We've created comprehensive beginner-friendly guides to help you succeed:

| Guide                                                                         | What You'll Learn                                                                          | When to Read                                        |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ | --------------------------------------------------- |
| **[Glossary](docs/GLOSSARY.md)**                                                                         | Plain-language explanations of all technical terms (AWS, Kubernetes, Terraform, VPN, etc.) | Before you start - understand the terminology            |
| **[Secret Generation Guide](docs/SECRET_GENERATION_GUIDE.md)**                                           | Step-by-step instructions to generate SSH keys, AWS credentials, GPG passwords, and more   | Before deployment - setup required secrets               |
| **[Workflow Guide](docs/WORKFLOW_GUIDE.md)**                                                             | Visual walkthrough of GitHub Actions workflows with screenshots and navigation help        | During deployment - run workflows correctly               |
| **[DSF Configuration Guide](docs/DSF_CONFIGURATION_GUIDE.md)**                                           | How to configure Helmsman files including clusterid and domain settings                    | Before Helmsman deployment - configure applications       |
| **[eSignet Standalone Deployment Guide](docs/ESIGNET_STANDALONE_DEPLOYMENT_GUIDE.md)**                   | Step-by-step guide to deploy eSignet standalone via GitHub Actions — secrets, variables, workflow order | eSignet standalone deployment |
| **[Environment Destruction Guide](docs/ENVIRONMENT_DESTRUCTION_GUIDE.md)**                               | Safe teardown procedures, backup steps, and cost monitoring                                | After deployment - clean up resources                    |

**Complete Documentation Index:** [View All Documentation](docs/README.md)

> **Note:** As of now we support AWS based automated deployment. We are looking for community contribution around terraform modules and changes for other cloud service providers.

> **Important for Beginners**: Start with AWS deployment only. Azure and GCP implementations are not yet complete. You'll need:
>
> - An AWS account ([Create one here](https://aws.amazon.com/free/))
> - Basic understanding of cloud concepts ([See our Glossary](docs/GLOSSARY.md))
> - GitHub account for running automated workflows

1. ### Cloud Provider Account (Required)

- **AWS account** with appropriate permissions (fully supported) - [How to create AWS account](https://aws.amazon.com/premiumsupport/knowledge-center/create-and-activate-aws-account/)
- Azure or GCP account (placeholder implementations - community contributions needed)
- Service account/access keys with infrastructure creation rights

2. ### AWS Permissions (Required)

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

3. ### AWS Instance Types (Required)

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

4. ### Secrets for Rapid Deployment (Required)

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

# GitHub Personal Access Token
GH_INFRA_PAT: "github_pat_..."
# What it's for: Required for repository operations during deployment
# How to get: GitHub Settings → Developer Settings → Personal access tokens (Fine-grained)
# Permissions Required:
# - Contents: Read and write (critical, Read only causes 403 on push)
# - Metadata: Read
# - Actions: Read and write
# - Environments: Read and write
# - Variables: Read and write
# NOTE: No Secrets permission needed (intentionally excluded)

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
- [ ] GitHub PAT (GH_INFRA_PAT) generated with correct permissions
- [ ] SSH key pair generated (public + private)
- [ ] SSH public key uploaded to AWS EC2 Key Pairs
- [ ] SSH private key added to GitHub secrets
- [ ] All secret names match exactly (case-sensitive!)

**Need step-by-step help?** [Secret Generation Guide](docs/SECRET_GENERATION_GUIDE.md)

**Environment Secrets** (configured per deployment environment):

```yaml
# WireGuard VPN (required - for infrastructure access & Keycloak-Rancher integration)
TF_WG_CONFIG: |
 [Interface]
 PrivateKey = terraform-private-key
 Address = 10.0.1.2/24
 
 [Peer]
 PublicKey = server-public-key
 Endpoint = your-server:51820
 AllowedIPs = 10.0.0.0/16
# NOTE: TF_WG_CONFIG is REQUIRED for the keycloak-rancher-integration workflow
# to access private Keycloak and Rancher instances. Configure this after base-infra deployment.

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
- `GH_INFRA_PAT` 
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
 # Edit terraform/implementations/aws/base-infra/aws.tfvars (or azure/gcp)
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
  - **What's this?** Select which infrastructure component to build.
  - Selecting `base-infra` triggers the creation of the core infrastructure components listed below:
    - **VPC & Networking**: Secure network foundation
    - **Jump Server**: Bastion host for secure access
    - **WireGuard VPN**: Encrypted private network access
    - **Security Groups**: Network access controls
    - **Route Tables**: Network traffic routing
- **Backend**: Choose backend configuration:
  - **(5)** `local` - GPG-encrypted local state (recommended for development)
    - Stores state in your GitHub repository (encrypted)
  - **(6)** `s3` - Remote S3 backend (If you want to store the state file in a S3 bucket, provide the bucket name. Otherwise, leave it empty to use the local backend)
    - Stores state in AWS S3 bucket (centralized)
- **(7)** **SSH_PRIVATE_KEY**: GitHub secret name containing SSH private key for instance access
  - Must match the `ssh_key_name` in your terraform.tfvars
- **Terraform apply**:
  - **(8)** ☐ **Unchecked**  — Plan mode: runs terraform plan (shows changes without applying).
  - **(8)** ✅ **Checked**  — Apply mode: runs terraform apply (creates/updates infrastructure).
  - Tip: For your first deployment, run in plan mode first to review changes. If the plan looks correct, re-run the workflow with Apply checked.
- **(9)** **Run Workflow**

 **What You Should See:**

- ✅ Workflow running (yellow circle icon)
- ✅ Steps completing one by one
- ✅ Green checkmark when complete
- ✅ Infrastructure created in AWS

 **If Workflow Fails - How to View Error Logs:**

1. Click on the **failed workflow run** (red ❌ icon)
2. Click on the **failed job** in the left sidebar
3. Expand the **failed step** (look for red ❌) to see detailed error logs
4. Common steps to check:
   - `Terraform Init` - Backend/provider issues
   - `Terraform Plan` - Configuration or syntax errors
   - `Terraform Apply` - Resource creation failures
5. Scroll through the logs to find the error message (usually highlighted in red)
6. For full logs, click **View raw logs** (gear icon → "View raw logs")

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

- `TF_WG_CONFIG` - For Terraform infrastructure deployments (peer1)
- `CLUSTER_WIREGUARD_WG0` - For Helmsman cluster access (peer2)
- `CLUSTER_WIREGUARD_WG1` - For Helmsman cluster access (peer3, optional)
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

> **Important:** Complete WireGuard setup and configure `TF_WG_CONFIG` environment secret before proceeding to MOSIP infrastructure deployment.
>
> **Need help?** Check the [detailed WireGuard guide](terraform/base-infra/WIREGUARD_SETUP.md) with screenshots!

#### Step 3ca: Observation Infrastructure (observ-infra) — Optional

This step creates the optional Rancher + Keycloak management cluster for observability, monitoring, and operator identity management. **Skip this step if you don't need a separate observation plane.**

1. **Update observ-infra variables in `terraform/implementations/aws/observ-infra/aws.tfvars`:**

 Complete configuration example with detailed explanations:

```hcl
 # Environment name (observ-infra component)
 cluster_name = "soil38-observ"
 # Observation infrastructure domain (ex: sandbox-observ.xyz.net)
 cluster_env_domain = "soil38-observ.mosip.net"
 # Email-ID will be used by certbot to notify SSL certificate expiry via email
 mosip_email_id = "chandra.mishra@technoforte.co.in"
 # SSH login key name for AWS node instances (ex: my-ssh-key)
 ssh_key_name = "mosip-aws"
 # The AWS region for resource creation
 aws_provider_region = "ap-south-1"

 # Specific availability zones for VM deployment (optional)
 specific_availability_zones = ["ap-south-1b"]

 # The instance type for Kubernetes nodes (typically smaller for observ-infra)
 k8s_instance_type = "t3a.xlarge"
 # The instance type for Nginx server (load balancer)
 nginx_instance_type = "t3a.xlarge"
 # The Route 53 hosted zone ID
 zone_id = "Z090954828SJIEL6P5406"

 ## UBUNTU 24.04
 # The Amazon Machine Image ID for the instances
 ami = "ami-0ad21ae1d0696ad58"

 # Repo K8S-INFRA URL
 k8s_infra_repo_url = "https://github.com/mosip/k8s-infra.git"
 # Repo K8S-INFRA branch
 k8s_infra_branch = "v1.2.1.0"
 # NGINX Node's Root volume size
 nginx_node_root_volume_size = 24
 # NGINX node's EBS volume size
 nginx_node_ebs_volume_size = 200

 # Control-plane, ETCD, Worker (smaller cluster for observ-infra)
 k8s_control_plane_node_count = 2
 # ETCD, Worker
 k8s_etcd_node_count = 2
 # Worker
 k8s_worker_node_count = 1

 # RKE2 Version Configuration
 rke2_version = "v1.28.9+rke2r1"

 # Rancher Import Configuration (optional)
 enable_rancher_import = false

 # Security group CIDRs
 network_cidr = "10.0.0.0/8"
 WIREGUARD_CIDR = "10.0.0.0/8"

 # DNS Records to map
 subdomain_public = ["rancher", "keycloak"]
 subdomain_internal = ["admin", "monitoring", "logging"]

 # VPC Configuration - Existing VPC to use (discovered by Name tag)
 vpc_name = "mosip-boxes"
```

2. **Run observ-infra via GitHub Actions:**

- **(1)** Go to **Actions** → **terraform plan/apply**
- **(2)** Click **Run workflow**
- **(3)** **Branch**: Select your deployment branch (e.g., `release-0.2.0`)
- **(4)** **Cloud Provider**: Select `aws`
- **(5)** **Component**: Select `observ-infra` (creates Rancher management cluster + Keycloak)
- **(6)** **Backend**: Choose backend configuration:
  - `local` - GPG-encrypted local state (recommended for development)
  - `s3` - Remote S3 backend (recommended for production)
- **(7)** **SSH_PRIVATE_KEY**: GitHub secret name containing SSH private key for instance access
- **Terraform apply**:
  - **(8)** ☐ **Unchecked**  — Plan mode: runs terraform plan (shows changes without applying).
  - **(8)** ✅ **Checked**  — Apply mode: runs terraform apply (creates/updates infrastructure).
- **(9)** **Run Workflow**

**What You Should See:**

- ✅ Workflow running (yellow circle icon)
- ✅ Steps completing one by one
- ✅ Green checkmark when complete
- ✅ Observation infrastructure created in AWS with Rancher and Keycloak

**If Workflow Fails - How to View Error Logs:**

1. Click on the **failed workflow run** (red ❌ icon)
2. Click on the **failed job** in the left sidebar
3. Expand the **failed step** (look for red ❌) to see detailed error logs
4. Common steps to check:
   - `Terraform Init` - Backend/provider issues
   - `Terraform Plan` - Configuration or syntax errors
   - `Terraform Apply` - Resource creation failures
5. Scroll through the logs to find the error message (usually highlighted in red)
6. For full logs, click **View raw logs** (gear icon → "View raw logs")

**Post-Deployment: Rancher UI Initial Setup**

After `observ-infra` deployment completes, perform the initial Rancher UI setup:

1. **Access Rancher UI:**
   - Open your browser and navigate to the Rancher domain configured in `aws.tfvars`
   - Example: `https://rancher.soil38-observ.mosip.net`

2. **Bootstrap Login:**
   - Enter the default bootstrap password: `admin`
   - Click **Log in**

3. **Set New Password:**
   - You will be prompted to set a new password
   - Enter a strong password and confirm
   - Click **Continue**

4. **Complete Setup:**
   - Accept the terms and conditions
   - Rancher UI is now ready for use

> **Important:** Save this new password securely. This password is used for **local user login** to Rancher UI (the `admin` account). After Keycloak-Rancher SAML integration is configured, operators can also login via Keycloak authentication.

> **Important Notes:**
>
> - `observ-infra` is optional and intended for production deployments requiring separate management/monitoring infrastructure
> - Recommended node sizes are smaller than main infra (t3a.xlarge vs t3a.2xlarge) to reduce costs
> - Keycloak in this cluster hosts operator/admin identities; back up before destructive operations
> - Rancher manages clusters; ensure main infra is properly configured before registering with Rancher

#### Step 3cb: Keycloak ⇄ Rancher integration (CI) — If using `observ-infra`

If you deployed `observ-infra` (Rancher + Keycloak for platform management), run the automated Keycloak–Rancher SAML integration workflow **after `observ-infra` deployment completes and before deploying MOSIP infra**. This configures Keycloak as the identity provider for Rancher operator access.

For complete workflow usage instructions, inputs, secrets configuration, and troubleshooting, see **[Rancher-Keycloak Integration Guide](Rancher-keycloak-integration/README.md)**.

#### Step 3d: MOSIP Infrastructure

This step creates MOSIP Kubernetes cluster, PostgreSQL (if enabled), ActiveMQ (if enabled), networking, and application infrastructure

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
 # NGINX node's third EBS volume size (optional - set to 0 to disable)
 nginx_node_ebs_volume_size_3 = 100 # Enable third EBS volume for ActiveMQ storage
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

 # ActiveMQ Configuration (optional, used when third EBS volume is enabled)
 enable_activemq_setup = true # Enable ActiveMQ persistent storage for main infra
 activemq_storage_device = "/dev/nvme3n1"
 activemq_mount_point = "/srv/activemq"
 activemq_nfs_allowed_hosts = "*" # Hosts allowed to mount NFS export (use CIDR/IP range for production, e.g., "10.0.0.0/8")

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
| `enable_activemq_setup`        | ActiveMQ persistent storage setup          | `true` (provisioned) / `false` (skipped) |
| `nginx_node_ebs_volume_size_3` | EBS volume size for ActiveMQ data (GB)     | `100`                                     |
| `vpc_name`                     | Existing VPC name tag to use               | `"mosip-boxes"`                           |

> **Important Notes:**
>
> - Ensure `cluster_name` and `cluster_env_domain` match `ENV_NAME` and `DOMAIN_NAME` set as GitHub Environment Variables — these drive all Helmsman DSF domain substitution
> - Set `enable_postgresql_setup = true` for production deployments with external PostgreSQL,If enable_postgresql_setup = true, Terraform will automatically:
>   - Provision dedicated EBS volume for PostgreSQL on nginx node
>   - Install and configure PostgreSQL 15 via Ansible playbooks
>   - Setup security configurations and user access controls
>   - Configure backup and recovery mechanisms
>   - Make PostgreSQL ready for MOSIP services connectivity
>   - No manual PostgreSQL secret management required!

> - Set `enable_postgresql_setup = false` for development deployments with containerized PostgreSQL
> - The `nginx_node_ebs_volume_size_2` is required when `enable_postgresql_setup = true`
> - **ActiveMQ Setup**: ActiveMQ installation is optional. To enable it, set `enable_activemq_setup = true` and ensure `nginx_node_ebs_volume_size_3 > 0` in `aws.tfvars`. It automatically provisions durable NFS-backed persistent storage via a dedicated EBS volume on the NGINX node.
> - **SSH Key Configuration**: The `ssh_key_name` value must match the repository secret name containing your SSH private key (e.g., if `ssh_key_name = "mosip-aws"`, create repository secret named `mosip-aws` with your SSH private key content)

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

**Step 2: Update aws.tfvars**

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

**Step 3: Deploy/Update Main Infra**

After updating `aws.tfvars`, deploy or update your main infra cluster:

2. **Run main infra via GitHub Actions:**

![Infrastructure Terraform Apply](docs/_images/infra-terraform-apply.png)

- **(1)** Go to **Actions** → **terraform plan/apply**
- **(2)** Click **Run workflow**
- **(3)** **Branch**: Select your deployment branch (e.g., `release-0.1.0`)
- **(4)** **Cloud Provider**: Select `aws` (Azure/GCP are placeholder implementations)
- **(5)** **Component**: Select `infra` (MOSIP application infrastructure)
- **(6)** **Profile**: Select `mosip`/`esignet` (Select profile which you want to use for deployment)
- **Backend**: Choose backend configuration:
  - **(7)** `local` - GPG-encrypted local state (recommended for development)
  - **(8)** `s3` - Remote S3 backend (If you want to store the state file in a S3 bucket, provide the bucket name. Otherwise, leave it empty to use the local backend)
- **(9)** **SSH_PRIVATE_KEY**: GitHub secret name containing SSH private key for instance access
  - Must match the `ssh_key_name` in your terraform.tfvars
- **(10)** **☐ Terraform apply**:
  - ☐ **Unchecked**  — Plan mode: runs terraform plan (shows changes without applying).
  - ✅ **Checked**  — Apply mode: runs terraform apply (creates/updates infrastructure).
  - Tip: For your first deployment, run in plan mode first to review changes. If the plan looks correct, re-run the workflow with Apply checked.
- **(11)** **Run Workflow**

**If Workflow Fails - How to View Error Logs:**

1. Click on the **failed workflow run** (red ❌ icon)
2. Click on the **failed job** in the left sidebar
3. Expand the **failed step** (look for red ❌) to see detailed error logs
4. Common steps to check:
   - `Terraform Init` - Backend/provider issues
   - `Terraform Plan` - Configuration or syntax errors
   - `Terraform Apply` - Resource creation failures
5. Scroll through the logs to find the error message (usually highlighted in red)
6. For full logs, click **View raw logs** (gear icon → "View raw logs")

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

#### Step 4a: Configure GitHub Environment Variables

**No manual DSF file edits are required per environment.** All domain, cluster, port, and environment name values are resolved at deploy time via Helmsman's `${VAR}` substitution.

**How values are provided:**

When you trigger a Helmsman workflow manually (`workflow_dispatch`), you enter these values directly as **workflow inputs** — no pre-configuration needed. The GitHub Environment (`<branch-name>`) must already exist (created automatically when Terraform runs or manually via Repository → Settings → Environments).

For **push-triggered runs** (no workflow inputs), values fall back to GitHub Environment Variables. In that case, navigate to **Repository → Settings → Environments → `<branch-name>` → Variables** and add:

| Variable | Example value | Used by |
|----------|--------------|---------|
| `DOMAIN_NAME` | `soil38.mosip.net` | All DSFs — hostnames, Istio VS, DB hosts |
| `ENV_NAME` | `soil38` | Landing page, testrig user |
| `CLUSTER_ID` | `c-m-abc12xyz` | `prereq-dsf.yaml` — rancher-monitoring |
| `SLACK_CHANNEL_NAME` | `#mosip-alerts` | `prereq-dsf.yaml` — alerting |
| `DB_PORT` | `5433` | MOSIP platform external postgres port |
| `ESIGNET_DB_PORT` | `5432` | eSignet container postgres port |

> **Domain consistency**: `DOMAIN_NAME` must match `cluster_env_domain` in `aws.tfvars`. `ENV_NAME` must match `cluster_name`. No in-file replacements needed.

**Finding your clusterid (for `CLUSTER_ID`):**
- **Rancher UI**: Open your cluster → the URL contains `c-m-xxxxx` — that's your clusterid
- **kubectl**: `kubectl get setting cluster-id -n cattle-system -o jsonpath='{.value}'`
- Only needed if `rancher_import = true` in your Terraform config

**Alerting (Slack) setup:**

Create a Slack incoming webhook ([guide](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks/)), then add:
- `SLACK_CHANNEL_NAME` variable (e.g. `#mosip-alerts`)
- `SLACK_WEBHOOK_URL` environment secret

**reCAPTCHA keys (MOSIP platform profiles):**

📖 **[View detailed reCAPTCHA Setup Guide](docs/RECAPTCHA_SETUP_GUIDE.md)**

Create reCAPTCHA v2 keys for each domain at [Google reCAPTCHA Admin](https://www.google.com/recaptcha/admin/create), then add as **Environment Secrets**:

| Secret | Domain |
|--------|--------|
| `PREREG_CAPTCHA_SITE_KEY` / `PREREG_CAPTCHA_SECRET_KEY` | `prereg.your-domain.net` |
| `ADMIN_CAPTCHA_SITE_KEY` / `ADMIN_CAPTCHA_SECRET_KEY` | `admin.your-domain.net` |
| `RESIDENT_CAPTCHA_SITE_KEY` / `RESIDENT_CAPTCHA_SECRET_KEY` | `resident.your-domain.net` |

The `external-dsf.yaml` reads these via `${PREREG_CAPTCHA_SITE_KEY}` etc. — no DSF edits needed.

**PostgreSQL configuration:**

The only DSF setting that still requires a manual decision is `postgres.enabled` in `external-dsf.yaml`:

```yaml
apps:
  postgres:
    enabled: false  # false = use external Terraform-provisioned PostgreSQL
                    # true  = deploy container PostgreSQL (for dev/test)
```

Set this to match your Terraform `enable_postgresql_setup` value. Everything else (host, port, credentials) is resolved automatically from environment variables and hooks.

**Database branch (MOSIP platform):**

```yaml
# In mosip-dsf.yaml — update to match your MOSIP version
gitRepo:
  dbBranch: "v1.2.0.2"   # must match your deployed MOSIP chart versions
```

**What you should NOT edit manually in DSF files:**
- Domain names or cluster names (use `vars.DOMAIN_NAME` / `vars.ENV_NAME`)
- Keycloak hostnames (derived from `${domain_name}`)
- eSignet service URLs (derived from `${domain_name}`)
- Test rig endpoints (derived from `${domain_name}`)
- Captcha keys (passed as GitHub Secrets via `${VAR}` substitution)

**Need detailed help?** [DSF Configuration Guide](docs/DSF_CONFIGURATION_GUIDE.md)

#### Step 4b: Configure Repository Secrets for Helmsman

Configure the required secrets for Helmsman deployments in **Repository → Settings → Environments → `<branch-name>` → Secrets**:

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

> **Important:** KUBECONFIG must be provided as **raw YAML** (plain text), not base64 encoded.

- Go to your GitHub repository → Settings → Environments
- Select or create environment for your branch (e.g., `release-0.1.0`, `main`, `develop`)
- Click "Add secret" under Environment secrets
- Name: `KUBECONFIG`
- Value: Copy the **entire raw YAML contents** of the kubeconfig file from `terraform/implementations/aws/infra/kubeconfig_<cluster-name>`

 **Branch Environment Configuration:- Ensure the environment name matches your deployment branch

- Configure environment protection rules if needed
- Verify Helmsman workflows reference the correct environment

3. **Required Environment Secrets for Helmsman:**

 **Environment Secrets (branch-specific):**

```yaml
 # Kubernetes Access (Environment Secret - raw YAML format)
 KUBECONFIG: |
   apiVersion: v1
   clusters:
   - cluster:
       certificate-authority-data: LS0tLS...
       server: https://your-cluster-endpoint:6443
     name: default
   contexts:
   - context:
       cluster: default
       user: default
     name: default
   current-context: default
   kind: Config
   users:
   - name: default
     user:
       client-certificate-data: LS0tLS...
       client-key-data: LS0tLS...

 # WireGuard Cluster Access for Helmsman
 CLUSTER_WIREGUARD_WG0: "peer2-wireguard-config" # Helmsman cluster access (peer2)
 CLUSTER_WIREGUARD_WG1: "peer3-wireguard-config" # Helmsman cluster access (peer3)

 # eSignet Required Secrets (Environment Secrets)
 # Configure in Repository → Settings → Environments → <branch-name> → Add secret
 
 MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY: | # Client private key for Mock Relying Party
   LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0t... # Base64 encoded PEM format
   
 MOCK_RELYING_PARTY_JWE_PRIVATE_KEY: | # JWE userinfo encryption private key
   LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0t... # Base64 encoded PEM format
   
 ESIGNET_CAPTCHA_SITE_KEY: "6LfkAMwrAAAAAATB1WhkIhzuAVMtOs9VWabODoZ_" # Google reCAPTCHA site key (plain text)
 ESIGNET_CAPTCHA_SECRET_KEY: "6LfkAMwrAAAAAHQAT93nTGcLKa-h3XYhGoNSG-NL" # Google reCAPTCHA secret key (plain text)
```

> **For detailed eSignet secrets configuration and generation instructions**, see [eSignet Deployment Guide - Required Secrets](docs/esignet_README.md#required-secrets-environment-secrets)

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

> **Always use `apply` mode.** The `dry-run` mode will fail because MOSIP services reference ConfigMaps and Secrets from other namespaces that don't exist at dry-run time.

Follow the sequence below. The flow differs by profile:

**eSignet standalone:**
```
External + Prereqs  →  eSignet (manual)  →  Signup (auto)  →  Testrigs (manual)
```

**MOSIP platform:**
```
External + Prereqs  →  MOSIP (auto)  →  eSignet (manual)  →  Testrigs (manual)
```

| Step | Workflow | Trigger | Profile | Guide |
|------|----------|---------|---------|-------|
| 1 | External + Prereqs | Manual | All profiles | [HELMSMAN_EXTERNAL_GUIDE.md](docs/HELMSMAN_EXTERNAL_GUIDE.md) |
| 2 | MOSIP services | Auto (from step 1) | MOSIP platform only | [HELMSMAN_MOSIP_GUIDE.md](docs/HELMSMAN_MOSIP_GUIDE.md) |
| 3 | eSignet | Manual | MOSIP platform | [esignet_README.md](docs/esignet_README.md) |
| | | | Standalone (4 instances) | [ESIGNET_STANDALONE_DEPLOYMENT_GUIDE.md](docs/ESIGNET_STANDALONE_DEPLOYMENT_GUIDE.md) |
| 4 | Testrigs | Manual | All profiles | [HELMSMAN_TESTRIGS_GUIDE.md](docs/HELMSMAN_TESTRIGS_GUIDE.md) |

Each guide covers: profile-specific secrets, workflow inputs, step-by-step run instructions, and verification commands.

### 7. Verify Deployment

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

For safe teardown and cleanup procedures:

- **Infrastructure Destruction**: [Environment Destruction Guide](docs/ENVIRONMENT_DESTRUCTION_GUIDE.md) - Complete Terraform-based infrastructure cleanup
- **Helmsman Services Destruction**: [Helmsman Destroy Guide](docs/HELMSMAN_DESTROY_GUIDE.md) - Safe removal of MOSIP services from Kubernetes without removing infrastructure

---

## Next Steps & Detailed Documentation

The Deployment Steps Guide provides the essential deployment flow. For comprehensive configuration options, troubleshooting, and advanced features, refer to the detailed component documentation:

#### **Terraform Infrastructure Documentation**

- **Location**: [`terraform/README.md`](terraform/README.md)
- **Contents**: Detailed variable explanations, multi-cloud configurations, state management, security best practices
- **Use Cases**: Custom infrastructure configurations, production deployments, troubleshooting infrastructure issues

#### **Helmsman Deployment Documentation**

| Guide | Purpose |
|-------|---------|
| [HELMSMAN_EXTERNAL_GUIDE.md](docs/HELMSMAN_EXTERNAL_GUIDE.md) | Deploy prereqs + external services (step 1 for all profiles) |
| [HELMSMAN_MOSIP_GUIDE.md](docs/HELMSMAN_MOSIP_GUIDE.md) | Deploy MOSIP core services + partner onboarding (MOSIP platform profiles) |
| [esignet_README.md](docs/esignet_README.md) | Deploy eSignet with MOSIP platform |
| [ESIGNET_STANDALONE_DEPLOYMENT_GUIDE.md](docs/ESIGNET_STANDALONE_DEPLOYMENT_GUIDE.md) | Deploy eSignet standalone (4 parallel instances) |
| [HELMSMAN_TESTRIGS_GUIDE.md](docs/HELMSMAN_TESTRIGS_GUIDE.md) | Deploy API/UI/DSL testrigs (all profiles) |
| [DSF_CONFIGURATION_GUIDE.md](docs/DSF_CONFIGURATION_GUIDE.md) | DSF structure, profile selection, variable substitution reference |
| [HELMSMAN_DESTROY_GUIDE.md](docs/HELMSMAN_DESTROY_GUIDE.md) | Safe removal of deployed services |

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