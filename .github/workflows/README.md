# GitHub Actions Workflows Documentation

> **Complete guide to automated infrastructure and application deployment workflows**

## Overview

This directory contains GitHub Actions workflows for automated MOSIP deployment:
- **Terraform workflows** for infrastructure provisioning (AWS complete, Azure/GCP placeholders)
- **Helmsman workflows** for application deployment on provisioned infrastructure 
- **GPG encrypted state management** with branch isolation
- **Sequential workflow execution** with parallel optimization within Helmsman phase

## Available Workflows

| Workflow | Purpose | Trigger | State Management | PostgreSQL |
|----------|---------|---------|------------------|------------|
| `terraform.yml` | Deploy/Update Infrastructure (Terraform + Ansible) | Manual Dispatch | GPG encrypted local | Ansible, per profile |
| `terraform-destroy.yml` | Destroy Infrastructure (reverse order) | Manual Dispatch | Uses encrypted state | Volume removed with storage |
| `terraform-component.yml` | Reusable: one Terraform root | Called by the two above | Per component | — |
| `infra-checks.yml` | Static checks | Pull request | — | — |
| `helmsman_external.yml` | Deploy Prerequisites & External Dependencies | Manual Dispatch | Uses deployed infra | **Parallel deployment** |
| `helmsman_mosip.yml` | Deploy MOSIP Services | Manual Dispatch | Uses deployed infra | Uses deployed PostgreSQL |
| `helmsman_esignet.yml` | Deploy eSignet Stack | Manual/Push | Uses deployed infra | Uses deployed PostgreSQL |
| `helmsman_testrigs.yml` | Deploy Test Rigs | Manual Dispatch | Uses deployed infra | Testing components |

## Cloud Provider Support

| Provider | Status | Implementation |
|----------|---------|----------------|
| **AWS** | **Complete** | Full infrastructure, VPC, RKE2, PostgreSQL integration |
| **Azure** | **Placeholder** | Basic structure - [community contributions welcome](../terraform/base-infra/azure/) |
| **GCP** | **Placeholder** | Basic structure - [community contributions welcome](../terraform/base-infra/gcp/) |

## Deployment Guide

### Step 1: Deploy Infrastructure

1. **Navigate**: Actions → "terraform plan / apply"
2. **Configure Parameters**:
 ```yaml
 CLOUD_PROVIDER: aws
 COMPONENT: all              # or one component, configure, base-infra
 PROFILE: mosip              # mosip | esignet-standalone | observ
 BACKEND_TYPE: local         # GPG-encrypted state committed to the branch
 SSH_PRIVATE_KEY: mosip-aws  # name of the secret with the node SSH key
 TERRAFORM_APPLY: true       # required for all / configure
 ```
3. **Execute**: Click "Run workflow"
4. **PostgreSQL / ActiveMQ**: controlled by the profile — `profiles/<profile>/profile.yml`
   (`configure_components`) and the volume sizes in `profiles/<profile>/aws/storage.tfvars`.

### Step 2: Deploy Prerequisites & External Dependencies (After Infrastructure Ready)

**Prerequisites: Complete Terraform infrastructure deployment first**

1. **Navigate**: Actions → "helmsman external dependencies"
2. **Configure**: Select deployed infrastructure environment
3. **Parallel Execution**: Prerequisites and External Dependencies deploy simultaneously
4. **Duration**: ~70-110 minutes (20% faster than sequential approach)

### Step 3: Deploy MOSIP Services (After Prerequisites Ready)

1. **Navigate**: Actions → "helmsman mosip services" 
2. **PostgreSQL Integration**: Automatically uses deployed PostgreSQL
3. **Duration**: ~25-35 minutes

### Step 4: Destroy Infrastructure (When Needed)

1. **Navigate**: Actions → "terraform destroy"
2. **Configure**: Use same parameters as deployment
3. **Confirm**: Set `TERRAFORM_DESTROY: true`
4. **PostgreSQL Cleanup**: Automatically handled
5. **Execute**: Click "Run workflow"

## PostgreSQL Integration

External PostgreSQL runs on the nginx node's second data volume. It's on when
the profile lists `postgresql` in `configure_components` **and** (on AWS) the
storage component creates the volume:

```hcl
# profiles/mosip/aws/storage.tfvars
nginx_node_ebs_volume_size_2 = 200   # 0 = no postgres volume → postgresql is skipped
```

