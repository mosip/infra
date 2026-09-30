<div align="left">
 <img src="docs/_images/MOSIP_Black.svg" alt="MOSIP Logo" width="200"/>
</div>

# MOSIP Rapid Deployment

This repository provides a **3-step rapid deployment model** for MOSIP (Modular Open Source Identity Platform) with enhanced security features including GPG (GNU Privacy Guard) encryption for local backends and integrated PostgreSQL setup via Terraform modules.

### Key Components:

- **Terraform** provisions cloud infrastructure on AWS — VPC, security groups, IAM, EC2, EBS, Route53 — one independent component (and state) at a time.
- **Ansible** configures the hosts — TLS + nginx, RKE2 Kubernetes, NFS, PostgreSQL, ActiveMQ, Rancher — identically on Terraform-provisioned AWS hosts and on pre-created data-centre VMs (no Terraform needed there).
- **Helmsman** deploys and manages all MOSIP services and applications on Kubernetes using Helm charts, providing centralized control through Desired State Files (DSF).

## Architecture Overview

For detailed MOSIP platform architecture Diagram, visit: [MOSIP Platform Architecture](https://docs.mosip.io/1.2.0/setup/deploymentnew/v3-installation/1.2.0.2/overview-and-architecture#architecture-diagram)

**Terraform Architecture (AWS):**
One root and one state per component, applied in order by `terraform.yml` (`COMPONENT=all`); each finds the previous layer by AWS tags, never shared state. More diagrams: [Architecture diagrams](docs/_images/ARCHITECTURE_DIAGRAMS.md).

```mermaid
%%{init: {'theme': 'neutral'}}%%
graph LR
    BI["base-infra<br/>VPC · subnets · WireGuard<br/>(once per account)"]
    PROF["profiles/&lt;profile&gt;/aws/*.tfvars"]
    subgraph ROOTS["terraform/implementations/aws/* — one state each"]
        direction LR
        SEC[security<br/>4 SGs] --> IAM["iam<br/>certbot role<br/>(zone-scoped)"] --> COMP["compute<br/>nginx + RKE2 EC2"] --> STO["storage<br/>EBS volumes"] --> DNS["dns<br/>Route53<br/>multi-zone"]
    end
    VM["vm<br/>standalone EC2 + SG + IAM<br/>(on demand)"]
    BI --> SEC
    BI --> VM
    PROF --> ROOTS
    PROF --> VM
    DNS --> CFG["configure<br/>Ansible site.yml"]
    STATE[("state per component · profile · branch<br/>GPG in git or S3")]
    ROOTS -.-> STATE

    classDef tf fill:none,stroke:#1976d2,stroke-width:2px
    classDef side fill:none,stroke:#ff8f00,stroke-width:2px
    classDef ans fill:none,stroke:#388e3c,stroke-width:2px
    class BI,SEC,IAM,COMP,STO,DNS,VM tf
    class PROF,STATE side
    class CFG ans
```

**Helmsman Architecture:**
[View Helmsman Architecture Diagram](docs/_images/updated-Helmsman.drawio.png)

**Ansible Architecture (AWS and data centre):**
Layer 3 is the same Ansible on both paths — only where the inventory comes from differs. Data-centre steps: [Data-centre deployment](docs/DATACENTRE_DEPLOYMENT.md).

```mermaid
%%{init: {'theme': 'neutral'}}%%
graph LR
    %% Where the hosts come from
    subgraph SRC["Hosts"]
        direction TB
        TF["AWS: Terraform<br/>security → iam → compute<br/>→ storage → dns"]
        DC["Data centre: pre-created VMs<br/>+ hosts.yml<br/>(DNS by DNS team)"]
    end

    PROF["profiles/&lt;profile&gt;/profile.yml<br/>components · subdomains · TLS mode"]

    TF -->|"terraform output<br/>compute + storage"| GEN
    DC -->|"generate.py --from-hosts"| GEN
    PROF --> GEN
    GEN["ansible/inventory/generate.py<br/>one inventory format"] --> INV[inventory.yml]

    %% site.yml — fixed legacy order; the profile only selects components
    INV --> SITE
    subgraph SITE["ansible/site.yml"]
        direction TB
        PF["preflight<br/>SSH · vars · disks · DNS check"] --> TLS["tls<br/>byo · http01 · dns01"]
        TLS --> NG[nginx]
        NG --> RK[rke2]
        RK --> RI["rancher import<br/>(optional)"]
        RI --> NFS[nfs]
        NFS --> PG["postgresql<br/>(profile)"]
        PG --> AMQ["activemq<br/>(profile)"]
        AMQ --> RKC["rancher + keycloak<br/>(observ profile)"]
    end

    SITE --> K8S["RKE2 cluster ready<br/>→ Helmsman"]

    classDef src fill:none,stroke:#1976d2,stroke-width:2px
    classDef gen fill:none,stroke:#ff8f00,stroke-width:2px
    classDef step fill:none,stroke:#388e3c,stroke-width:1px
    classDef done fill:none,stroke:#7b1fa2,stroke-width:2px
    class TF,DC src
    class PROF,GEN,INV gen
    class PF,TLS,NG,RK,RI,NFS,PG,AMQ,RKC step
    class K8S done
```

---

## Complete Deployment Flow

```mermaid
%%{init: {'theme': 'neutral'}}%%
graph TB
    %% Prerequisites
    A[Fork Repository] --> B[Configure Secrets]
    B --> C{Where do the<br/>hosts come from?}

    %% Infrastructure Phase
    C -->|AWS| D[Terraform: base-infra<br/>VPC, Networking, WireGuard]
    C -->|Data centre / any VMs| DCV[Pre-created VMs + hosts.yml<br/>DNS by DNS team<br/>Ansible only - no Terraform]
    DCV --> PS
    D --> OBS{Deploy<br/>Observability?}
    OBS -->|Yes| F[Terraform + Ansible<br/>profile: observ<br/>Rancher UI + Keycloak]
    OBS -->|No| PS
    F --> PS

    %% Profile selection (same profiles on AWS and data centre)
    PS{Select<br/>Profile}
    PS -->|esignet-standalone| TF_ES[Terraform + Ansible<br/>profile: esignet-standalone]
    PS -->|mosip| TF_MP[Terraform + Ansible<br/>profile: mosip]

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

    class A,B prereq
    class DCV terraform
    class D,F,TF_ES,TF_MP terraform
    class ES_EXT,ES_ESIGNET,ES_TRIGS helmsman
    class MP_EXT,MP_MOSIP,MP_ESIGNET,MP_TRIGS mosip
    class NS1,NS2,NS3,NS4 ns
    class V,DONE success
    class C,OBS,PS,MP_VER decision
```

> **Note:** Terraform provisioning is implemented for **AWS**. Azure and GCP have `base-infra` only. Any other environment — including data-centre VMs — is supported by the provider-agnostic Ansible layer without Terraform.

**Important:** If you deploy the `observ` profile (Rancher + Keycloak for platform management), you **must** run the Keycloak–Rancher SAML integration workflow after it completes and before deploying MOSIP clusters. This configures Keycloak as the identity provider for Rancher operator access. See [Step 3d](#step-3d-deploy-with-one-run).

**Data centres:** VMs you already have (no cloud API) use the same Ansible with no Terraform — see [Step 3e](#step-3e-data-centre-deployment-pre-created-vms-no-terraform).

## Prerequisites

**First Time Deploying? Start Here!**

We've created comprehensive beginner-friendly guides to help you succeed:

| Guide                                                                         | What You'll Learn                                                                          | When to Read                                        |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ | --------------------------------------------------- |
| **[Glossary](docs/GLOSSARY.md)**                                                                         | Plain-language explanations of all technical terms (AWS, Kubernetes, Terraform, VPN, etc.) | Before you start - understand the terminology            |
| **[Secret Generation Guide](docs/SECRET_GENERATION_GUIDE.md)**                                           | Step-by-step instructions to generate SSH keys, AWS credentials, GPG passwords, and more   | Before deployment - setup required secrets               |
| **[Workflow Guide](docs/WORKFLOW_GUIDE.md)**                                                             | Visual walkthrough of GitHub Actions workflows with screenshots and navigation help        | During deployment - run workflows correctly               |
| **[DSF Configuration Guide](docs/DSF_CONFIGURATION_GUIDE.md)**                                           | How to configure Helmsman files including clusterid and domain settings                    | Before Helmsman deployment - configure applications       |
| **[eSignet Standalone Deployment Guide](docs/ESIGNET_STANDALONE_DEPLOYMENT_GUIDE.md)**                   | End-to-end guide for eSignet standalone — Terraform infra provisioning, required AWS/GitHub secrets, tfvars setup, and Helmsman workflow order | eSignet standalone deployment |
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

> **Configuration Note:** Instance types are set per profile in `profiles/<profile>/aws/compute.tfvars` (`k8s_instance_type`, `nginx_instance_type`).

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
# Where to find: published automatically as this secret when ENABLE_RANCHER_IMPORT + PUBLISH_KUBECONFIG are set;
#   otherwise copy /home/ubuntu/.kube/<cluster_name>-CONTROL-PLANE-NODE-1.yaml from the primary control-plane node
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

> **Note**: PostgreSQL secrets are no longer required! External PostgreSQL is set up automatically by Ansible when the profile lists `postgresql` in `configure_components` (and, on AWS, `nginx_node_ebs_volume_size_2 > 0` in `storage.tfvars`).

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

### 3. Infrastructure Deployment (Terraform on AWS, or Ansible on your VMs)

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
 # Edit terraform/implementations/aws/base-infra/aws.tfvars (azure/gcp base-infra are placeholders)
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

> Screenshot from the previous workflow version — the form now shows `COMPONENT` (pick `base-infra`) and `PROFILE` (ignored for base-infra) instead of `TERRAFORM_COMPONENT` / `INFRA_PROFILE`.

- **(1)** Go to **Actions** → **terraform plan/apply**
  - **Can't find it?** Look in the left sidebar under "All workflows"
  - Click **Run workflow** (green button on the right)
  - **Configure workflow parameters:**
- **(2)** **Branch**: Select your deployment branch (e.g., `release-0.1.0`)
  - **What's this?** The branch of code to use for deployment
- **(3)** **Cloud Provider**: Select `aws` (Azure/GCP are placeholder implementations)
  - **Important**: Only `aws` is fully functional
- **(4)** **COMPONENT**: Select `base-infra` (creates VPC, networking, jump server, WireGuard)
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

#### Step 3c: Fill in a profile

Every deployment shape is a **profile** under [`profiles/`](profiles/) — see the [Profiles guide](docs/PROFILES.md):

| Profile | What it is |
|---------|------------|
| `mosip` | Full MOSIP platform (3 control-plane, 3 etcd, 1 worker; postgres + activemq volumes) |
| `esignet-standalone` | Standalone eSignet (1/1/2 nodes, no postgres/activemq volumes) |
| `observ` | Observability cluster: Rancher UI + Keycloak (1 node) — optional, deploy it first |

On your deployment branch, edit the files of the profile you'll use:

- `profiles/<profile>/aws/common.tfvars` — values every component shares:

  ```hcl
  cluster_name        = "soil38"             # must match ENV_NAME (GitHub environment variable)
  cluster_env_domain  = "soil38.mosip.net"   # must match DOMAIN_NAME
  mosip_email_id      = "ops@example.org"    # certbot expiry mails
  ssh_key_name        = "mosip-aws"          # AWS key pair; the SSH_PRIVATE_KEY secret must hold its private key
  aws_provider_region = "ap-south-1"
  zone_id             = "Z090954828SJIEL6P5406"
  ami                 = "ami-0ad21ae1d0696ad58"  # Ubuntu 24.04
  vpc_name            = "mosip-boxes"        # created by base-infra
  network_cidr        = "10.0.0.0/8"
  WIREGUARD_CIDR      = "10.0.0.0/8"
  ```

- `profiles/<profile>/aws/compute.tfvars` — instance types and node counts.
- `profiles/<profile>/aws/storage.tfvars` — data volumes on the nginx node. `nginx_node_ebs_volume_size_2 = 0` skips PostgreSQL, `nginx_node_ebs_volume_size_3 = 0` (or `enable_activemq_setup = false`) skips ActiveMQ.
- `profiles/<profile>/aws/dns.tfvars` — optional: extra hosted zones, extra records.
- `profiles/<profile>/profile.yml` — public / internal subdomains, which Layer-3 components run, the `k8s_infra_branch`, and the TLS mode.

#### Step 3d: Deploy with one run

- **(1)** Go to **Actions** → **terraform plan / apply** → **Run workflow**
- **(2)** **Branch**: your deployment branch
- **(3)** **CLOUD_PROVIDER**: `aws`
- **(4)** **COMPONENT**: `all`
- **(5)** **PROFILE**: `mosip`, `esignet-standalone` or `observ`
- **(6)** **BACKEND_TYPE**: `local` (GPG-encrypted state committed to the branch) or `remote`
- **(7)** **SSH_PRIVATE_KEY**: name of the secret holding the private key for `ssh_key_name`
- **(8)** ✅ **TERRAFORM_APPLY** (required for `all`)
- **(9)** **ENABLE_RANCHER_IMPORT**: tick to register the cluster in Rancher (needs `RANCHER_API_URL` / `RANCHER_API_TOKEN` secrets and an `observ` cluster)

`all` runs the components in the legacy order, each with its own state, stopping at the first failure:

```
security → iam → compute → storage → dns → configure (Ansible: nginx → rke2 → rancher import → nfs → postgresql → activemq)
```

To preview without changing anything, run a single component with **TERRAFORM_APPLY** unchecked (plan only). Every component can also be re-run on its own later — e.g. `COMPONENT=dns` to change only Route53 records, or `COMPONENT=configure` to re-run Ansible. See [Deployment sequence](docs/DEPLOYMENT_SEQUENCE.md).

**Observability cluster (`observ` profile):** deploy it before the clusters that import into its Rancher. Set the `RANCHER_BOOTSTRAP_PASSWORD` environment secret first — it's the initial `admin` password for Rancher UI (it's no longer kept in a tfvars file). Then run the Keycloak ⇄ Rancher SAML integration: see the **[Rancher-Keycloak Integration Guide](Rancher-keycloak-integration/README.md)**.

**Rancher import:** with **ENABLE_RANCHER_IMPORT** ticked, the workflow registers the cluster through the Rancher API, applies the import on the cluster, grants team access and (with **PUBLISH_KUBECONFIG**) stores the kubeconfig as the `KUBECONFIG` environment secret. No import URL goes into tfvars anymore.

**If a run fails:** open the failed job (each component is its own job), expand the red step, and fix the cause. Re-running the same dispatch is safe — components that already applied show no changes.

**Troubleshooting Rancher import:**

```bash
kubectl get pods -n cattle-system
kubectl logs -n cattle-system -l app=cattle-cluster-agent
# Common causes: no network path from the cluster to Rancher, firewall rules, expired import token
```

#### Step 3e: Data-centre deployment (pre-created VMs, no Terraform)

For VMs you already have (e.g. a country data centre), skip Terraform entirely. The same Ansible runs against them:

```bash
cp ansible/inventory/hosts.example.yml my-hosts.yml     # fill in IPs, disks, TLS mode
python3 ansible/inventory/generate.py --profile profiles/mosip --from-hosts my-hosts.yml -o inventory.yml
ansible-playbook -i inventory.yml ansible/site.yml
```

Create the DNS records first (your DNS team, or `COMPONENT=dns` if the domain is in Route53). TLS can be your own certificate, Let's Encrypt HTTP-01, or Let's Encrypt DNS-01 through any provider. Full guide — VM prerequisites, firewall ports, TLS options, troubleshooting: **[Data-centre deployment](docs/DATACENTRE_DEPLOYMENT.md)**.

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

Set this to match your profile: `false` when `profiles/<profile>/profile.yml` lists `postgresql` (external PostgreSQL on the nginx node), `true` otherwise. Everything else (host, port, credentials) is resolved automatically from environment variables and hooks.

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

 **Get the kubeconfig:**

- With **ENABLE_RANCHER_IMPORT** + **PUBLISH_KUBECONFIG** ticked, the deployment already stored it as the `KUBECONFIG` environment secret — nothing to do.
- Otherwise copy it from the primary control-plane node (over WireGuard). The server address in it is the node's private IP:

```bash
scp -i <ssh-key> ubuntu@<k8s_primary_control_plane_ip>:/home/ubuntu/.kube/<cluster_name>-CONTROL-PLANE-NODE-1.yaml kubeconfig
```

 **Add KUBECONFIG as Environment Secret:**

> **Important:** KUBECONFIG must be provided as **raw YAML** (plain text), not base64 encoded.

- Go to your GitHub repository → Settings → Environments
- Select or create environment for your branch (e.g., `release-0.1.0`, `main`, `develop`)
- Click "Add secret" under Environment secrets
- Name: `KUBECONFIG`
- Value: Copy the **entire raw YAML contents** of that kubeconfig file

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