# Helmsman Destroy Guide

This guide provides comprehensive instructions for safely destroying and undeploying MOSIP services from Kubernetes clusters using Helmsman. Follow these steps carefully to ensure clean removal and proper resource cleanup.

## Table of Contents

1. [GitHub Actions Destroy Workflows](#github-actions-destroy-workflows)
2. [When to Destroy Helmsman Deployments](#when-to-destroy-helmsman-deployments)
3. [Pre-Destruction Checklist](#pre-destruction-checklist)
4. [Destruction Order (Critical!)](#destruction-order-critical)
5. [Verification and Cleanup](#verification-and-cleanup)
6. [Data Backup and Recovery](#data-backup-and-recovery)
7. [Troubleshooting Destruction](#troubleshooting-destruction)

---

## GitHub Actions Destroy Workflows

This section explains the CI/CD-based approach to destroying Helmsman deployments using GitHub Actions workflows.

### Architecture Overview

The destroy workflows follow a **reusable workflow pattern**:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Reusable Workflow (Core Engine)                      │
│                    destroy-resources.yml                                │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │ • Sets up kubectl, Helm, WireGuard                                │  │
│  │ • Connects to cluster via VPN                                     │  │
│  │ • Uninstalls Helm releases from specified namespaces              │  │
│  │ • Deletes namespaces                                              │  │
│  │ • Verifies cleanup                                                │  │
│  │ • Removes DSF labels                                              │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                                    ▲
                                    │ uses
        ┌───────────────┬───────────┼───────────┬───────────────┐
        │               │           │           │               │
        ▼               ▼           ▼           ▼               ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│  Testrigs    │ │    MOSIP     │ │   External   │ │ Prerequisites│
│   Destroy    │ │   Destroy    │ │   Destroy    │ │   Destroy    │
│  Workflow    │ │  Workflow    │ │  Workflow    │ │  Workflow    │
└──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘
```

### Available Destroy Workflows

| Workflow                            | File                                       | Purpose                       | Namespaces Affected                                                                                                                                                                                                              |
| ----------------------------------- | ------------------------------------------ | ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Destroy Testrigs**          | `helmsman_testrigs_destroy.yml`          | Removes test rig services     | `apitestrig`, `dslrig`, `uitestrig`                                                                                                                                                                                        |
| **Destroy MOSIP Services**    | `helmsman_mosip_destroy.yml`             | Removes core MOSIP services   | `admin`, `apitestrig`, `artifactory`, `config-server`, `dslrig`, `esignet`, `idrepo`, `kernel`, `masterdata`, `packet-manager`, `pmp`, `postgresdb`, `print`, `regproc`, `resident`, `uitestrig` |
| **Destroy External Services** | `helmsman_external_destroy_external.yml` | Removes external dependencies | `keycloak`, `kafka`, `minio`, `softhsm`, `clamav`, `activemq`, `landing-page`                                                                                                                                      |
| **Destroy Prerequisites**     | `helmsman_external_destroy_prereq.yml`   | Removes monitoring and Istio  | `cattle-logging-system`, `istio-system`, `monitoring`                                                                                                                                                                      |

### Reusable Workflow: `destroy-resources.yml`

The **Destroy Kubernetes Resources (Reusable)** workflow is the core engine used by all 4 destroy workflows. It provides a standardized, secure approach to resource cleanup.

#### Input Parameters

| Parameter                 | Type   | Required | Description                                                                       |
| ------------------------- | ------ | -------- | --------------------------------------------------------------------------------- |
| `namespace_selection`   | string | Yes      | `all` or `specific` - determines namespace scope                              |
| `specific_namespaces`   | string | No       | Comma-separated list of namespaces (used when `specific` is selected)           |
| `all_namespaces`        | string | Yes      | Space-separated list of all namespaces for this deployment type                   |
| `dsf_label`             | string | Yes      | DSF label to remove from default namespace (e.g.,`mosip-dsf`, `testrigs-dsf`) |
| `wireguard_secret_name` | string | Yes      | WireGuard secret name (e.g.,`CLUSTER_WIREGUARD_WG0`)                            |
| `deployment_type`       | string | Yes      | Type of deployment (e.g.,`MOSIP`, `Testrigs`, `External`)                   |

#### What the Reusable Workflow Does

1. **Environment Setup**

   - Checks out repository
   - Installs kubectl (v1.31.3) with checksum verification
   - Sets up Helm
   - Configures KUBECONFIG from secrets
2. **Network Configuration**

   - Installs WireGuard
   - Configures firewall (UFW)
   - Establishes VPN connection to cluster
3. **Resource Destruction**

   - Iterates through target namespaces
   - Uninstalls all Helm releases in each namespace
   - Deletes the namespaces
4. **Verification & Cleanup**

   - Verifies namespaces are deleted
   - Removes DSF labels from default namespace

### Step-by-Step: How to Use Destroy Workflows

#### Step 1: Navigate to GitHub Actions

1. Go to your repository on GitHub
2. Click the **Actions** tab
3. In the left sidebar, find the destroy workflow you need

#### Step 2: Select the Appropriate Workflow

Choose the workflow based on what you want to destroy:

| If You Want to Destroy...                  | Use This Workflow                                     |
| ------------------------------------------ | ----------------------------------------------------- |
| Test rigs only                             | `Destroy Testrigs using Helmsman`                   |
| MOSIP core services                        | `Destroy MOSIP services using Helmsman`             |
| External dependencies (Kafka, MinIO, etc.) | `Destroy External services of MOSIP using Helmsman` |
| Prerequisites (Istio, monitoring)          | `Destroy Prerequisite services of MOSIP using Helm` |

#### Step 3: Trigger the Workflow

1. Click **Run workflow** button (right side)
2. Select the target branch (e.g., `release-0.2.0`)
3. Fill in the required inputs:

   **Confirmation** (Required):

   ```
   destroy
   ```

   > ⚠️ You MUST type exactly `destroy` to confirm. Any other value will cancel the workflow.
   >

   **Namespace Selection** (Required):

   - `all` - Destroy all namespaces for this deployment type
   - `specific` - Destroy only specified namespaces

   **Specific Namespaces** (Optional - only if `specific` is selected):

   ```
   namespace1,namespace2,namespace3
   ```

   > Comma-separated list, no spaces around commas
   >
4. Click **Run workflow**

#### Step 4: Monitor Execution

1. Click on the running workflow to see progress
2. Watch the job steps:

   - ✅ Validate destruction confirmation
   - ✅ Setup kubectl and kubeconfig
   - ✅ Install WireGuard
   - ✅ Configure and start WireGuard
   - ✅ Setup Helm
   - ✅ Verify cluster access
   - ✅ Destroy services using Helm
   - ✅ Verify resource cleanup
   - ✅ Remove DSF label
3. Check logs for any errors or warnings

#### Step 5: Verify Destruction

After workflow completes:

```bash
# Connect to cluster
export KUBECONFIG=<path-to-kubeconfig>

# Check remaining namespaces
kubectl get namespaces

# Check remaining Helm releases
helm list -A

# Check remaining pods
kubectl get pods -A
```

### Destruction Order Using Workflows

**CRITICAL: Always destroy in reverse order of deployment!**

```
Deployment Order:              Destruction Order (Use Workflows):
───────────────────────────────────────────────────────────────────
1. Prerequisites          →    4. Destroy Prerequisites Workflow
2. External Dependencies  →    3. Destroy External Workflow
3. MOSIP Services        →    2. Destroy MOSIP Workflow
4. Test Rigs             →    1. Destroy Testrigs Workflow
```

**Correct Workflow Execution Order:**

1. **First**: Run `Destroy Testrigs using Helmsman`
2. **Second**: Run `Destroy MOSIP services using Helmsman`
3. **Third**: Run `Destroy External services of MOSIP using Helmsman`
4. **Fourth**: Run `Destroy Prerequisite services of MOSIP using Helm`

### When to Use Each Mode

#### Use `all` Namespace Selection When:

- ✅ Performing complete teardown of a deployment layer
- ✅ Preparing for fresh redeployment
- ✅ Decommissioning an environment

#### Use `specific` Namespace Selection When:

- ✅ Removing only specific services
- ✅ Troubleshooting a particular namespace
- ✅ Partial cleanup needed
- ✅ Testing destruction process

### Example: Selective Namespace Destruction

**Scenario**: You only want to destroy the API test rig and DSL rig, but keep UI test rig.

1. Go to **Actions** → **Destroy Testrigs using Helmsman**
2. Click **Run workflow**
3. Enter:
   - **Branch**: `release-0.2.0`
   - **Confirmation**: `destroy`
   - **Namespace selection**: `specific`
   - **Specific namespaces**: `apitestrig,dslrig`
4. Click **Run workflow**

### Required Secrets

The destroy workflows require these repository secrets:

| Secret                    | Description                                                   |
| ------------------------- | ------------------------------------------------------------- |
| `KUBECONFIG`            | Kubernetes cluster configuration                              |
| `CLUSTER_WIREGUARD_WG0` | WireGuard configuration for main cluster                      |
| `CLUSTER_WIREGUARD_WG1` | WireGuard configuration for external services (if applicable) |

### Troubleshooting Workflows

#### Workflow Fails at Confirmation Step

**Error**: `Destruction cancelled. You must type 'destroy' to confirm.`

**Solution**: Ensure you typed exactly `destroy` (lowercase, no quotes, no spaces).

#### Workflow Fails at WireGuard Step

**Error**: WireGuard connection fails

**Solution**:

1. Verify `CLUSTER_WIREGUARD_WG0` or `CLUSTER_WIREGUARD_WG1` secret is configured
2. Check VPN endpoint is reachable
3. Verify WireGuard configuration is valid

#### Workflow Fails at Helm Uninstall

**Error**: Helm uninstall times out

**Solution**:

1. Check if resources have finalizers preventing deletion
2. Manually connect to cluster and check pod status
3. Re-run workflow after resolving stuck resources

#### Namespace Still Exists After Workflow

**Cause**: Resources with finalizers preventing deletion

**Solution**:

```bash
# Check what's blocking deletion
kubectl api-resources --verbs=list --namespaced=true | \
  xargs -n 1 kubectl get --show-kind --ignore-not-found -n <namespace>

# Remove finalizers if needed
kubectl patch ns <namespace> -p '{"metadata":{"finalizers":null}}'
```

---

## When to Destroy Helmsman Deployments

### Reasons to Destroy Services

| Scenario                     | Action                             | Data Backup        |
| ---------------------------- | ---------------------------------- | ------------------ |
| **Testing/Demo**       | Destroy services after testing     | Not required       |
| **Redeployment**       | Destroy before redeploying         | Recommended        |
| **Service Cleanup**    | Remove unused applications         | Not required       |
| **Production Cleanup** | Remove old versions before upgrade | **REQUIRED** |
| **Disk Space**         | Free up persistent volumes         | **REQUIRED** |
| **Cost Reduction**     | Remove non-critical services       | Recommended        |

---

## Pre-Destruction Checklist

### Before Destroying Any Services, Complete These Steps

**⚠️ Critical - Complete these BEFORE any destruction:**

- [ ] **Backup all critical data**

  - [ ] PostgreSQL databases exported
  - [ ] MinIO objects backed up
  - [ ] Kafka topics/messages archived
  - [ ] Keycloak configurations exported
  - [ ] All persistent volume data copied
- [ ] **Stop automated processes**

  - [ ] Stop all test rig schedulers
  - [ ] Stop any running batch jobs
  - [ ] Pause any integration processes
  - [ ] Stop cron jobs in dslrig, apitestrig, uitestrig namespaces
- [ ] **Notify stakeholders**

  - [ ] Alert team members of planned destruction
  - [ ] Ensure no active users/integrations
  - [ ] Pause any dependent services
- [ ] **Document current state**

  - [ ] Note deployed versions
  - [ ] Document custom configurations
  - [ ] Save any custom DSF modifications
  - [ ] Export Rancher cluster registrations (if using Rancher)
- [ ] **Verify cluster connectivity**

  - [ ] KUBECONFIG is valid and accessible
  - [ ] VPN connection active
  - [ ] kubectl commands working

```bash
# Test cluster connectivity
kubectl get nodes
kubectl get namespaces
```

---

## Destruction Order (Critical!)

**IMPORTANT: Always destroy in reverse order of deployment!**

```
Deployment Order:           Destruction Order:
1. Prerequisites       ←→   4. Destroy Prerequisites
2. External Deps      ←→   3. Destroy External Deps
3. MOSIP Services     ←→   2. Destroy MOSIP Services
4. Test Rigs          ←→   1. Destroy Test Rigs
```

**Why reverse order matters:**

- Services depend on external dependencies
- External dependencies depend on prerequisites
- Test rigs depend on all MOSIP services
- Destroying in wrong order causes orphaned resources

---

## Verification and Cleanup

> **Note**: The destroy workflows automatically verify resource cleanup. Use these commands for additional manual verification if needed.

### Verify Services Are Destroyed

```bash
# Check all Helm releases across namespaces
helm list -A
# Expected: Empty or only system releases

# Check all pods
kubectl get pods -A
# Expected: Only system pods (kube-system, kube-public, etc.)

# Check persistent volumes
kubectl get pvc -A
kubectl get pv
```

### Post-Workflow Cleanup (If Needed)

If any resources remain after workflow execution:

```bash
# Delete remaining PVCs
kubectl delete pvc <pvc-name> -n <namespace>

# Delete released PVs
kubectl get pv | grep Released | awk '{print $1}' | xargs kubectl delete pv

# Delete remaining LoadBalancer services (to stop AWS costs)
kubectl get svc -A | grep LoadBalancer
kubectl delete svc <service-name> -n <namespace>
```

---

## Data Backup and Recovery

> **Important**: Always backup data BEFORE running destroy workflows.

### Before Destruction: Backup Strategy

#### PostgreSQL Backup

```bash
# Backup single database
kubectl exec -it deployment/postgres -n postgres -- \
  pg_dump -U postgres <database-name> > backup_<database-name>.sql

# Backup all databases
kubectl exec -it deployment/postgres -n postgres -- \
  pg_dumpall -U postgres > backup_all_databases.sql

# Backup to file in pod
kubectl exec -it deployment/postgres -n postgres -- \
  pg_dump -U postgres mosip_keycloak > /tmp/backup.sql

# Copy from pod to local
kubectl cp postgres/deployment-pod:/tmp/backup.sql ./backup.sql -n postgres
```

#### MinIO Backup

```bash
# Port forward to MinIO
kubectl port-forward svc/minio -n external 9000:9000 &

# Setup mc (MinIO CLI)
mc alias set minio http://localhost:9000 minioadmin minioadmin

# Mirror all buckets
mc mirror minio ./minio_backup/

# Or backup specific bucket
mc mirror minio/bucket-name ./bucket_backup/
```

#### ConfigMaps and Secrets Backup

```bash
# Backup all ConfigMaps
kubectl get cm -A -o yaml > configmaps_backup.yaml

# Backup all Secrets
kubectl get secrets -A -o yaml > secrets_backup.yaml

# Backup specific namespace
kubectl get cm,secret -n mosip -o yaml > mosip_config_backup.yaml
```

#### Keycloak Backup

```bash
# Export Keycloak realm configuration
kubectl exec -it deployment/keycloak -n keycloak -- \
  /bin/bash -c 'keycloak export-realm --realm master' > keycloak_realm_backup.json

# Backup Keycloak database (if using PostgreSQL)
kubectl exec -it deployment/postgres -n postgres -- \
  pg_dump -U postgres keycloak > keycloak_db_backup.sql
```

### After Destruction: Recovery

#### Restore PostgreSQL

```bash
# Deploy PostgreSQL again
# Then restore from backup
kubectl exec -it deployment/postgres -n postgres -- \
  psql -U postgres < backup_all_databases.sql

# Or specific database
kubectl exec -it deployment/postgres -n postgres -- \
  psql -U postgres <database-name> < backup_<database-name>.sql
```

#### Restore MinIO Data

```bash
# After MinIO is deployed:
kubectl port-forward svc/minio -n external 9000:9000 &

# Mirror backup back to MinIO
mc mirror ./minio_backup/ minio/

# Verify restoration
mc ls minio/ -r
```

---

## Troubleshooting Destruction

### Services Won't Uninstall

**Issue**: Helm uninstall hangs or fails

```bash
# Force uninstall without waiting
helm uninstall <release> -n <namespace> --no-hooks

# Or delete helm secret directly
kubectl delete secret sh.helm.release.<release>.v1 -n <namespace>
```

### Persistent Volumes Won't Delete

**Issue**: PVCs stuck in "Terminating" state

```bash
# Check PVC status
kubectl get pvc -n <namespace>

# Describe PVC to see issues
kubectl describe pvc <pvc-name> -n <namespace>

# Remove finalizers if stuck
kubectl patch pvc <pvc-name> -n <namespace> -p '{"metadata":{"finalizers":null}}'

# Delete PVC
kubectl delete pvc <pvc-name> -n <namespace>
```

### Namespaces Won't Delete

**Issue**: Namespace stuck in "Terminating" state

```bash
# Check namespace status
kubectl get ns <namespace>

# See what's preventing deletion
kubectl api-resources --verbs=list --namespaced=true | \
  xargs -n 1 kubectl get --show-kind --ignore-not-found -n <namespace>

# Remove finalizers from namespace
kubectl patch ns <namespace> -p '{"metadata":{"finalizers":null}}'
```

### Services Left Behind

**Issue**: Some services still exist after uninstall

```bash
# Check all resources in namespace
kubectl get all -n <namespace>

# Describe remaining resources
kubectl describe deployment <name> -n <namespace>

# Manually delete remaining resources
kubectl delete deployment,statefulset,daemonset --all -n <namespace>
```

---

## Cleanup Confirmation Checklist

After running destruction, verify everything is cleaned up:

- [ ] All Helm releases removed: `helm list -A` returns empty (except system)
- [ ] All pods removed: `kubectl get pods -A` shows only system pods
- [ ] All services removed: `kubectl get svc -A` shows only system services
- [ ] All PVCs deleted: `kubectl get pvc -A` returns empty
- [ ] All PVs cleaned: `kubectl get pv` shows no "Released" volumes
- [ ] All namespaces deleted: `kubectl get ns` shows only system namespaces
- [ ] Load balancers removed in AWS Console (check ELB/ALB)
- [ ] No orphaned volumes in AWS (check EBS volumes)
- [ ] No DNS entries leftover (check Route 53)

---

## Cost Implications

### What Gets Destroyed vs. What Remains

**Destroyed (Stops Incurring Costs):**

- ✅ Helm releases and services
- ✅ Deployments and pods
- ✅ ConfigMaps and secrets
- ✅ Persistent volumes (if namespace deleted)

**Remains (Still Incurs Costs if Infrastructure Exists):**

- ⚠️ Kubernetes nodes (require Terraform destroy)
- ⚠️ Load balancers (require Terraform destroy)
- ⚠️ Database volumes (if external PostgreSQL, requires Terraform destroy)
- ⚠️ Network resources (require Terraform destroy)

**To fully stop costs, you must also run:**

```bash
# Terraform destroy for full cleanup
terraform destroy -var-file=implementations/aws/infra/aws.tfvars
```

See [Environment Destruction Guide](ENVIRONMENT_DESTRUCTION_GUIDE.md) for complete infrastructure teardown.

---

## Related Documentation

- **Infrastructure Destruction**: [Environment Destruction Guide](ENVIRONMENT_DESTRUCTION_GUIDE.md)
- **DSF Configuration**: [DSF Configuration Guide](DSF_CONFIGURATION_GUIDE.md)
- **Helmsman Overview**: [Helmsman README](../Helmsman/README.md)
- **Workflow Guide**: [GitHub Actions Workflow Guide](WORKFLOW_GUIDE.md)

---

## Getting Help

If you encounter issues:

1. Check the [Troubleshooting Destruction](#troubleshooting-destruction) section
2. Review cluster logs: `kubectl logs -n <namespace> <pod-name>`
3. Check Helm release status: `helm status <release> -n <namespace>`
4. Review GitHub Actions workflow logs for automation-based destruction

---

*For questions or issues, refer to MOSIP community support channels.*