Version / port come from `profiles/<profile>/profile.yml` (`ansible_vars`).
Leave it off to use in-cluster PostgreSQL via Helmsman.

## Terraform workflows

```
terraform.yml (dispatch)                 terraform-destroy.yml (dispatch)
  validate                                 validate
  security ─► compute ─► iam ─►            dns ─► storage ─► iam ─►
  storage ─► dns ─► configure (Ansible)    compute ─► security
        │                                        │
        └──── each job calls terraform-component.yml (reusable) ────┘
                 plan / apply / destroy of ONE root, own state
```

| Input | Values | Notes |
|-------|--------|-------|
| `CLOUD_PROVIDER` | `aws` \| `azure` \| `gcp` | azure/gcp: `base-infra` only |
| `COMPONENT` | `all` \| `security` \| `compute` \| `iam` \| `storage` \| `dns` \| `configure` \| `base-infra` | `all` = every component in order, then configure |
| `PROFILE` | `mosip` \| `esignet-standalone` \| `observ` | deployment shape, see [docs/PROFILES.md](../../docs/PROFILES.md) |
| `BACKEND_TYPE` | `local` \| `remote` | local = GPG-encrypted state in git |
| `REMOTE_BACKEND_CONFIG` | `aws:bucket:region` … | remote only |
| `ENABLE_STATE_LOCKING` | bool | remote only |
| `SSH_PRIVATE_KEY` | secret name | key for `ssh_key_name` |
| `TERRAFORM_APPLY` | bool | unchecked = plan only; required for `all` / `configure` |
| `ENABLE_RANCHER_IMPORT` | bool | register in Rancher via API during configure |
| `RANCHER_CLUSTER_NAME`, `PUBLISH_KUBECONFIG`, `GRANT_GROUP_ACCESS`, `RANCHER_CLUSTER_OWNER_GROUP*` | | Rancher follow-ups, as before |

- Each component job only calls cloud APIs; the `configure` job connects
  WireGuard and runs `ansible/site.yml` over SSH.
- A component can always be run alone for day-2 changes (`COMPONENT=dns`
  to update only Route53, `COMPONENT=configure` to re-run Ansible).
- Destroy: **terraform destroy** with the same `COMPONENT` / `PROFILE`;
  unchecked `TERRAFORM_DESTROY` only runs `plan -destroy`.
- Order and data-centre use: [docs/DEPLOYMENT_SEQUENCE.md](../../docs/DEPLOYMENT_SEQUENCE.md).

### What `configure` does

```mermaid
graph TD
    A[configure] --> B[WireGuard up]
    B --> C[terraform output: compute + storage]
    C --> D[ansible/inventory/generate.py --from-terraform]
    D --> E[mint Rancher import cmd - if enabled]
    E --> F["ansible/site.yml<br/>preflight → tls+nginx → rke2 → rancher import<br/>→ nfs → postgresql → activemq → rancher+keycloak<br/>(profile selects which)"]
    F --> G[Rancher: fresh import, team grants, publish KUBECONFIG - if enabled]
```

### State files

`{provider}-{component}-{profile}-{branch}-terraform.tfstate` per root
(`base-infra` has no profile). With the local backend only the `.gpg` file is
committed, e.g.

```
terraform/implementations/aws/base-infra/aws-base-infra-<branch>-terraform.tfstate.gpg
terraform/implementations/aws/compute/profiles/<profile>/aws-compute-<profile>-<branch>-terraform.tfstate.gpg
```

### PR checks

`infra-checks.yml` runs on pull requests: `terraform fmt -check`,
`terraform test` for every module, `terraform validate` for every root, the
inventory generator's unit tests and a `site.yml` syntax check per profile.

## Security & Access Control

