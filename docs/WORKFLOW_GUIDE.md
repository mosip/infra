# GitHub Actions Workflow Guide

This guide provides detailed, step-by-step instructions for running Terraform and Helmsman workflows through GitHub Actions. Perfect for beginners who need visual guidance on navigating the GitHub interface.

## Table of Contents

1. [Understanding Workflow Basics](#understanding-workflow-basics)
2. [Terraform Workflows](#terraform-workflows)
3. [Helmsman Workflows](#helmsman-workflows)
4. [Workflow Parameters Explained](#workflow-parameters-explained)
5. [Common Issues and Solutions](#common-issues-and-solutions)

---

## Understanding Workflow Basics

### What You'll See
When you run workflows, you'll interact with GitHub's web interface. Here's what to expect:

```
Your Repository
└── Actions Tab (at the top)
 ├── All workflows (left sidebar)
 ├── Workflow runs (center)
 └── Run workflow button (right side)
```

### Key Concepts

#### Terraform Apply vs Dry Run

| Mode | What It Does | When to Use |
|------|--------------|-------------|
| **Apply** (checkbox ✅) | Actually creates/modifies infrastructure | Production deployments, real changes |
| **Dry Run** (checkbox ☐) | Shows what WOULD happen without making changes | Testing configurations, previewing changes |

**Example:**
- ✅ **Checked** → Terraform will create actual AWS servers
- ☐ **Unchecked** → Terraform only shows you the plan (no changes made)

#### Rancher Import Option

| Setting | What It Does | When to Use |
|---------|--------------|-------------|
| **True** | Automatically imports cluster into Rancher UI | If you want centralized cluster management |
| **False** | Cluster runs independently | For standalone deployments |

**Relationship with Terraform Apply:**
```
If Terraform Apply = ✅ AND Rancher Import = True
 → Cluster is deployed AND imported into Rancher

If Terraform Apply = ✅ AND Rancher Import = False
 → Cluster is deployed but NOT imported

If Terraform Apply = ☐ (unchecked)
 → Dry run only, nothing happens (Rancher import setting is ignored)
```

---

## Terraform Workflows

### Workflow 1: Base Infrastructure

**What it does**: Creates the foundation - VPC, networking, jump server, WireGuard VPN

#### Step-by-Step Navigation

1. **Open GitHub Actions**
 ```
 Click: Your Repository → Actions (top menu bar)
 ```

2. **Find the Workflow**
 ```
 Left Sidebar: Look for "Terraform Base Infrastructure"
 Click on it
 ```

3. **Start the Workflow**
 ```
 Right Side: Click "Run workflow" button (dropdown)
 ```

4. **Configure Parameters**
 You'll see a form with these fields:

 | Parameter | What to Select | Example | Notes |
 |-----------|---------------|---------|-------|
 | **Use workflow from** | `Branch: release-0.1.0` | Your deployment branch | Dropdown at top |
 | **Cloud Provider** | `aws` | `aws` | Azure/GCP not fully implemented |
 | **Component** | `base-infra` | `base-infra` | Creates VPC & networking |
 | **Backend** | `local` or `s3` | `local` for dev, `s3` for prod | Where Terraform stores state |
 | **Terraform apply** | ✅ Check this box | ✅ | Leave unchecked for dry run |

5. **Run the Workflow**
 ```
 Bottom of form: Click green "Run workflow" button
 ```

6. **Monitor Progress**
 ```
 Watch the workflow run in real-time
 Yellow circle = Running
 Green checkmark = Success
 Red X = Failed
 ```

#### What You Should See

**During Execution:**
```
✓ Setup environment
✓ Configure WireGuard
✓ Run Terraform init
✓ Run Terraform plan
→ Run Terraform apply (if checked)
✓ Complete
```

**After Success:**
- VPC created in AWS
- Jump server running
- WireGuard VPN configured
- Security groups configured
- Output shows server IP addresses

---

### Workflow 2: Main Infrastructure

**What it does**: Creates MOSIP Kubernetes cluster, PostgreSQL (optional), application infrastructure

#### Step-by-Step Navigation

1. **Open GitHub Actions**
 ```
 Click: Your Repository → Actions
 ```

2. **Find the Workflow**
 ```
 Left Sidebar: Look for "Terraform Infrastructure"
 Click on it
 ```
 
 **Note**: The workflow name might also appear as:
 - "Terraform"
 - "Deploy Infrastructure"
 - Check for keywords: "Infrastructure" or "Main Infra"

3. **Start the Workflow**
 ```
 Click: "Run workflow" button (right side)
 ```

4. **Configure Parameters**

 | Parameter | What to Select | Example | Why? |
 |-----------|---------------|---------|------|
 | **Use workflow from** | `Branch: release-0.1.0` | Your branch | Dropdown at top |
 | **Cloud Provider** | `aws` | `aws` | Where to deploy |
 | **Component** | `infra` | `infra` | Main MOSIP infrastructure |
 | **Profile** | `esignet` or `mosip` | `esignet` | Selects tfvars and cluster size — see below |
 | **Backend** | `local` or `s3` | `local` | State storage location |
 | **Terraform apply** | ✅ | ✅ | Check to deploy, uncheck for dry run |

 **Profile options for `infra` component:**

 | Profile | tfvars loaded | Cluster size | Use for |
 |---------|--------------|--------------|---------|
 | `esignet` | `profiles/esignet/aws.tfvars` | 4-node K8s cluster | eSignet standalone |
 | `mosip` | `profiles/mosip/aws.tfvars` | 7-node K8s cluster | Full MOSIP platform |

 > **Note**: `base-infra` and `observ-infra` do not use a profile — this field only applies to the `infra` component.

5. **Run the Workflow**
 ```
 Click: Green "Run workflow" button
 ```

6. **Monitor Progress** (This takes 15-30 minutes)
 ```
 → Creating Kubernetes cluster
 → Installing RKE2
 → Configuring networking
 → Setting up PostgreSQL (if enabled)
 → Importing to Rancher (if enabled)
 ```

#### What You Should See

**Success Indicators:**
- ✅ Kubernetes cluster created
- ✅ Multiple nodes visible in AWS EC2
- ✅ KUBECONFIG file generated
- ✅ PostgreSQL running (if enabled)

**Outputs to Save:**
- KUBECONFIG file location
- Cluster endpoint URL
- Node IP addresses

---

### Workflow 3: Observability Infrastructure (Optional)

**What it does**: Creates Rancher management cluster for monitoring multiple MOSIP clusters

#### When to Use
- Managing multiple MOSIP environments
- Need centralized cluster management UI
- Want advanced monitoring dashboards

#### Step-by-Step Navigation

1. **Open GitHub Actions**
 ```
 Click: Repository → Actions
 ```

2. **Find the Workflow**
 ```
 Left Sidebar: "Terraform Observability Infrastructure"
 OR look for: "Observ Infra" / "Monitoring Infrastructure"
 ```

3. **Configure Parameters**

 | Parameter | What to Select | Example |
 |-----------|---------------|---------|
 | **Branch** | `release-0.1.0` | Your deployment branch |
 | **Cloud Provider** | `aws` | `aws` |
 | **Component** | `observ-infra` | `observ-infra` |
 | **Backend** | `local` or `s3` | `local` for dev |
 | **Terraform apply** | ✅ | Check to deploy |

4. **Run and Monitor**
 - Deployment takes 10-20 minutes
 - Creates separate Rancher management cluster

---

## Helmsman Workflows

### Deployment Flow

**eSignet standalone profile** (`profile=esignet`):
```
External (prereq + external-dsf, parallel) → eSignet (4 parallel instances) → Testrigs
```

**MOSIP platform profiles** (`profile=mosip-platform-1.2.0.x` or `mosip-platform-1.2.1.x`):
```
External (prereq + external-dsf, parallel) → MOSIP (auto-triggered) → eSignet → Testrigs
```

### Profile Selection

Each Helmsman workflow takes a `profile` input that selects the DSF subdirectory to use:

| Profile | DSF directory | Use case |
|---------|--------------|----------|
| `esignet` | `Helmsman/dsf/esignet/` | eSignet standalone (no full MOSIP) |
| `mosip-platform-1.2.0.x` | `Helmsman/dsf/mosip-platform-1.2.0.x/` | Full MOSIP, Java 11 |
| `mosip-platform-1.2.1.x` | `Helmsman/dsf/mosip-platform-1.2.1.x/` | Full MOSIP, Java 21 |

### Understanding Helmsman Modes

**IMPORTANT**: For Helmsman, ALWAYS use `apply` mode. Dry-run mode will fail!

**Why dry-run fails:**
- Helmsman checks dependencies between namespaces
- Dry-run doesn't create shared configmaps/secrets
- Validation fails when resources don't exist yet

**Always use:**
```
Mode: apply ✅
```

---

### Workflow 1: Prerequisites & External Dependencies

**What it does**: Deploys monitoring, Istio, databases, message queues, storage, Keycloak

**Workflow Name in GitHub**: `Deploy External services of mosip using Helmsman`

#### Step-by-Step Navigation

1. **Open GitHub Actions**
 ```
 Click: Repository → Actions
 ```

2. **Find the Workflow**
 ```
 Left Sidebar: "Deploy External services of mosip using Helmsman"
 ```

3. **Start the Workflow**
 ```
 Click: "Run workflow" button
 ```

4. **Configure Parameters**

 | Parameter | What to Select | Notes |
 |-----------|---------------|-------|
 | **Branch** | Your deployment branch | Selects the GitHub Environment for secrets/vars |
 | **profile** | `esignet` / `mosip-platform-1.2.0.x` / `mosip-platform-1.2.1.x` | Selects DSF subdirectory |
 | **mode** | `apply` | MUST be apply, not dry-run! |
 | **domain_name** | `sandbox.example.net` | Your deployment domain (or set `vars.DOMAIN_NAME`) |
 | **db_port** | `5433` | MOSIP platform external postgres port (or `vars.DB_PORT`) |
 | **esignet_db_port** | `5432` | eSignet container postgres port (or `vars.ESIGNET_DB_PORT`) |
 | **env_name** | `sandbox` | Environment display name (or `vars.ENV_NAME`) |
 | **clusterid** | `c-m-abc12xyz` | Rancher cluster ID for monitoring (or `vars.CLUSTER_ID`) |
 | **slack_channel_name** | `#mosip-alerts` | For alerting (or `vars.SLACK_CHANNEL_NAME`) |

 > **Tip**: If you configure GitHub Environment Variables (`vars.*`), you don't need to fill these in for each run — the workflow reads them automatically.

5. **What Happens** (20-40 minutes)
 
 Deploys TWO DSF files in parallel:
 
 - **Prerequisites**: Monitoring, Istio, Logging (`prereq-dsf.yaml`)
 - **External Dependencies**: PostgreSQL, Redis, Kafka, SoftHSM, Keycloak, Captcha, MinIO (`external-dsf.yaml`)

6. **Automatic Trigger**
 ```
 ✅ On success → Automatically triggers MOSIP Services deployment (for MOSIP platform profiles)
 ```
 > For `profile=esignet`, the MOSIP auto-trigger is skipped — run the eSignet workflow directly next.

---

### Workflow 2: MOSIP Core Services (Auto-triggered)

**What it does**: Deploys all MOSIP application services

**Workflow Name**: `Deploy MOSIP services using Helmsman`

**Trigger**: Automatically runs after Workflow 1 succeeds (MOSIP platform profiles only — NOT triggered for `profile=esignet`)

**Manual Run** (if needed):

| Parameter | Value |
|-----------|-------|
| Branch | Your deployment branch |
| profile | `mosip-platform-1.2.0.x` or `mosip-platform-1.2.1.x` |
| mode | `apply` |
| domain_name | Your domain |

**Monitor Progress** (30-60 minutes):
- Config Server, Artifactory, Kernel services
- Pre-registration, Registration Processor
- ID Repository, Authentication services
- Partner Management, Resident Services

**Important**: Verify all pods running before proceeding to eSignet

---

### Workflow 3: eSignet (Manual)

**What it does**: Deploys eSignet authentication stack (1 instance for MOSIP platform profiles, 4 parallel instances for eSignet standalone)

**Workflow Name**: `Deploy eSignet using Helmsman`

**Prerequisites**: External services must be running (Workflow 1 complete)

#### Step-by-Step Navigation

1. **Find the Workflow**
 ```
 GitHub Actions → "Deploy eSignet using Helmsman"
 ```

2. **Configure Parameters**

 | Parameter | What to Select | Notes |
 |-----------|---------------|-------|
 | **Branch** | Your deployment branch | |
 | **profile** | `esignet` / `mosip-platform-1.2.0.x` / `mosip-platform-1.2.1.x` | Must match what you used for external-dsf |
 | **mode** | `apply` | MUST be apply! |
 | **domain_name** | `sandbox.example.net` | Or set `vars.DOMAIN_NAME` |
 | **esignet_db_port** | `5432` (esignet) / `5433` (MOSIP platform) | Or set `vars.ESIGNET_DB_PORT` |
 | **mosipid1_domain_name** | `mosipid1.example.net` | esignet profile only — MOSIP-ID1 environment domain |
 | **mosipid2_domain_name** | `mosipid2.example.net` | esignet profile only — MOSIP-ID2 environment domain |
 | **skip_mosip_dsf_check** | `true` for standalone, `false` when MOSIP is deployed | |
 | **delete_existing_jobs** | `true` when re-running after a failed attempt | Cleans up stale onboarder jobs |

3. **Monitor Progress** (25-35 minutes for esignet profile with 4 instances)
 ```
 → SoftHSM (all 4 namespaces)
 → Config server
 → eSignet core (all 4 namespaces in parallel)
 → OIDC UI (all 4 namespaces)
 → Mock identity system
 → Mock relying party
 ```

4. **Next step**
 ```
 ✅ On success → Run Testrigs workflow manually
 ```

**Check Status:**
```bash
kubectl get pods -n esignet
kubectl get pods -n esignet-mosipid1    # esignet profile only
kubectl get pods -n esignet-mosipid2   # esignet profile only
kubectl get pods -n esignet-sunbird # esignet profile only
```

---

### Workflow 4: Test Rigs (Manual, Optional)

**What it does**: Deploys automated testing infrastructure (API/UI test rigs as CronJobs)

**IMPORTANT**: Only run after ALL services are running and stable!

#### Step-by-Step Navigation

1. **Verify All Services Running**
 ```bash
 kubectl get pods -A | grep -v Running | grep -v Completed
 # Should return nothing!
 ```

2. **Find the Workflow**
 ```
 GitHub Actions → "Deploy Testrigs of mosip using Helmsman"
 ```

3. **Configure Parameters**

 | Parameter | What to Select | Notes |
 |-----------|---------------|-------|
 | **Branch** | Your deployment branch | |
 | **profile** | Same as your deployment profile | |
 | **mode** | `apply` | |
 | **domain_name** | `sandbox.example.net` | Or `vars.DOMAIN_NAME` |
 | **mosipid1_domain_name** | `mosipid1.example.net` | esignet profile only |
 | **mosipid2_domain_name** | `mosipid2.example.net` | esignet profile only |
 | **db_port** | `5433` | MOSIP platform only |
 | **esignet_db_port** | `5432` | eSignet profile |

4. **Monitor Progress** (10-20 minutes)
 ```
 → esignet-apitestrig (esignet profile: 4 instances across all namespaces)
 → signup-apitestrig (if signup was deployed)
 → API / DSL / UI test rigs (MOSIP platform profiles)
 ```

5. **Verify CronJobs Created**
 ```bash
 kubectl get cronjobs -n esignet
 kubectl get cronjobs -n esignet-mosipid1   # esignet profile
 kubectl get cronjobs -n esignet-mosipid2  # esignet profile
 kubectl get cronjobs -n esignet-sunbird # esignet profile
 ```

---

## Workflow Parameters Explained

### Common to All Terraform Workflows

#### Branch Selection
```
Use workflow from: Branch [dropdown]
```
**What it does**: Selects which branch's code to use

**Choose**:
- `release-0.1.0` - Stable release branch
- `main` - Main development branch
- `develop` - Latest development

**Recommendation**: Use release branches for production

---

#### Cloud Provider
```
Cloud Provider: [aws | azure | gcp]
```
**What it does**: Selects cloud platform

**Status**:
- ✅ `aws` - Fully functional
- `azure` - Placeholder only
- `gcp` - Placeholder only

**Choose**: `aws` (only fully implemented option)

---

#### Component
```
Component: [base-infra | infra | observ-infra]
```
**What it does**: Selects which infrastructure layer to deploy

**Options**:
| Component | Creates | Run Order |
|-----------|---------|-----------|
| `base-infra` | VPC, networking, jump server | **1st** (foundation) |
| `observ-infra` | Rancher management cluster | **2nd** (optional) |
| `infra` | MOSIP Kubernetes cluster | **3rd** (main deployment) |

---

#### Infra Profile
```
Profile: [esignet | mosip]
```
**Applies to**: `infra` component only (`base-infra` and `observ-infra` ignore this field)

| Profile | tfvars file | Cluster size | Use for |
|---------|------------|--------------|---------|
| `esignet` | `profiles/esignet/aws.tfvars` | 4-node K8s cluster | eSignet standalone deployment |
| `mosip` | `profiles/mosip/aws.tfvars` | 7-node K8s cluster | Full MOSIP platform deployment |

**Important**: The Terraform profile (`esignet` / `mosip`) and the Helmsman profile (`esignet` / `mosip-platform-1.2.0.x` / `mosip-platform-1.2.1.x`) are separate inputs. After running `infra` with `profile=mosip`, you choose the specific MOSIP platform version when running the Helmsman workflows.

---

#### Backend
```
Backend: [local | s3]
```
**What it does**: Determines where Terraform stores state files

| Backend | Storage Location | Best For | Encryption |
|---------|-----------------|----------|------------|
| `local` | GitHub repository | Development, small teams | GPG encrypted |
| `s3` | AWS S3 bucket | Production, large teams | S3 server-side encryption |

**Recommendations**:
- Development → `local`
- Production → `s3`

---

#### Terraform Apply Checkbox
```
☐ Terraform apply
```
**What it does**: Controls whether changes are actually made

| State | Effect | Use Case |
|-------|--------|----------|
| ☐ **Unchecked** | Dry run - shows plan only | Testing configurations |
| ✅ **Checked** | Applies changes - creates resources | Actual deployment |

**Visual Guide**:
```
☐ Unchecked → terraform plan → Shows what WOULD happen → No changes
✅ Checked → terraform apply → Actually creates resources → Real changes
```

---

### Helmsman-Specific Parameters

#### Mode Selection
```
Mode: [apply | dry-run]
```

**IMPORTANT**: Always use `apply` for Helmsman!

**Why?**
```
apply ✅ Works correctly
dry-run ❌ Fails due to missing shared resources
```

**Choose**: `apply` (always)

---

#### Profile Selection
```
profile: [esignet | mosip-platform-1.2.0.x | mosip-platform-1.2.1.x]
```

Selects the DSF subdirectory under `Helmsman/dsf/`. Must be consistent across all workflows in a deployment:

| Profile | DSF directory | Use when |
|---------|--------------|----------|
| `esignet` | `Helmsman/dsf/esignet/` | eSignet-only deployment |
| `mosip-platform-1.2.0.x` | `Helmsman/dsf/mosip-platform-1.2.0.x/` | Full MOSIP, Java 11 |
| `mosip-platform-1.2.1.x` | `Helmsman/dsf/mosip-platform-1.2.1.x/` | Full MOSIP, Java 21 |

---

#### Domain and Environment Inputs

These inputs override the corresponding GitHub Environment Variables for a single run:

| Input | Fallback variable | Purpose |
|-------|------------------|---------|
| `domain_name` | `vars.DOMAIN_NAME` | Base domain for all services |
| `env_name` | `vars.ENV_NAME` | Environment display name |
| `clusterid` | `vars.CLUSTER_ID` | Rancher cluster ID |
| `db_port` | `vars.DB_PORT` | MOSIP platform postgres port |
| `esignet_db_port` | `vars.ESIGNET_DB_PORT` | eSignet postgres port |
| `mosipid1_domain_name` | `vars.MOSIPID1_DOMAIN_NAME` | MOSIP-ID1 environment base domain (esignet profile) |
| `mosipid2_domain_name` | `vars.MOSIPID2_DOMAIN_NAME` | MOSIP-ID2 environment base domain (esignet profile) |

---

## Common Issues and Solutions

### Issue 1: Workflow Not Found

**Problem**: Can't find the workflow in GitHub Actions

**Solution**:
1. Check left sidebar - workflows are listed by name
2. Try searching for keywords: "Terraform", "Helmsman", "Deploy"
3. Verify you're on the "Actions" tab
4. Check if workflows are in `.github/workflows/` directory

**Workflow Name Variations**:
| Documentation Says | Actual Workflow Name Might Be |
|--------------------|------------------------------|
| "Helmsman External Dependencies" | "Deploy External services of mosip using Helmsman" |
| "Terraform Infrastructure" | "Terraform" or "Deploy Infrastructure" |

---

### Issue 2: Workflow Run Fails

**Problem**: Red X appears, workflow failed

**Solution**:
1. **Click on the failed run**
 ```
 Actions → Click the failed run → Click failed job
 ```

2. **Read error messages**
 ```
 Scroll through logs
 Look for red ERROR or FAILED messages
 ```

3. **Common Errors**:

 | Error Message | Solution |
 |--------------|----------|
 | "Authentication failed" | Check AWS credentials in secrets |
 | "InsufficientInstanceCapacity" | Set `specific_availability_zones = []` |
 | "Permission denied" | Check IAM permissions |
 | "Secret not found" | Add missing secret to GitHub |

---

### Issue 3: Terraform Apply Checkbox Confusion

**Problem**: Not sure when to check or uncheck

**Simple Rule**:
```
Want to see what would happen? → ☐ Uncheck (dry run)
Want to actually deploy? → ✅ Check (apply)
```

**Example Scenarios**:
```
Testing new configuration → ☐ Uncheck first to verify
First time deploying → ☐ Uncheck first, then ✅ check
Updating existing deployment → ☐ Uncheck first to see changes
```

---

### Issue 4: Environment Not Found

**Problem**: Workflow can't find environment secrets

**Solution**:
1. **Verify environment name matches branch**
 ```
 Branch: release-0.1.0
 Environment name: release-0.1.0 (must match exactly!)
 ```

2. **Create environment if missing**
 ```
 Settings → Environments → New environment
 Name: release-0.1.0 (match your branch)
 ```

3. **Add secrets to environment**
 ```
 Configure environment → Add secrets
 ```

---

### Issue 5: Helmsman Dry-Run Fails

**Problem**: Helmsman workflow fails with validation errors

**Solution**:
```
❌ Don't use: Mode = dry-run
✅ Always use: Mode = apply
```

**Why?**
- Dry-run validates resources that don't exist yet
- Shared configmaps/secrets aren't created in dry-run
- Dependencies between namespaces can't be validated

---

## Workflow Execution Checklist

### Before Running ANY Workflow

- [ ] All required secrets configured
- [ ] Branch selected correctly
- [ ] Environment matches branch name
- [ ] AWS/cloud credentials valid
- [ ] Previous steps completed successfully

### For Terraform Workflows

- [ ] tfvars file updated with correct values
- [ ] Cloud provider = `aws`
- [ ] Backend choice made (`local` or `s3`)
- [ ] Understand dry-run vs apply
- [ ] WireGuard configured (for infra deployment)

### For Helmsman Workflows

- [ ] KUBECONFIG secret added (raw YAML, not base64)
- [ ] WireGuard secrets (`CLUSTER_WIREGUARD_WG0`, `CLUSTER_WIREGUARD_WG1`) configured
- [ ] GitHub Environment Variables set (`DOMAIN_NAME`, `ENV_NAME`, `CLUSTER_ID`, `SLACK_CHANNEL_NAME`, `DB_PORT`, `ESIGNET_DB_PORT`)
- [ ] Previous Helmsman steps completed and all pods Running
- [ ] Mode set to `apply` (never dry-run — it will fail!)
- [ ] Profile selected consistently across all workflow runs

---

## Visual Workflow Summary

### eSignet Standalone (`profile=esignet`)

```
DEPLOYMENT FLOW:

1. Terraform: Base Infrastructure
 └── VPC, networking, WireGuard jump server

2. Terraform: Main Infrastructure
 └── RKE2 Kubernetes cluster
 └── PAUSE: Add KUBECONFIG secret

3. Helmsman: External Dependencies  [helmsman_external.yml, profile=esignet]
 └── prereq-dsf + external-dsf (parallel)
 └── PostgreSQL, Redis, Kafka, SoftHSM, Keycloak, Captcha, MinIO

4. Helmsman: eSignet  [helmsman_esignet.yml, profile=esignet]
 └── 4 parallel instances (esignet / esignet-mosipid1 / esignet-mosipid2 / esignet-sunbird)

5. Helmsman: Test Rigs  [helmsman_testrigs.yml, profile=esignet, manual]
 └── API testrigs for all 4 esignet namespaces
 └── ✅ Deployment Complete!
```

### Full MOSIP Platform (`profile=mosip-platform-1.2.0.x` or `mosip-platform-1.2.1.x`)

```
DEPLOYMENT FLOW:

1. Terraform: Base Infrastructure
2. Terraform: Main Infrastructure
3. Helmsman: External Dependencies  [helmsman_external.yml, profile=mosip-platform-*]
 └── ✅ Auto-triggers MOSIP workflow on success

4. Helmsman: MOSIP Core Services  [helmsman_mosip.yml — auto-triggered]
 └── 50+ microservices across 22 namespaces
 └── PAUSE: Verify all pods Running

5. Helmsman: eSignet  [helmsman_esignet.yml, profile=mosip-platform-*]
 └── 1 eSignet instance in esignet namespace

6. Helmsman: Test Rigs  [helmsman_testrigs.yml, manual]
 └── ✅ Deployment Complete!
```

---

## Need More Help?

- **Detailed Configurations**: See [DSF Configuration Guide](DSF_CONFIGURATION_GUIDE.md)
- **Secret Setup**: See [Secret Generation Guide](SECRET_GENERATION_GUIDE.md)
- **Troubleshooting**: See [Main README Troubleshooting Section](../README.md#troubleshooting-guides)
- **Report Issues**: Open GitHub issue with workflow logs

---

**Navigation**: [Back to Main README](../README.md) | [View Glossary](GLOSSARY.md)
