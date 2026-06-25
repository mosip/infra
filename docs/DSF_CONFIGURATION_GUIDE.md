# DSF Configuration Guide

This guide explains how to configure Helmsman Desired State Files (DSF) for MOSIP and eSignet deployment, including the profile-based DSF structure, `clusterid` configuration, and domain/environment variable setup.

## Table of Contents

1. [Understanding DSF Files](#understanding-dsf-files)
2. [Prerequisites DSF Configuration](#prerequisites-dsf-configuration)
3. [External Dependencies DSF Configuration](#external-dependencies-dsf-configuration)
4. [MOSIP Services DSF Configuration](#mosip-services-dsf-configuration)
5. [Test Rigs DSF Configuration](#test-rigs-dsf-configuration)
6. [Common Configuration Patterns](#common-configuration-patterns)

---

## Understanding DSF Files

### What is a DSF File?

DSF (Desired State File) tells Helmsman:
- **What** applications to install
- **Which versions** to use
- **How** to configure them
- **Where** to deploy them

Think of it as a recipe that Helmsman follows to deploy your MOSIP or eSignet platform.

### Profile-Based DSF Structure

DSF files are organized by **deployment profile** — not a single flat folder. Each workflow takes a `profile` input that selects the correct subdirectory automatically.

| Profile | Use Case |
|---------|----------|
| `esignet` | eSignet standalone (authentication only, no full MOSIP core services) |
| `mosip-platform-1.2.0.x` | Full MOSIP platform with Java 11 |
| `mosip-platform-1.2.1.x` | Full MOSIP platform with Java 21 |

```
Helmsman/dsf/
├── esignet/                      # eSignet standalone profile
│   ├── prereq-dsf.yaml
│   ├── external-dsf.yaml
│   ├── esignet-dsf.yaml
│   ├── signup-dsf.yaml
│   └── testrigs-dsf.yaml
├── mosip-platform-1.2.0.x/       # Full MOSIP (Java 11) profile
│   ├── prereq-dsf.yaml
│   ├── external-dsf.yaml
│   ├── mosip-dsf.yaml
│   ├── esignet-dsf.yaml
│   └── testrigs-dsf.yaml
└── mosip-platform-1.2.1.x/       # Full MOSIP (Java 21) profile
    ├── prereq-dsf.yaml
    ├── external-dsf.yaml
    ├── mosip-dsf.yaml
    ├── esignet-dsf.yaml
    └── testrigs-dsf.yaml
```

### DSF File Types (per profile)

| File | Purpose | Deploy Order |
|------|---------|--------------|
| `prereq-dsf.yaml` | Monitoring, Istio, logging | 1st |
| `external-dsf.yaml` | Databases, queues, storage, Keycloak | 2nd |
| `mosip-dsf.yaml` | MOSIP core services (MOSIP platform profiles only) | 3rd |
| `esignet-dsf.yaml` | eSignet stack + OIDC UI + Mock RP | 4th (or 3rd for esignet profile) |
| `signup-dsf.yaml` | Signup stack (esignet profile only) | 5th (auto-triggered) |
| `testrigs-dsf.yaml` | Testing infrastructure | Last (optional) |

### Environment Variable Substitution

**No manual editing of DSF files is needed per environment.** All domain, port, and cluster values are resolved at deploy time via Helmsman's built-in `${VAR}` expansion.

| Variable | Resolved from | Example |
|----------|--------------|---------|
| `${domain_name}` | Workflow input or `vars.DOMAIN_NAME` | `sandbox.example.net` |
| `${env_name}` | Workflow input or `vars.ENV_NAME` | `sandbox` |
| `${clusterid}` | Workflow input or `vars.CLUSTER_ID` | `c-m-abc12xyz` |
| `${slack_channel_name}` | Workflow input or `vars.SLACK_CHANNEL_NAME` | `#mosip-alerts` |
| `${db_port}` | Workflow input or `vars.DB_PORT` | `5433` |
| `${esignet_db_port}` | Workflow input or `vars.ESIGNET_DB_PORT` | `5432` |

Configure these under: **Repository → Settings → Environments → `<branch-name>` → Variables**

For push-triggered runs (no `workflow_dispatch` inputs), the workflow reads these variables automatically. For manual runs, you can override them via workflow inputs.

---

## Prerequisites DSF Configuration

**File**: `Helmsman/dsf/prereq-dsf.yaml`

**Purpose**: Deploys monitoring stack, Istio service mesh, and logging

### Critical Configuration: clusterid

#### What is clusterid?

The `clusterid` is a unique identifier for your Rancher-managed Kubernetes cluster. It's used by Rancher Monitoring to correctly identify and track your cluster's metrics.

#### Why is it Important?

Without the correct `clusterid`:
- ❌ Monitoring dashboards won't display correct cluster data
- ❌ Grafana may show metrics from wrong cluster
- ❌ Alerts and notifications may not work properly

#### How to Find Your clusterid

**Option 1: From Rancher UI (Recommended)**

1. Log in to Rancher UI
 ```
 URL: https://rancher.your-domain.net
 ```

2. Navigate to your cluster
 ```
 Home → Clusters → Click on your MOSIP cluster
 ```

3. Get clusterid from URL
 ```
 URL format: https://rancher.example.net/c/c-m-abc12xyz/explorer
 ^^^^^^^^^^^^
 This is your clusterid
 ```

4. Copy the clusterid
 ```
 Example: c-m-pbrcfglw
 c-m-abc12xyz
 c-m-5x9k7w3d
 ```

**Option 2: Using kubectl**

```bash
# Connect to your cluster with kubectl
export KUBECONFIG=/path/to/kubeconfig

# Get clusterid from cluster registration
kubectl get setting cluster-id -n cattle-system -o jsonpath='{.value}'

# Output example:
# c-m-pbrcfglw
```

**Option 3: From Terraform Outputs**

```bash
# If Rancher import was enabled during Terraform deployment
cd terraform/implementations/aws/infra/
terraform output rancher_cluster_id
```

#### How to Set clusterid for Deployment

**Previously**, `clusterid` had to be manually hardcoded in `prereq-dsf.yaml`. Now it is passed via GitHub Environment Variables — no DSF edits needed.

**Set it as a GitHub Environment Variable:**

1. Go to **Repository → Settings → Environments → `<branch-name>` → Variables**
2. Add variable: `CLUSTER_ID` = your clusterid (e.g. `c-m-abc12xyz`)

The DSF file reads it automatically via `${clusterid}` substitution at deploy time. For manual `workflow_dispatch` runs, you can also pass it directly as the `clusterid` workflow input.

**How the DSF uses it (no changes needed):**

```yaml
apps:
 rancher-monitoring:
 namespace: cattle-monitoring-system
 enabled: true
 version: 103.1.0+up45.31.1
 chart: mosip/rancher-monitoring
 set:
 grafana.global.cattle.clusterId: "${clusterid}"  # resolved from vars.CLUSTER_ID
 global.cattle.clusterId: "${clusterid}"          # resolved from vars.CLUSTER_ID
 wait: true
 valuesFile: "$WORKDIR/utils/monitoring_values.yaml"
 priority: -5
 timeout: 600
```

### Complete prereq-dsf.yaml Configuration

#### Domain Configuration

**Previously**, domain placeholders like `<sandbox>` and `sandbox.xyz.net` had to be manually replaced throughout each DSF file. This is no longer needed.

All domain values are now resolved via `${domain_name}` substitution at deploy time.

**Set your domain as a GitHub Environment Variable:**

1. Go to **Repository → Settings → Environments → `<branch-name>` → Variables**
2. Add variable: `DOMAIN_NAME` = your domain (e.g. `soil38.mosip.net`)

The DSF files reference `${domain_name}` and `${env_name}` everywhere a domain or environment name is needed — no file edits required.

**Example — how it works (no changes needed to the DSF):**

```yaml
hooks:
 postInstall: "$WORKDIR/hooks/install-istio-and-httpbin.sh ${env_name} helmsman"
 # env_name is resolved from vars.ENV_NAME (e.g. "soil38")
```

#### Monitoring Configuration Options

```yaml
apps:
 # CRDs (Custom Resource Definitions) - Always deploy first
 rancher-monitoring-crd:
 namespace: cattle-monitoring-system
 enabled: true # Keep enabled
 version: 103.1.1+up45.31.1
 chart: mosip/rancher-monitoring-crd
 priority: -6 # Highest priority (deploys first)
 
 # Main monitoring stack
 rancher-monitoring:
 namespace: cattle-monitoring-system
 enabled: true # Set to false to disable monitoring
 # If disabled, Grafana and Prometheus won't be installed
```

#### Logging Configuration (Optional)

```yaml
apps:
 logging:
 namespace: cattle-logging-system
 enabled: false # Set to true to enable logging
 # When enabled, installs Fluentd/Elasticsearch/Kibana stack
```

**When to enable logging:**
- Need centralized log aggregation
- Debugging complex issues
- Compliance requirements
- Performance analysis

**Cost considerations:**
- Logging consumes significant storage
- Requires additional resources (CPU/memory)
- Recommended for production, optional for development

---

## External Dependencies DSF Configuration

**File**: `Helmsman/dsf/external-dsf.yaml`

**Purpose**: Deploys databases, message queues, storage, and identity management

### Critical Configurations

#### 1. Domain Configuration

**No manual domain edits needed.** All hostnames and domain references in `external-dsf.yaml` use `${domain_name}` substitution, resolved from `vars.DOMAIN_NAME` in the GitHub Environment.

For the eSignet standalone profile, make sure `vars.ESIGNET_DB_PORT=5432` (container postgres, default port). For MOSIP platform profiles, set `vars.DB_PORT=5433` (external postgres, custom port).

#### 2. PostgreSQL Configuration

**Location**: Around line 50-100

**Decision Point**: Container PostgreSQL vs External PostgreSQL

| Configuration | When to Use | Setting |
|--------------|-------------|---------|
| **Container** | Development, testing | `enabled: true` |
| **External** | Production, deployed via Terraform | `enabled: false` |

**For Container PostgreSQL**:
```yaml
apps:
 postgres:
 namespace: postgres
 enabled: true # ← Set to true
 chart: mosip/postgres
 version: 14.0.0
 priority: -11
 set:
 # PostgreSQL version
 image.tag: "15.8.0-debian-12-r0"
```

**For External PostgreSQL (Terraform-deployed)**:
```yaml
apps:
 postgres:
 namespace: postgres
 enabled: false # ← Set to false (skip container)
 # External PostgreSQL connection details are in terraform outputs
```

**Important**: This setting must match your Terraform configuration:
```hcl
# In terraform/implementations/aws/infra/aws.tfvars
enable_postgresql_setup = true # External → postgres.enabled = false
enable_postgresql_setup = false # Container → postgres.enabled = true
```

#### 3. reCAPTCHA Configuration

**Location**: Around line 315

**Purpose**: Protects MOSIP web portals from bots

**Configuration**:
```yaml
apps:
 captcha:
 enabled: true
 hooks:
 postInstall: "$WORKDIR/hooks/captcha-setup.sh PREREG_SITE_KEY PREREG_SECRET_KEY ADMIN_SITE_KEY ADMIN_SECRET_KEY RESIDENT_SITE_KEY RESIDENT_SECRET_KEY"
```

**How to get keys**: See [Secret Generation Guide - reCAPTCHA](SECRET_GENERATION_GUIDE.md#6-recaptcha-keys)

**Example with actual keys**:
```yaml
hooks:
 postInstall: "$WORKDIR/hooks/captcha-setup.sh 6LfkAMwrAAAAAATB1WhkIhzuAVMtOs9VWabODoZ_ 6LfkAMwrAAAAAHQAT93nTGcLKa-h3XYhGoNSG-NL 6LdNAcwrAAAAAETGWvz-3I12vZ5V8vPJLu2ct9CO 6LdNAcwrAAAAAE4iWGJ-g6Dc2HreeJdIwAl5h1iL 6LdRAcwrAAAAAFUEHHKK5D_bSrwAPqdqAJqo4mCk 6LdRAcwrAAAAAOeVl6yHGBCBA8ye9GsUOy4pi9s9"
```

**Key Order (CRITICAL)**:
1. PreReg Site Key
2. PreReg Secret Key
3. Admin Site Key
4. Admin Secret Key
5. Resident Site Key
6. Resident Secret Key

#### 4. MinIO Configuration (Object Storage)

**Location**: Around line 150-200

```yaml
apps:
 minio:
 namespace: minio
 enabled: true # Required for MOSIP file storage
 chart: mosip/minio
 version: 5.0.14
 priority: -11
 set:
 # Storage capacity
 persistence.size: "100Gi" # Adjust based on needs
 
 # Resource limits
 resources.requests.memory: "2Gi"
 resources.limits.memory: "4Gi"
```

**Storage recommendations:**
- **Development**: 50-100 GB
- **Testing**: 100-200 GB
- **Production**: 500+ GB

#### 5. Kafka Configuration (Message Queue)

**Location**: Around line 250-300

```yaml
apps:
 kafka:
 namespace: kafka
 enabled: true # Required for MOSIP async communication
 chart: mosip/kafka
 version: 22.1.5
 priority: -11
 set:
 # Kafka cluster sizing
 replicaCount: 3 # Number of Kafka brokers
 
 # ZooKeeper configuration
 zookeeper.replicaCount: 3 # Number of ZooKeeper nodes
```

**Sizing recommendations:**
- **Development**: 1 broker, 1 ZooKeeper
- **Testing**: 3 brokers, 3 ZooKeeper
- **Production**: 3+ brokers, 3+ ZooKeeper

#### 6. Keycloak Configuration (Identity Management)

**Location**: Around line 350-400

```yaml
apps:
 keycloak-init:
 namespace: keycloak
 enabled: true # Required for authentication
 chart: mosip/keycloak-init
 version: 12.0.1
 priority: -10
 set:
 # Admin credentials (auto-generated)
 # Database connection (auto-configured)
 
 # Domain configuration
 istio.hosts:
 - "iam.sandbox.xyz.net" # ← Replace with your domain
```

---

## MOSIP Services DSF Configuration

**File**: `Helmsman/dsf/mosip-dsf.yaml`

**Purpose**: Deploys all MOSIP core application services

### Critical Configurations

#### 1. Domain Configuration

**No manual domain edits needed.** All service hostnames in `mosip-dsf.yaml` use `${domain_name}` substitution resolved from `vars.DOMAIN_NAME`. The `${env_name}` variable (from `vars.ENV_NAME`) is used for the landing page name and other environment-specific labels.

#### 2. Database Branch Configuration

**Location**: Multiple locations, look for `dbBranch`

```yaml
apps:
 config-server:
 set:
 # CRITICAL: Must match your MOSIP version
 gitRepo.dbBranch: "v1.2.0.2" # ← Update to your MOSIP version
```

**How to determine correct branch:**

| MOSIP Version | DB Branch |
|---------------|-----------|
| 1.2.0.2 | `v1.2.0.2` |
| 1.2.0.3 | `v1.2.0.3` |
| Latest | Check MOSIP releases |

**Where to find your MOSIP version:**
- Check Helm chart versions in DSF file
- Refer to your deployment requirements
- Match with MOSIP official releases

#### 3. Chart Versions

**Update all chart versions** to latest compatible releases:

```yaml
apps:
 config-server:
 version: 12.0.2 # Check for updates
 chart: mosip/config-server
 
 artifactory:
 version: 12.0.1 # Check for updates
 chart: mosip/artifactory
 
 kernel:
 version: 1.2.0.2 # Match MOSIP version
 chart: mosip/kernel
```

**Where to find latest versions:**
- MOSIP Helm Repository: https://mosip.github.io/mosip-helm
- GitHub Releases: https://github.com/mosip/mosip-helm/releases

#### 4. Resource Limits

**Adjust based on environment:**

```yaml
apps:
 prereg-application:
 set:
 # Resource requests (minimum guaranteed)
 resources.requests.cpu: "500m"
 resources.requests.memory: "1Gi"
 
 # Resource limits (maximum allowed)
 resources.limits.cpu: "2000m"
 resources.limits.memory: "4Gi"
```

**Environment-based recommendations:**

| Environment | CPU Request | Memory Request | CPU Limit | Memory Limit |
|-------------|-------------|----------------|-----------|--------------|
| **Development** | 250m | 512Mi | 1000m | 2Gi |
| **Testing** | 500m | 1Gi | 2000m | 4Gi |
| **Production** | 1000m | 2Gi | 4000m | 8Gi |

#### 5. Replica Counts

**Scale services based on load:**

```yaml
apps:
 kernel-auth:
 set:
 replicaCount: 3 # Number of pod replicas
```

**Scaling recommendations:**

| Service Type | Development | Testing | Production |
|--------------|-------------|---------|------------|
| **Auth Services** | 1 | 2 | 3-5 |
| **Core Services** | 1 | 2 | 3 |
| **Batch Jobs** | 1 | 1 | 1-2 |
| **Web Apps** | 1 | 2 | 3-5 |

---

## Test Rigs DSF Configuration

**File**: `Helmsman/dsf/testrigs-dsf.yaml`

**Purpose**: Deploys automated testing infrastructure

### When to Deploy

**Deploy test rigs when:**
- ✅ All MOSIP services are running
- ✅ All pods show `Running` status
- ✅ Partner onboarding completed successfully
- ✅ You need automated testing

**Skip test rigs when:**
- ❌ This is a production environment
- ❌ MOSIP services are not stable
- ❌ You don't need automated testing

### Critical Configurations

#### 1. Test Endpoints

All API endpoints in `testrigs-dsf.yaml` use `${domain_name}` substitution — no manual edits needed. For the eSignet profile, `${mosipid1_domain_name}` and `${mosipid2_domain_name}` are also used for the MOSIP-ID1 and MOSIP-ID2 testrig database hosts. Set these as GitHub Environment Variables:
- `vars.MOSIPID1_DOMAIN_NAME` (e.g. `mosipid1.example.net`)
- `vars.MOSIPID2_DOMAIN_NAME` (e.g. `mosipid2.example.net`)

#### 2. Test Data Configuration

```yaml
apps:
 apitestrig:
 set:
 # Test data branch — match your MOSIP version
 testDataBranch: "v1.2.0.2"
```

#### 3. Test Rig Resources

```yaml
apps:
 apitestrig:
 set:
 resources.requests.memory: "2Gi"
 resources.limits.memory: "4Gi"
```

**Recommendations:**
- API Test Rig: 2-4 GB memory
- DSL Test Rig: 4-8 GB memory 
- UI Test Rig: 4-8 GB memory

---

## Common Configuration Patterns

### Pattern 1: Enabling/Disabling Services

**To disable a service:**
```yaml
apps:
 service-name:
 enabled: false # Service will not be deployed
```

**To enable a service:**
```yaml
apps:
 service-name:
 enabled: true # Service will be deployed
```

**Common uses:**
- Disable logging in development to save resources
- Disable test rigs in production
- Disable optional monitoring components

---

### Pattern 2: Domain Configuration

**All DSF files** use `${domain_name}` substitution — a single environment variable drives all domain references consistently across every DSF.

**Set once, used everywhere:**

```
vars.DOMAIN_NAME = soil38.mosip.net
```

This resolves in all DSFs at deploy time:

```yaml
# prereq-dsf.yaml (resolved at runtime)
postInstall: "$WORKDIR/hooks/install-istio-and-httpbin.sh ${env_name} helmsman"

# external-dsf.yaml
istio.hosts:
 - "postgres.${domain_name}"

# mosip-dsf.yaml
istio.hosts:
 - "prereg.${domain_name}"

# testrigs-dsf.yaml
apiEndpoint: "https://api.${domain_name}"
```

**Consistency checklist:**
- [ ] `vars.DOMAIN_NAME` matches Terraform `cluster_env_domain`
- [ ] `vars.ENV_NAME` matches Terraform `cluster_name`
- [ ] DNS records exist for all subdomains in Route 53

---

### Pattern 3: Chart Version Management

**Check and update versions regularly:**

```yaml
apps:
 service-name:
 version: 12.0.1 # Chart version
 chart: mosip/service-name # Chart repository/name
```

**Version compatibility matrix:**

| MOSIP Version | Config Server | Kernel | Auth | PreReg |
|---------------|---------------|--------|------|--------|
| 1.2.0.2 | 12.0.2 | 1.2.0.2 | 1.2.0.2 | 1.2.0.2 |
| 1.2.0.3 | 12.0.3 | 1.2.0.3 | 1.2.0.3 | 1.2.0.3 |

**Always check**: https://github.com/mosip/mosip-helm/releases

---

### Pattern 4: Priority Configuration

**Deploy order is controlled by priority:**

```yaml
priority: -20 # Deploy first (highest priority)
priority: -10 # Deploy second
priority: 0 # Deploy last (lowest priority)
```

**Standard priorities:**
- `-20` to `-15`: Infrastructure (databases, queues)
- `-14` to `-10`: External services (Keycloak, MinIO)
- `-9` to `-5`: Core services (config-server)
- `-4` to `0`: Application services

**Example:**
```yaml
apps:
 postgres:
 priority: -20 # Deploy first (database needed by all)
 
 keycloak:
 priority: -10 # Deploy second (auth needed by services)
 
 config-server:
 priority: -5 # Deploy third (config needed by apps)
 
 prereg:
 priority: 0 # Deploy last (depends on above)
```

---

## Configuration Validation Checklist

### Before Deploying any DSF

- [ ] GitHub Environment Variables set for your branch (`vars.DOMAIN_NAME`, `vars.ENV_NAME`, `vars.CLUSTER_ID`, `vars.SLACK_CHANNEL_NAME`)
- [ ] Port variables set: `vars.DB_PORT` (MOSIP platform profiles), `vars.ESIGNET_DB_PORT` (eSignet profile)
- [ ] For eSignet profile: `vars.MOSIPID1_DOMAIN_NAME` and `vars.MOSIPID2_DOMAIN_NAME` also set
- [ ] No manual `<sandbox>` or domain placeholder edits needed in DSF files

### Before Deploying prereq-dsf.yaml

- [ ] `vars.CLUSTER_ID` set with your Rancher clusterid (e.g. `c-m-abc12xyz`)
- [ ] Monitoring enabled/disabled as needed
- [ ] Chart versions are latest stable

### Before Deploying external-dsf.yaml

- [ ] PostgreSQL `enabled` matches Terraform setting
- [ ] reCAPTCHA keys configured as GitHub Environment Secrets
- [ ] MinIO storage size appropriate
- [ ] Kafka cluster size appropriate

### Before Deploying mosip-dsf.yaml

- [ ] Database branch matches MOSIP version
- [ ] Chart versions compatible
- [ ] Resource limits appropriate for environment
- [ ] Replica counts set correctly

### Before Deploying testrigs-dsf.yaml

- [ ] All MOSIP/eSignet services running
- [ ] Test data branch matches MOSIP version
- [ ] `vars.MOSIPID1_DOMAIN_NAME` and `vars.MOSIPID2_DOMAIN_NAME` set (esignet profile)

---

## Troubleshooting DSF Configurations

### Issue: clusterid Error

**Symptom**: Monitoring dashboards show wrong cluster or no data

**Solution**:
1. Verify clusterid in Rancher UI (URL path `c-m-xxxxx`) or via `kubectl get setting cluster-id -n cattle-system -o jsonpath='{.value}'`
2. Update the GitHub Environment Variable: **Repository → Settings → Environments → `<branch-name>` → Variables → `CLUSTER_ID`**
3. Re-run the prereq workflow — the DSF picks up `${clusterid}` from the updated variable automatically

---

### Issue: Domain Resolution Failures

**Symptom**: Services can't be accessed via domain names

**Solution**:
1. Check DNS records in Route 53
2. Verify `vars.DOMAIN_NAME` in the GitHub Environment matches Terraform `cluster_env_domain` — no manual DSF edits needed
3. Check subdomain configuration in Terraform:
 ```hcl
 subdomain_public = ["resident", "prereg", ...]
 subdomain_internal = ["admin", "iam", ...]
 ```

---

### Issue: PostgreSQL Connection Failures

**Symptom**: Services can't connect to database

**Solution**:
1. Verify PostgreSQL enabled setting matches Terraform:
 ```yaml
 # If Terraform enable_postgresql_setup = true
 postgres:
 enabled: false # Use external
 
 # If Terraform enable_postgresql_setup = false
 postgres:
 enabled: true # Use container
 ```
2. Check database branch matches MOSIP version
3. Verify database init jobs completed successfully

---

### Issue: Version Incompatibilities

**Symptom**: Services fail to start or crash repeatedly

**Solution**:
1. Check MOSIP version compatibility matrix
2. Ensure all chart versions are compatible
3. Update database branch to match service versions
4. Refer to MOSIP release notes for breaking changes

---

## Quick Reference

### Essential Settings (GitHub Environment Variables)

| Setting | Variable | Where to set | Purpose |
|---------|----------|-------------|---------|
| Domain name | `vars.DOMAIN_NAME` | GitHub Environment Variables | All DSFs — hostnames, Istio VS, DB hosts |
| Environment name | `vars.ENV_NAME` | GitHub Environment Variables | Landing page name, testrig user |
| Rancher cluster ID | `vars.CLUSTER_ID` | GitHub Environment Variables | rancher-monitoring in prereq-dsf |
| Slack channel | `vars.SLACK_CHANNEL_NAME` | GitHub Environment Variables | Alerting in prereq-dsf |
| MOSIP postgres port | `vars.DB_PORT` | GitHub Environment Variables | MOSIP platform external postgres (5433) |
| eSignet postgres port | `vars.ESIGNET_DB_PORT` | GitHub Environment Variables | eSignet container postgres (5432) |
| MOSIP-ID1 domain | `vars.MOSIPID1_DOMAIN_NAME` | GitHub Environment Variables | esignet profile — MOSIP-ID1 testrig hosts |
| MOSIP-ID2 domain | `vars.MOSIPID2_DOMAIN_NAME` | GitHub Environment Variables | esignet profile — MOSIP-ID2 testrig hosts |

**DSF file manual edits (one-time per environment):**

| Setting | File | Purpose |
|---------|------|---------|
| `postgres.enabled` | `external-dsf.yaml` | `true` = container PostgreSQL, `false` = external (Terraform-managed) |
| `dbBranch` | `mosip-dsf.yaml` | DB scripts version — must match MOSIP version |
| Domain values | `Helmsman/utils/global_configmap.yaml` | Shared ConfigMap consumed by all services |

---

## Need More Help?

- **Workflow Execution**: [Workflow Guide](WORKFLOW_GUIDE.md)
- **Secret Configuration**: [Secret Generation Guide](SECRET_GENERATION_GUIDE.md)
- **Technical Terms**: [Glossary](GLOSSARY.md)
- **Main Documentation**: [README](../README.md)

---

**Navigation**: [Back to Main README](../README.md) | [View All Docs](.)