### Required GitHub Secrets
```yaml
# GPG Encryption for State Files
GPG_PRIVATE_KEY: |
 -----BEGIN PGP PRIVATE KEY BLOCK-----
 <your-gpg-private-key>
 -----END PGP PRIVATE KEY BLOCK-----

# SSH Access for jumpserver
SSH_PRIVATE_KEY: |
 -----BEGIN OPENSSH PRIVATE KEY-----
 <your-private-key-content>
 -----END OPENSSH PRIVATE KEY-----

# AWS Credentials (Complete Implementation)
AWS_ACCESS_KEY_ID: AKIA...
AWS_SECRET_ACCESS_KEY: wJalr...

# Azure Credentials (Placeholder Implementation)
AZURE_CLIENT_ID: 12345678-1234-1234-1234-123456789012
AZURE_CLIENT_SECRET: secret-value
AZURE_SUBSCRIPTION_ID: 12345678-1234-1234-1234-123456789012
AZURE_TENANT_ID: 12345678-1234-1234-1234-123456789012

# GCP Credentials (Placeholder Implementation)
GOOGLE_CREDENTIALS: |
 {
 "type": "service_account",
 "project_id": "your-project",
 ...
 }

# Optional: Slack notifications
SLACK_WEBHOOK_URL: https://hooks.slack.com/services/...
```

### Security Best Practices
- **GPG encryption**: All state files encrypted before commit
- **Least privilege access**: IAM roles with minimal required permissions
- **Secret rotation**: Regular rotation of access keys and GPG keys
- **Audit logging**: CloudTrail/Activity logs enabled for all operations
- **Network isolation**: Resources deployed in private subnets
- **Database security**: PostgreSQL with encrypted storage and secure access

## Workflow Examples

```yaml
# One-time network
COMPONENT: base-infra
TERRAFORM_APPLY: true

# Observability cluster (optional, before MOSIP clusters that import into it)
COMPONENT: all
PROFILE: observ
TERRAFORM_APPLY: true

# MOSIP cluster, registered in Rancher
COMPONENT: all
PROFILE: mosip
TERRAFORM_APPLY: true
ENABLE_RANCHER_IMPORT: true

# Later: change DNS records only
COMPONENT: dns
PROFILE: mosip
TERRAFORM_APPLY: true
```

Then the Helmsman workflows: `helmsman_external.yml` → `helmsman_mosip.yml`
→ `helmsman_esignet.yml` → `helmsman_testrigs.yml`.

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| **GPG Decryption Failed** | Invalid GPG private key | Verify GPG_PRIVATE_KEY secret is correct |
| **State File Not Found** | Missing encrypted state | Check .terraform-state/ directory for .gpg files |
| **Provider Auth Failed** | Invalid credentials | Check cloud provider secrets configuration |
| **Module Not Found** | Git access issues | Verify SSH key has repository access |
| **PostgreSQL Connection Failed** | Database not ready | Wait for Ansible PostgreSQL setup to complete |
| **Azure/GCP Placeholder Error** | Incomplete implementation | Use AWS or contribute to Azure/GCP modules |

### Debug Steps
1. **Check workflow logs**: Review GitHub Actions execution logs
2. **Validate GPG key**: Ensure GPG_PRIVATE_KEY secret is configured
3. **Verify cloud credentials**: Check AWS/Azure/GCP secrets
4. **Test connectivity**: Verify network access to cloud APIs
5. **State inspection**: Decrypt and inspect state files manually
6. **PostgreSQL logs**: Check Ansible output for database setup

### Cloud Provider Debugging

#### AWS (Full Support)
- Check IAM permissions for EC2, VPC, RDS
- Verify region availability and quota limits
- Test AWS CLI connectivity with provided credentials

#### Azure/GCP (Placeholder)
- Current implementations use `null_resource` placeholders
- No actual cloud resources are created
- Community contributions needed for full implementation

## Integration with Terraform Components

### GitHub Actions Workflow Sequence
```mermaid
sequenceDiagram
 participant User
 participant Terraform Workflows
 participant Helmsman Workflows
 participant AWS Infrastructure
 participant PostgreSQL
 
 User->>Terraform Workflows: 1. Deploy base-infra
 Terraform Workflows->>AWS Infrastructure: Create VPC, WireGuard
 AWS Infrastructure-->>User: Base infrastructure ready
 
 User->>Terraform Workflows: 2. Deploy COMPONENT=all (profile)
 Terraform Workflows->>AWS Infrastructure: security, compute, iam, storage, dns
 Terraform Workflows->>PostgreSQL: configure: Ansible site.yml (RKE2, nginx, PostgreSQL 15, ...)
 AWS Infrastructure-->>User: MOSIP cluster + PostgreSQL ready
 
 User->>Helmsman Workflows: 3. Deploy Prerequisites (parallel)
 User->>Helmsman Workflows: 3. Deploy External Dependencies (parallel)
 Helmsman Workflows-->>AWS Infrastructure: Install Prerequisites & Dependencies
 AWS Infrastructure-->>User: Prerequisites & Dependencies ready (70-110 min)
 
 User->>Helmsman Workflows: 4. Deploy MOSIP Services
 Helmsman Workflows->>PostgreSQL: Connect to external database
 AWS Infrastructure-->>User: MOSIP platform operational
 
 User->>Helmsman Workflows: 5. Deploy eSignet Stack (optional)
 Helmsman Workflows->>PostgreSQL: Init eSignet database
 Helmsman Workflows-->>AWS Infrastructure: Install eSignet, Redis, SoftHSM, OIDC UI
 AWS Infrastructure-->>User: eSignet stack operational
```

