# Secret Generation and Configuration Guide

This guide provides step-by-step instructions for generating all required secrets for MOSIP deployment. Each section explains what the secret is for, how to generate it, and where to use it.

## Table of Contents

1. [SSH Keys](#1-ssh-keys)
2. [GPG Passphrase](#2-gpg-passphrase)
3. [AWS Credentials](#3-aws-credentials)
4. [WireGuard VPN Configuration](#4-wireguard-vpn-configuration)
5. [Kubernetes Config (KUBECONFIG)](#5-kubernetes-config-kubeconfig)
6. [reCAPTCHA Keys](#6-recaptcha-keys)
7. [How to Add Secrets to GitHub](#how-to-add-secrets-to-github)

---

## 1. SSH Keys

### What is it?
SSH (Secure Shell) keys are used to securely connect to your servers without using passwords. You need an SSH key pair to access EC2 instances created by Terraform.

### Why do you need it?
- To access jump servers and Kubernetes nodes
- For automated deployments via GitHub Actions
- For troubleshooting and maintenance tasks

### Two Approaches to Setup SSH Keys

You can use **either** approach below. **We recommend Option A** for simplicity.

---

### ✅ **Option A: Create Key Pair in AWS (Recommended - Simpler)**

This is the easiest approach - AWS creates the key pair for you.

#### Steps:

1. **Create Key Pair in AWS Console**
   ```
   1. Go to AWS Console → EC2 → Key Pairs
   2. Click "Create key pair"
   3. Name: mosip-aws (or your preferred name)
   4. Key pair type: RSA
   5. Private key format: .pem
   6. Click "Create key pair"
   7. AWS will automatically download the .pem file - SAVE THIS FILE SECURELY!
   ```

2. **Add Private Key (.pem) to GitHub Secrets**
   ```bash
   # View the content of your downloaded .pem file:
   cat ~/Downloads/mosip-aws.pem
   
   # Copy the entire content (including BEGIN and END lines)
   # Add as Repository Secret in GitHub:
   # - Name: mosip-aws (must match the key pair name you created)
   # - Value: (paste the entire .pem file content)
   ```

3. **Update Terraform Configuration**
   ```hcl
   # In terraform/implementations/aws/infra/aws.tfvars
   ssh_key_name = "mosip-aws" # Must match the AWS key pair name
   ```

#### ✅ Advantages:
- Simpler - only 3 steps
- No need to generate keys locally
- No need to import public key to AWS
- AWS manages the key pair for you

---

### **Option B: Generate Locally and Import to AWS**

This approach gives you more control over key generation.

#### On Linux/Mac:

```bash
# Open terminal and run:
ssh-keygen -t rsa -b 4096 -C "your-email@example.com" -f ~/.ssh/mosip-aws

# This creates two files:
# - ~/.ssh/mosip-aws (private key - keep this SECRET)
# - ~/.ssh/mosip-aws.pub (public key - safe to share)
```

#### On Windows:

**Using Git Bash or WSL:**
```bash
ssh-keygen -t rsa -b 4096 -C "your-email@example.com" -f ~/.ssh/mosip-aws
```

**Using PuTTYgen:**
1. Download and install [PuTTY](https://www.putty.org/)
2. Open PuTTYgen
3. Click "Generate" and move mouse randomly
4. Set key passphrase (optional but recommended)
5. Save private key (keep secret)
6. Copy public key text for AWS

#### Import to AWS:
```bash
# Upload the PUBLIC key to AWS:
1. Go to AWS Console → EC2 → Key Pairs
2. Click "Actions" → "Import key pair"
3. Name it (e.g., "mosip-aws")
4. Paste contents of ~/.ssh/mosip-aws.pub
5. Click "Import"
```

#### Add Private Key to GitHub Secrets:
```bash
# Copy private key content
cat ~/.ssh/mosip-aws

# Add as Repository Secret in GitHub:
# Name: mosip-aws (must match ssh_key_name in terraform.tfvars)
# Value: (paste the entire private key including BEGIN and END lines)
```

#### Update Terraform Configuration:
```hcl
# In terraform/implementations/aws/infra/aws.tfvars
ssh_key_name = "mosip-aws" # Must match the name in AWS and GitHub secret
```

---

### Official Documentation
- **AWS EC2 Key Pairs**: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/create-key-pairs.html
- **GitHub SSH Guide**: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent

### Common Pitfalls
- ❌ Using the public key as GitHub secret (use private key or .pem file!)
- ❌ Mismatched names between AWS key pair name, GitHub secret name, and ssh_key_name in tfvars
- ❌ Losing the .pem file after downloading (cannot be re-downloaded from AWS)
- ❌ Not including BEGIN/END lines when copying private key
- ❌ Adding extra spaces or newlines when pasting key

---

## 2. GPG Passphrase

### What is it?
GPG (GNU Privacy Guard) is used to encrypt sensitive Terraform state files when using local backend storage.

### Why do you need it?
- To encrypt Terraform state files that contain sensitive information
- To prevent unauthorized access to infrastructure secrets
- Required when using `local` backend option

### How to Generate

**Choose a strong passphrase that:**
- Is at least 16 characters long
- Contains uppercase and lowercase letters
- Contains numbers and special characters
- Is unique (not used elsewhere)
- Is memorable (you may need it for recovery)

**Example Strong Passphrase:**
```
MyM0s1p$ecur3!2024Deploy
```

**Password Generation Tools:**
- Online: https://www.random.org/passwords/
- Command line (Linux/Mac): `openssl rand -base64 32`
- Password managers: 1Password, LastPass, Bitwarden

### Official Documentation
- **GPG Official Guide**: https://gnupg.org/gph/en/manual/c14.html

### Where to Use It
Add as **Repository Secret** in GitHub:
- **Name**: `GPG_PASSPHRASE`
- **Value**: Your generated passphrase

### Common Pitfalls
- ❌ Using a weak/short passphrase
- ❌ Forgetting the passphrase (store it in a password manager!)
- ❌ Sharing the passphrase in insecure locations

---

## 3. AWS Credentials

### What is it?
AWS Access Keys are credentials that allow programmatic access to your AWS account.

### Why do you need it?
- To allow Terraform to create AWS resources
- To allow GitHub Actions to deploy infrastructure
- For automated AWS API calls

### How to Generate AWS Access Keys

#### Step-by-Step:

1. **Log in to AWS Console**
 - Go to https://console.aws.amazon.com/

2. **Navigate to IAM**
 - Search for "IAM" in the top search bar
 - Click "IAM" (Identity and Access Management)

3. **Create or Select User**
 - Option A: Use existing IAM user
 - Option B: Create new user:
 - Click "Users" > "Create user"
 - Enter username (e.g., "mosip-deployer")
 - Click "Next"

4. **Attach Permissions**
 - Click "Attach policies directly"
 - Search and select these policies:
 - `AmazonEC2FullAccess`
 - `AmazonVPCFullAccess`
 - `AmazonRoute53FullAccess`
 - `IAMFullAccess`
 - `AmazonS3FullAccess`
 - Click "Next" > "Create user"

5. **Create Access Key**
 - Click on the user name
 - Click "Security credentials" tab
 - Scroll to "Access keys" section
 - Click "Create access key"
 - Select use case: "Application running outside AWS"
 - Click "Next"
 - Add description tag (optional): "MOSIP Terraform Deployment"
 - Click "Create access key"

6. **Save Credentials Securely**
 - **IMPORTANT**: This is the ONLY time you can view the secret key!
 - Download CSV file or copy both keys
 - Store in password manager

**You will get:**
```
Access Key ID: AKIAIOSFODNN7EXAMPLE
Secret Access Key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

### Official Documentation
- **AWS Access Keys Guide**: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html
- **AWS IAM Best Practices**: https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html

### Where to Use It
Add as **Repository Secrets** in GitHub:

1. **AWS_ACCESS_KEY_ID**
 - Value: `AKIAIOSFODNN7EXAMPLE` (your actual access key ID)

2. **AWS_SECRET_ACCESS_KEY**
 - Value: `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` (your actual secret)

### Security Best Practices
- ✅ Use IAM user (not root account) for deployment
- ✅ Enable MFA (Multi-Factor Authentication) on IAM user
- ✅ Rotate access keys every 90 days
- ✅ Use least-privilege permissions (only required policies)
- ✅ Monitor AWS CloudTrail for unauthorized usage
- ❌ Never commit keys to Git repositories
- ❌ Never share keys via email or chat
- ❌ Never use root account credentials

### Common Pitfalls
- ❌ Using root account credentials (use IAM user instead)
- ❌ Not saving the secret access key (can't retrieve it later!)
- ❌ Insufficient permissions (deployment will fail)
- ❌ Committing credentials to Git (use secrets!)

---

## 4. WireGuard VPN Configuration

### What is it?
WireGuard is a modern VPN that creates secure connections to your private infrastructure.

### Why do you need it?
- To access Kubernetes clusters via private IP addresses
- To deploy services securely without exposing infrastructure to the internet
- For encrypted communication with infrastructure

### How to Generate WireGuard Config

WireGuard configuration is generated **AFTER** deploying base infrastructure. Follow these steps:

#### Step 1: Deploy Base Infrastructure First
```bash
# Complete Terraform base-infra deployment
# This creates the jump server with WireGuard installed
```

#### Step 2: Follow Detailed Setup Guide
**Complete WireGuard Setup Guide**: [WIREGUARD_SETUP.md](../terraform/base-infra/WIREGUARD_SETUP.md)

#### Quick Overview:

1. **SSH to Jump Server**
 ```bash
 ssh -i ~/.ssh/mosip-aws ubuntu@<jump-server-public-ip>
 ```

2. **Generate Peer Configurations**
 ```bash
 # On jump server
 sudo wg-quick down wg0
 sudo nano /etc/wireguard/wg0.conf
 
 # Add peer configuration
 [Peer]
 PublicKey = <your-public-key>
 AllowedIPs = 10.0.1.2/32
 ```

3. **Get Client Configuration**
 - The jump server provides pre-configured peer templates
 - Customize with your private key and IP address

4. **Install WireGuard Client**
 - **Windows**: https://www.wireguard.com/install/ (download MSI installer)
 - **Mac**: `brew install wireguard-tools` or Mac App Store
 - **Linux**: `sudo apt install wireguard` (Ubuntu/Debian)

5. **Import Configuration**
 - Open WireGuard client
 - Import tunnel from file or paste configuration
 - Activate tunnel

### Official Documentation
- **WireGuard Official**: https://www.wireguard.com/quickstart/
- **WireGuard Installation**: https://www.wireguard.com/install/

### Where to Use It

Add as **Environment Secrets** in GitHub (not repository secrets):

1. **TF_WG_CONFIG** - For Terraform deployments
 ```ini
 [Interface]
 PrivateKey = <terraform-private-key>
 Address = 10.0.1.2/24
 DNS = 10.0.0.2
 
 [Peer]
 PublicKey = <server-public-key>
 Endpoint = <jump-server-ip>:51820
 AllowedIPs = 10.0.0.0/16
 PersistentKeepalive = 25
 ```

2. **CLUSTER_WIREGUARD_WG0** - For Helmsman cluster access (peer1)
3. **CLUSTER_WIREGUARD_WG1** - For Helmsman cluster access (peer2, optional)

### Common Pitfalls
- ❌ Trying to create WireGuard config before deploying base-infra
- ❌ Not activating WireGuard tunnel when testing connectivity
- ❌ Using same peer configuration for different purposes
- ❌ Incorrect AllowedIPs range (should match VPC CIDR)
- ❌ Firewall blocking UDP port 51820

---

## 5. Kubernetes Config (KUBECONFIG)

### What is it?
KUBECONFIG is a configuration file that contains credentials and connection details for your Kubernetes cluster.

### Why do you need it?
- To allow Helmsman to deploy applications to your Kubernetes cluster
- For kubectl command-line access
- For automated deployments via GitHub Actions

### How to Get KUBECONFIG

KUBECONFIG is **automatically generated** by Terraform after deploying infrastructure.

#### Step 1: Deploy Infrastructure First
```bash
# Complete Terraform infra deployment
# Wait for workflow to complete successfully
```

#### Step 2: Locate KUBECONFIG File

The file is created in your Terraform outputs:

```bash
# Location in repository:
terraform/implementations/aws/infra/kubeconfig_<cluster-name>

# Example:
terraform/implementations/aws/infra/kubeconfig_soil38
```

#### Step 3: Download KUBECONFIG

**Option 1: From GitHub Actions Artifacts**
1. Go to your GitHub repository
2. Click "Actions" tab
3. Find the completed "Terraform Infrastructure" workflow
4. Scroll to "Artifacts" section at the bottom
5. Download artifact containing kubeconfig

**Option 2: From Terraform Outputs**
```bash
# View kubeconfig content
cd terraform/implementations/aws/infra/
cat kubeconfig_<your-cluster-name>
```

#### Step 4: Test KUBECONFIG Locally (Optional)

```bash
# Set kubeconfig path
export KUBECONFIG=/path/to/kubeconfig_soil38

# Test connectivity
kubectl get nodes

# You should see your cluster nodes listed
```

### Official Documentation
- **Kubernetes Config**: https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/
- **kubectl Installation**: https://kubernetes.io/docs/tasks/tools/

### Where to Use It

Add as **Environment Secret** in GitHub (not repository secret):

**Secret Name**: `KUBECONFIG`

**Secret Value**: Complete contents of the kubeconfig file

```yaml
# Example format (your actual values will be different):
apiVersion: v1
clusters:
- cluster:
 certificate-authority-data: LS0tLS1CRUdJTi...
 server: https://10.0.1.10:6443
 name: soil38
contexts:
- context:
 cluster: soil38
 user: soil38
 name: soil38
current-context: soil38
kind: Config
preferences: {}
users:
- name: soil38
 user:
 client-certificate-data: LS0tLS1CRUdJTi...
 client-key-data: LS0tLS1CRUdJTi...
```

### Common Pitfalls
- ❌ Trying to get KUBECONFIG before infrastructure is deployed
- ❌ Adding KUBECONFIG as repository secret (should be environment secret)
- ❌ Not including complete file content (missing BEGIN/END lines)
- ❌ Using KUBECONFIG from wrong cluster
- ❌ WireGuard VPN not active when testing kubectl access

---

## 6. reCAPTCHA Keys

### What is it?
reCAPTCHA is Google's service that protects websites from bots and spam by verifying users are human.

### Why do you need it?
- To protect MOSIP web portals (PreReg, Admin, Resident) from automated attacks
- To prevent spam registrations and malicious bots
- Required for production deployments

### How to Generate reCAPTCHA Keys

You need **separate reCAPTCHA keys for each MOSIP portal**:
- PreReg portal: `prereg.your-domain.net`
- Admin portal: `admin.your-domain.net`
- Resident portal: `resident.your-domain.net`

#### Step-by-Step for Each Domain:

1. **Go to Google reCAPTCHA Admin Console**
 - Visit: https://www.google.com/recaptcha/admin/create
 - Sign in with your Google account

2. **Create New Site**
 - **Label**: `MOSIP PreReg` (or Admin/Resident)
 - **reCAPTCHA type**: Select **"reCAPTCHA v2"**
 - **Sub-type**: Select **"I'm not a robot" Checkbox**

3. **Add Domain**
 - Enter your domain: `prereg.your-domain.net`
 - Example: `prereg.soil.mosip.net`
 - Click "+" to add

4. **Accept Terms**
 - Check "Accept the reCAPTCHA Terms of Service"
 - Click "Submit"

5. **Save Keys**
 You will receive two keys:
 ```
 Site Key: 6LfkAMwrAAAAAATB1WhkIhzuAVMtOs9VWabODoZ_
 Secret Key: 6LfkAMwrAAAAAHQAT93nTGcLKa-h3XYhGoNSG-NL
 ```

6. **Repeat for Other Domains**
 - Create separate reCAPTCHA for Admin portal
 - Create separate reCAPTCHA for Resident portal

### Official Documentation
- **Google reCAPTCHA Documentation**: https://developers.google.com/recaptcha/intro
- **reCAPTCHA v2 Guide**: https://developers.google.com/recaptcha/docs/display

### Where to Use It

Update in `Helmsman/dsf/external-dsf.yaml` file:

```yaml
# Around line 315 in external-dsf.yaml
hooks:
 postInstall: "$WORKDIR/hooks/captcha-setup.sh PREREG_SITE_KEY PREREG_SECRET_KEY ADMIN_SITE_KEY ADMIN_SECRET_KEY RESIDENT_SITE_KEY RESIDENT_SECRET_KEY"
```

**Replace placeholders with actual keys:**

```yaml
hooks:
 postInstall: "$WORKDIR/hooks/captcha-setup.sh 6LfkAMwrAAAAAATB1WhkIhzuAVMtOs9VWabODoZ_ 6LfkAMwrAAAAAHQAT93nTGcLKa-h3XYhGoNSG-NL 6LdNAcwrAAAAAETGWvz-3I12vZ5V8vPJLu2ct9CO 6LdNAcwrAAAAAE4iWGJ-g6Dc2HreeJdIwAl5h1iL 6LdRAcwrAAAAAFUEHHKK5D_bSrwAPqdqAJqo4mCk 6LdRAcwrAAAAAOeVl6yHGBCBA8ye9GsUOy4pi9s9"
```

**Key Order:**
1. PreReg Site Key
2. PreReg Secret Key
3. Admin Site Key
4. Admin Secret Key
5. Resident Site Key
6. Resident Secret Key

### Common Pitfalls
- ❌ Using the same reCAPTCHA for all three portals (need separate ones!)
- ❌ Wrong domain name in reCAPTCHA setup
- ❌ Mixing up site keys and secret keys
- ❌ Wrong order of keys in captcha-setup.sh arguments
- ❌ Not updating keys after changing domain names

---

## 7. How to Add Secrets to GitHub

### Understanding Secret Types

#### Repository Secrets
- **Scope**: Available to all branches and environments
- **Use case**: Cloud credentials, SSH keys, GPG passphrase
- **Where to add**: Settings → Secrets and variables → Actions → Repository secrets

#### Environment Secrets
- **Scope**: Specific to a deployment environment/branch
- **Use case**: KUBECONFIG, WireGuard configs (different per environment)
- **Where to add**: Settings → Secrets and variables → Actions → Environments

### Step-by-Step: Adding Repository Secrets

1. **Navigate to Repository Settings**
 ```
 Your Repository → Settings → Secrets and variables → Actions
 ```

2. **Click "Repository secrets" Tab**

3. **Click "New repository secret"**

4. **Add Secret**
 - **Name**: Enter secret name (e.g., `AWS_ACCESS_KEY_ID`)
 - **Value**: Paste secret value
 - Click "Add secret"

5. **Repeat for All Repository Secrets**
 - `GPG_PASSPHRASE`
 - `AWS_ACCESS_KEY_ID`
 - `AWS_SECRET_ACCESS_KEY`
 - `mosip-aws` (or your SSH key name)

### Step-by-Step: Adding Environment Secrets

1. **Create Environment (if not exists)**
 ```
 Settings > Environments > New environment
 ```
 - **Name**: Your branch name (e.g., `release-0.1.0`, `main`, `develop`)
 - Click "Configure environment"

2. **Add Environment Secrets**
 - Scroll to "Environment secrets" section
 - Click "Add secret"
 - **Name**: Enter secret name (e.g., `KUBECONFIG`)
 - **Value**: Paste secret value
 - Click "Add secret"

3. **Repeat for All Environment Secrets**
 - `KUBECONFIG`
 - `TF_WG_CONFIG`
 - `CLUSTER_WIREGUARD_WG0`
 - `CLUSTER_WIREGUARD_WG1` (optional)

### Official Documentation
- **GitHub Secrets Documentation**: https://docs.github.com/en/actions/security-guides/encrypted-secrets

### Visual Guide

```
Repository Structure:
├── Repository Secrets (global, all branches)
│ ├── GPG_PASSPHRASE
│ ├── AWS_ACCESS_KEY_ID
│ ├── AWS_SECRET_ACCESS_KEY
│ └── mosip-aws (SSH private key)
│
└── Environments
 ├── release-0.1.0 (environment)
 │ ├── KUBECONFIG
 │ ├── TF_WG_CONFIG
 │ ├── CLUSTER_WIREGUARD_WG0
 │ └── CLUSTER_WIREGUARD_WG1
 │
 ├── main (environment)
 │ └── (same secrets as above)
 │
 └── develop (environment)
 └── (same secrets as above)
```

### Common Pitfalls
- ❌ Adding KUBECONFIG as repository secret (should be environment secret)
- ❌ Environment name doesn't match branch name
- ❌ Copy-paste errors (extra spaces, newlines)
- ❌ Not updating secrets after rotation
- ❌ Typos in secret names (case-sensitive!)

---

## Quick Reference Checklist

Use this checklist to ensure you've generated and configured all required secrets:

### Repository Secrets (Do Once)
- [ ] SSH Key Pair generated
- [ ] SSH Public Key added to AWS EC2 Key Pairs
- [ ] SSH Private Key added to GitHub Repository Secret
- [ ] GPG Passphrase generated and added
- [ ] AWS Access Key ID obtained and added
- [ ] AWS Secret Access Key obtained and added

### Infrastructure Deployment
- [ ] Terraform base-infra deployed successfully
- [ ] WireGuard VPN configured on jump server
- [ ] WireGuard client installed on your computer
- [ ] TF_WG_CONFIG environment secret added

### Main Infrastructure
- [ ] Terraform infra deployed successfully
- [ ] KUBECONFIG file downloaded from Terraform outputs
- [ ] KUBECONFIG added as environment secret
- [ ] WireGuard cluster access configs added

### MOSIP Services
- [ ] reCAPTCHA keys generated for PreReg portal
- [ ] reCAPTCHA keys generated for Admin portal
- [ ] reCAPTCHA keys generated for Resident portal
- [ ] reCAPTCHA keys added to external-dsf.yaml

---

## Troubleshooting

### Secret Not Working

**Check these common issues:**

1. **Typo in secret name**
 - Secret names are case-sensitive
 - Verify exact name matches workflow configuration

2. **Wrong secret type**
 - Verify if it should be repository or environment secret
 - Check if workflow is using correct environment

3. **Invalid format**
 - Ensure no extra spaces or newlines
 - Include complete content (BEGIN/END lines for keys)

4. **Secret not accessible**
 - Verify workflow has permission to access secrets
 - Check environment protection rules

### Need Help?

- **GitHub Issues**: Report problems in repository issues
- **MOSIP Community**: Join community channels for support
- **Documentation**: Refer to component-specific guides

---

**Navigation**: [Back to Main README](../README.md) | [View Glossary](GLOSSARY.md)