### Workflow Execution Order

1. **Terraform Workflows** (Sequential - Infrastructure Setup):
 - `terraform.yml` → Deploy base-infra
 - `terraform.yml` → `COMPONENT=all`, `PROFILE=observ` (optional)
 - `terraform.yml` → `COMPONENT=all`, `PROFILE=mosip` / `esignet-standalone`

2. **Helmsman Workflows** (Can run in parallel after Terraform complete):
 - `helmsman_external.yml` → Prerequisites + External Dependencies (simultaneous)
 - `helmsman_mosip.yml` → MOSIP Services (after external dependencies ready)
 - `helmsman_esignet.yml` → eSignet Stack (after MOSIP DSF or standalone)
 - `helmsman_testrigs.yml` → Test components (optional)

### Parallel Deployment Architecture
```mermaid
graph TD
 A[Terraform Infrastructure Complete] --> B[Helmsman Workflows Triggered]
 
 B --> C[Prerequisites Workflow]
 B --> D[External Dependencies Workflow]
 
 C -->|Parallel| E[Monitoring Stack]
 C -->|Parallel| F[Istio Service Mesh]
 C -->|Parallel| G[Logging Infrastructure]
 
 D -->|Parallel| H[PostgreSQL Connection]
 D -->|Parallel| I[MinIO Storage]
 D -->|Parallel| J[Keycloak IAM]
 D -->|Parallel| K[Kafka Messaging]
 
 E --> L[MOSIP Services Deployment]
 F --> L
 G --> L
 H --> L
 I --> L
 J --> L
 K --> L
 
 L --> M{Deploy eSignet?}
 M -->|Yes| N[eSignet Stack Deployment<br/>Redis, SoftHSM, Keycloak Init,<br/>eSignet, OIDC UI, Mock Identity]
 M -->|No| O[Optional: Test Rigs]
 N --> O
 
 style A fill:#e1f5fe,stroke:#01579b,stroke-width:2px,color:#000000
 style B fill:#e8f5e8,stroke:#1b5e20,stroke-width:2px,color:#000000
 style C fill:#fff3e0,stroke:#f57c00,stroke-width:2px,color:#000000
 style D fill:#fff3e0,stroke:#f57c00,stroke-width:2px,color:#000000
 style L fill:#f3e5f5,stroke:#4a148c,stroke-width:2px,color:#000000
 style N fill:#e0f2f1,stroke:#00695c,stroke-width:2px,color:#000000
```

**Sequential Dependency**: Terraform workflows must complete before Helmsman workflows 
**Parallel Optimization**: Prerequisites and External Dependencies run simultaneously via separate Helmsman workflows

---

## Support & Best Practices

- **Workflow Maintenance**: Keep workflows updated with latest Terraform versions 
- **State Management**: GPG encrypted state with branch-based isolation 
- **Security Reviews**: Regular rotation of GPG keys and cloud credentials 
- **PostgreSQL Management**: Automated setup via Ansible, selected per profile 
- **Performance Optimization**: Use parallel deployment for 20% faster setup times 

## Cloud Provider Contribution Guide

- **AWS** - Production ready with full feature set 
- **Azure** - [Placeholder implementation](../terraform/base-infra/azure/main.tf) - contributions welcome 
- **GCP** - [Placeholder implementation](../terraform/base-infra/gcp/main.tf) - contributions welcome 

**Community contributions needed for Azure and GCP implementations**

---

## eSignet Workflow (`helmsman_esignet.yml`)

Deploys the complete eSignet authentication stack including Redis, SoftHSM, Keycloak, Mock Identity System, Mock Relying Party, and Partner Onboarder.

### Triggers

| Trigger | Condition |
|---------|-----------|
| **Manual** | `workflow_dispatch` - Run from Actions tab |
| **Push** | When `Helmsman/dsf/esignet-dsf.yaml` is modified |

### Workflow Inputs (Manual Trigger)

| Input | Description | Required | Default |
|-------|-------------|----------|---------|  
| `mode` | Helmsman mode: `dry-run` or `apply` | Yes | `dry-run` |
| `skip_mosip_dsf_check` | Skip MOSIP DSF completion check for standalone deployment | No | `false` |

### Required GitHub Secrets

Configure in **Repository → Settings → Secrets and variables → Actions → Secrets**:

| Secret | Description | Required |
|--------|-------------|----------|
| `KUBECONFIG` | Kubernetes config file content | ✅ Yes |
| `CLUSTER_WIREGUARD_WG0` | WireGuard configuration for cluster access | ✅ Yes |
| `MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY` | Mock Relying Party client private key (base64 encoded PEM) | ✅ Yes |
| `MOCK_RELYING_PARTY_JWE_PRIVATE_KEY` | JWE userinfo private key (base64 encoded PEM) | ✅ Yes |

### Repository Variables (Optional)

Configure in **Repository → Settings → Secrets and variables → Actions → Variables**:

| Variable | Description | Values |
|----------|-------------|--------|
| `ESIGNET_STANDALONE_MODE` | Enable standalone mode for push-triggered runs | `true` / `false` |

### Creating Base64 Encoded Secrets

```bash
# Encode client private key (no line wrapping)
cat client-private-key.pem | base64 -w 0
# Copy output → Add as MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY secret

# Encode JWE userinfo private key
cat jwe-userinfo-private-key.pem | base64 -w 0
# Copy output → Add as MOCK_RELYING_PARTY_JWE_PRIVATE_KEY secret
```

### Deployment Modes

#### 1. Dependent Mode (Default)
Requires MOSIP DSF to be completed first. Checks for `mosip-dsf=completed` label on default namespace.

```
MOSIP DSF → eSignet DSF
```

#### 2. Standalone Mode
Skips MOSIP DSF check. Enable via:

| Trigger Type | How to Enable |
|--------------|--------------|
| Manual Run | Set `skip_mosip_dsf_check` to `true` in workflow UI |
| Push Triggered | Set repository variable `ESIGNET_STANDALONE_MODE=true` |

### eSignet Components Deployed

| Priority | Component | Description |
|----------|-----------|-------------|
| -19 | redis | Cache layer |
| -18 | softhsm-esignet | Hardware security module for eSignet |
| -15 | postgres-init-esignet | Database initialization |
| -14 | keycloak | Identity and access management |
| -13 | esignet-keycloak-init | Keycloak realm configuration |
| -12 | esignet | Core eSignet service |
| -11 | softhsm-mock-identity-system | HSM for mock identity |
| -11 | oidc-ui | OpenID Connect UI |
| -10 | mock-identity-system | Mock identity provider |
| -10 | partner-onboarder | Partner onboarding service |
| -9 | mock-relying-party-ui | Mock relying party frontend |
| -8 | mock-relying-party-service | Mock relying party backend |

### Security Features

- ✅ All secrets automatically masked in GitHub Actions logs
- ✅ Private keys passed as environment variables (never written to disk)
- ✅ WireGuard config written with restricted permissions (600)
- ✅ Kubeconfig stored with 400 permissions
- ✅ Explicit `::add-mask::` for additional protection

### Post-Deployment Verification

```bash
# Check all eSignet pods
kubectl get pods -n esignet

# Verify services
kubectl get svc -n esignet

# Check eSignet logs
kubectl logs -n esignet -l app=esignet

# Verify namespace label
kubectl get ns default --show-labels | grep esignet-dsf
```

### Troubleshooting

| Issue | Solution |
|-------|----------|
| `MOSIP DSF not completed` | Run MOSIP DSF workflow first OR enable standalone mode |
| `Secret not configured` | Add required secrets in repository settings |
| `WireGuard connection failed` | Verify `CLUSTER_WIREGUARD_WG0` contains valid config |
| Pods not starting | Check `kubectl logs -n esignet <pod-name>` for errors |

---

**Professional infrastructure automation with enterprise-grade security, PostgreSQL integration, and parallel deployment capabilities**
