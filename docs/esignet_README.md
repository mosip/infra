# eSignet DSF Deployment Guide

> **Complete guide for deploying eSignet authentication stack using Helmsman**

## Overview

The eSignet DSF (Desired State File) deploys a complete authentication stack including:
- **eSignet** - Core authentication service
- **Keycloak** - Identity and access management
- **Mock Identity System** - For testing/demo purposes
- **Mock Relying Party** - Sample relying party application
- **SoftHSM** - Hardware security module emulation
- **Redis** - Caching layer
- **OIDC UI** - OpenID Connect user interface

## Quick Start

### Prerequisites

1. Kubernetes cluster with Istio installed
2. External services deployed (prereq-dsf + external-dsf from `helmsman_external.yml`)
3. GitHub Actions secrets and Environment Variables configured
4. WireGuard VPN access to cluster


## Required Secrets (Environment Secrets)

> **Important:** All secrets must be configured as **Environment Secrets**, not Repository Secrets.
> The environment name matches the branch name (e.g., `main`, `develop`).

Configure in **Repository → Settings → Environments → `<branch-name>` → Add secret**:

| Secret | Description | Format |
|--------|-------------|--------|
| `KUBECONFIG` | Kubernetes config file | Raw YAML (plain text) |
| `CLUSTER_WIREGUARD_WG0` | WireGuard VPN configuration | Plain text (WireGuard config format) |
| `MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY` | Client private key for Mock RP | Base64 encoded PEM |
| `MOCK_RELYING_PARTY_JWE_PRIVATE_KEY` | JWE userinfo private key | Base64 encoded PEM |
| `ESIGNET_CAPTCHA_SITE_KEY` | Google reCAPTCHA site key | Plain text |
| `ESIGNET_CAPTCHA_SECRET_KEY` | Google reCAPTCHA secret key | Plain text |

> **eSignet standalone profile** requires additional per-namespace captcha secrets and Keycloak/Postgres passwords for MOSIP-ID1, MOSIP-ID2, and Sunbird environments. See [ESIGNET_STANDALONE_DEPLOYMENT_GUIDE.md](ESIGNET_STANDALONE_DEPLOYMENT_GUIDE.md) for the full secrets list.

### Creating Environment Secrets

1. Go to **Repository → Settings → Environments**
2. Click on your environment (e.g., `main`) or create a new one
3. Under **Environment secrets**, click **Add secret**
4. Add each secret listed above

### Creating Private Key Secrets

```bash
# Generate keys (if not already available)
openssl genrsa -out client-private-key.pem 2048
openssl genrsa -out jwe-userinfo-private-key.pem 2048

# Base64 encode for GitHub secrets (no line wrapping)
cat client-private-key.pem | base64 -w 0
# Copy output → Add as MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY

cat jwe-userinfo-private-key.pem | base64 -w 0
# Copy output → Add as MOCK_RELYING_PARTY_JWE_PRIVATE_KEY
```

### Creating KUBECONFIG Secret

> **Important:** KUBECONFIG must be provided as **raw YAML** (plain text), not base64 encoded.

```bash
# After Terraform infrastructure deployment, find the kubeconfig file in:
# terraform/implementations/aws/infra/kubeconfig_<cluster-name>

# Copy the entire contents of the kubeconfig file
cat terraform/implementations/aws/infra/kubeconfig_<cluster-name>
# Copy the raw YAML output → Add as KUBECONFIG (do NOT base64 encode)

# Example KUBECONFIG value (raw YAML format):
# apiVersion: v1
# clusters:
# - cluster:
#     certificate-authority-data: LS0tLS...
#     server: https://your-cluster-endpoint:6443
#   name: default
# contexts:
# ...
```

### Captcha Secrets

> **Note:** For detailed instructions on creating Google reCAPTCHA keys with screenshots, see [RECAPTCHA Setup Guide](./RECAPTCHA_SETUP_GUIDE.md).

Get reCAPTCHA keys from [Google reCAPTCHA Admin Console](https://www.google.com/recaptcha/admin):

1. Create a new site with reCAPTCHA v2 (Invisible)
2. Add your eSignet domain (e.g., `esignet.sandbox.xyz.net`)
3. Copy the **Site Key** → Add as GitHub Environment Secret `ESIGNET_CAPTCHA_SITE_KEY` (plain text, no encoding)
4. Copy the **Secret Key** → Add as GitHub Environment Secret `ESIGNET_CAPTCHA_SECRET_KEY` (plain text, no encoding)

**To add these secrets:**
- Go to **Repository → Settings → Environments → `<branch-name>` → Add secret**
- Add both keys exactly as copied from Google (no base64 encoding needed)



---

## Deployment Modes

### Default: MOSIP Platform

This guide covers eSignet deployed as part of a full MOSIP platform. eSignet is deployed **after** MOSIP core services are running:

```
helmsman_external.yml (profile=mosip-platform-1.2.0.x)
         ↓
helmsman_mosip.yml (auto-triggered)
         ↓
helmsman_esignet.yml (profile=mosip-platform-1.2.0.x)
```

Use `skip_mosip_dsf_check=false` (default) — the workflow checks for the `mosip-dsf=completed` label before deploying.

Set `skip_mosip_dsf_check=true` only if you need to re-run eSignet independently after it has already been deployed once.

> **For eSignet standalone** (no full MOSIP, 4 parallel instances): see [ESIGNET_STANDALONE_DEPLOYMENT_GUIDE.md](ESIGNET_STANDALONE_DEPLOYMENT_GUIDE.md).

---

## Components & Deployment Order

Components are deployed by priority (lower = earlier):

| Priority | Component | Namespace | Description |
|----------|-----------|-----------|-------------|
| -19 | redis | redis | Cache and session storage |
| -18 | softhsm-esignet | softhsm | HSM for eSignet keys |
| -15 | postgres-init-esignet | postgres | Database initialization |
| -14 | keycloak | keycloak | Identity provider |
| -13 | esignet-keycloak-init | esignet | Keycloak realm setup |
| -12 | esignet | esignet | Core eSignet service |
| -11 | softhsm-mock-identity-system | softhsm | HSM for mock identity |
| -11 | oidc-ui | esignet | OpenID Connect UI |
| -10 | mock-identity-system | esignet | Mock identity provider |
| -10 | partner-onboarder | esignet | Partner onboarding |
| -9 | mock-relying-party-ui | esignet | Mock RP frontend |
| -8 | mock-relying-party-service | esignet | Mock RP backend |

---

## DSF Configuration

### File Location

```
Helmsman/dsf/mosip-platform-1.2.0.x/esignet-dsf.yaml   (Java 11)
Helmsman/dsf/mosip-platform-1.2.1.x/esignet-dsf.yaml   (Java 21)
```

The workflow selects the correct subdirectory based on the `profile` input.

### Domain and Environment Configuration

**No manual domain edits needed in the DSF file.** All hostnames and service URLs are resolved via `${domain_name}` substitution at deploy time.

Set your domain as a GitHub Environment Variable:
- **Repository → Settings → Environments → `<branch-name>` → Variables → `DOMAIN_NAME`**

The workflow also reads `vars.ESIGNET_DB_PORT` for the PostgreSQL port (typically `5433` for MOSIP platform external postgres).

### Enable/Disable Components

```yaml
apps:
  redis:
    enabled: true    # Set to false to skip

  keycloak:
    enabled: false   # Use existing Keycloak

  mock-identity-system:
    enabled: true    # Disable for production
```

---

## Hooks

Pre-install and post-install hooks handle setup tasks:

| Hook | App | Purpose |
|------|-----|---------|
| `esignet-init-db.sh` | postgres-init-esignet | Initialize database |
| `esignet-preinstall-keycloak-init.sh` | esignet-keycloak-init | Copy Keycloak configs |
| `esignet-postinstall-keycloak-init.sh` | esignet-keycloak-init | Sync client secrets |
| `softhsm-esignet-setup.sh` | softhsm-esignet | Setup HSM namespace |
| `softhsm-esignet-postinstall.sh` | softhsm-esignet | Share HSM secrets |
| `esignet-preinstall.sh` | esignet | Setup prerequisites |
| `esignet-postinstall.sh` | esignet | Post-deployment config |
| `mock-relying-party-service-preinstall.sh` | mock-relying-party-service | Create private key secrets |
| `esignet-partner-onboarder-preinstall.sh` | partner-onboarder | Setup S3 configs |

### Hook Location
```
Helmsman/hooks/
```

---

## Values Files

Custom Helm values are stored in:

| File | Component |
|------|-----------|
| `utils/keycloak-init-values.yaml` | Keycloak realm configuration |
| `utils/softhsm-esignet-values.yaml` | SoftHSM for eSignet |
| `utils/softhsm-mock-identity-system-values.yaml` | SoftHSM for mock identity |
| `utils/postgres-values.yaml` | PostgreSQL configuration |

---

### Deploy via GitHub Actions

![Deploy eSignet - Helmsman](_images/esignet.png)

- **(1)** Go to **Actions** (top of the repository page) → click **"Deploy eSignet using Helmsman"** in the list on the left.
- **(2)** Click the **Run workflow** dropdown button (top right) — this opens the form shown above.
- **(3)** **Branch** — pick the branch you're deploying from (e.g., `MOSIP-44613`).
- **(4)** **Deployment profile to use** — pick the profile you want (e.g., `mosip-platform-1.2.0.x`, or `esignet-standalone` for standalone).
- **(5)** **Choose Helmsman mode: dry-run or apply** — always pick **`apply`**.
- **(6)** **Skip MOSIP DSF completion check** (checkbox) — for eSignet standalone deployments, tick this. For MOSIP platform profiles, leave it unticked (default) so the workflow waits for MOSIP to finish first.
- **(7)** **Delete existing onboarder jobs before deploy** (checkbox) — only tick this when re-running after a failure. Leave unticked on a first-time deploy.
- **(8)** **Domain name for this environment** — type the web domain this environment should use (e.g., `example.xyz.net`).
- **(9)** **PostgreSQL port for esignet databases** — type `5432` for eSignet standalone, or `5433` if this is part of a MOSIP platform profile.
- **(10)** **MOSIP-ID1 domain name** *(eSignet standalone only)* — base domain for the MOSIP-ID1 eSignet instance (e.g., `mosipid1.xyz.net`). Leave blank if you're not deploying MOSIP-ID1.
- **(11)** **Enable MOSIP-ID2 eSignet instance** *(eSignet standalone only)* — toggle to `true` to deploy the MOSIP-ID2 instance (softhsm, esignet, oidc-ui, mock-rp). Leave `false` to skip it entirely.
- **(12)** **MOSIP-ID2 domain name** *(eSignet standalone only, required if enable_mosipid2 is true)* — base domain for the MOSIP-ID2 eSignet instance (e.g., `mosipid2.xyz.net`).
- **(13)** **Environment name** — a short nickname for this environment (e.g., `sandbox`, `dev`, `staging`).
- **(14)** Click the green **Run workflow** button to start the deployment.

---

## GitHub Actions Workflow

### Triggers

| Trigger | Condition |
|---------|-----------|
| **Manual** | Run from Actions tab (`workflow_dispatch`) |
| **Push** | When `Helmsman/dsf/esignet-dsf.yaml` is modified |

### Workflow Inputs

| Input | Description | Required | Notes |
|-------|-------------|----------|-------|
| `profile` | Deployment profile | Yes | `mosip-platform-1.2.0.x`, `mosip-platform-1.2.1.x`, or `esignet-standalone` |
| `mode` | `dry-run` or `apply` | Yes | Always use `apply` — dry-run will fail |
| `domain_name` | Your base domain | Yes | Or set `vars.DOMAIN_NAME` in GitHub Environment |
| `esignet_db_port` | PostgreSQL port for esignet databases | Yes | `5433` for MOSIP platform external postgres, `5432` for eSignet standalone (or `vars.ESIGNET_DB_PORT`) |
| `mosipid1_domain_name` | Base domain for the MOSIP-ID1 eSignet instance | No | eSignet standalone only — leave blank otherwise (or `vars.MOSIPID1_DOMAIN_NAME`) |
| `enable_mosipid2` | Deploy MOSIP-ID2 eSignet instance | No | Toggle `true` to deploy softhsm, esignet, oidc-ui, mock-rp for mosipid2; default `false` |
| `mosipid2_domain_name` | Base domain for the MOSIP-ID2 eSignet instance | No | Required only if `enable_mosipid2` is `true` (or `vars.MOSIPID2_DOMAIN_NAME`) |
| `env_name` | Environment name shown on the landing page | Yes | Or set `vars.ENV_NAME` in GitHub Environment |
| `skip_mosip_dsf_check` | Skip MOSIP DSF completion check | No | Tick for eSignet standalone deploys; default `false` otherwise |
| `delete_existing_jobs` | Delete stale onboarder jobs before deploy | No | Set `true` when re-running after a failure |

---

## Security

### Secrets Protection

- ✅ All secrets masked in GitHub Actions logs
- ✅ Private keys passed via environment variables
- ✅ Never written to disk in plain text
- ✅ `::add-mask::` applied for extra protection

### Kubernetes Secrets Created

| Secret | Namespace | Source |
|--------|-----------|--------|
| `mock-relying-party-service-secrets` | esignet | GitHub Actions secret |
| `jwe-userinfo-service-secrets` | esignet | GitHub Actions secret |
| `keycloak-client-secrets` | esignet | Keycloak postInstall hook |

---

## Post-Deployment

### Verify Deployment

```bash
# Check namespace label
kubectl get ns default --show-labels | grep esignet-dsf

# Check all pods
kubectl get pods -n esignet

# Check services
kubectl get svc -n esignet

# Check ingress/virtualservices
kubectl get virtualservice -n esignet
```

### Access URLs (after deployment)

| Service | URL |
|---------|-----|
| eSignet UI | `https://esignet.YOUR_DOMAIN.net` |
| Keycloak Admin | `https://iam.YOUR_DOMAIN.net/auth/admin` |
| Mock Relying Party | `https://healthservices.YOUR_DOMAIN.net` |

### View Logs

```bash
# eSignet service logs
kubectl logs -n esignet -l app=esignet -f

# Keycloak logs
kubectl logs -n keycloak -l app.kubernetes.io/name=keycloak -f

# Mock Identity System logs
kubectl logs -n esignet -l app=mock-identity-system -f
```

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| `MOSIP DSF not completed` | Dependency check failed | Run MOSIP DSF first OR enable standalone mode |
| `Secret not configured` | Missing GitHub secret | Add required secrets in repository settings |
| `WireGuard connection failed` | Invalid VPN config | Verify `CLUSTER_WIREGUARD_WG0` secret |
| Pod `CrashLoopBackOff` | Configuration error | Check pod logs: `kubectl logs -n esignet <pod>` |
| `ImagePullBackOff` | Image not found | Verify image repository/tag in DSF |
| Database connection failed | Wrong host/port | Update `postgres.YOUR_DOMAIN.net:5433` |

### Debug Commands

```bash
# Check pod status and events
kubectl describe pod -n esignet <pod-name>

# Check namespace events
kubectl get events -n esignet --sort-by='.lastTimestamp'

# Check Helmsman releases
helm list -n esignet

# Check configmaps
kubectl get configmap -n esignet

# Check secrets (names only)
kubectl get secrets -n esignet
```

### Re-run Failed Hooks

```bash
# Set environment variables
export KUBECONFIG=/path/to/kubeconfig
export WORKDIR=/path/to/Helmsman

# Run specific hook manually
./hooks/esignet-preinstall.sh
```

---

## Local Development

### Run Helmsman Locally

```bash
# Set environment
export KUBECONFIG=~/.kube/config
export WORKDIR=$(pwd)/Helmsman
export domain_name=sandbox.example.net

# Apply eSignet (MOSIP platform profile — Java 11)
helmsman --apply -f $WORKDIR/dsf/mosip-platform-1.2.0.x/esignet-dsf.yaml

# Apply eSignet (MOSIP platform profile — Java 21)
helmsman --apply -f $WORKDIR/dsf/mosip-platform-1.2.1.x/esignet-dsf.yaml
```

### Test Individual Hooks

```bash
cd Helmsman
export WORKDIR=$(pwd)

# Test preinstall hook
./hooks/esignet-preinstall.sh

# Test postinstall hook  
./hooks/esignet-postinstall.sh
```

---

## Cleanup

### Uninstall eSignet Stack

```bash
# Using Helmsman (recommended — select your profile)
helmsman --destroy -f Helmsman/dsf/mosip-platform-1.2.0.x/esignet-dsf.yaml
# or
helmsman --destroy -f Helmsman/dsf/mosip-platform-1.2.1.x/esignet-dsf.yaml

# Or manually via Helm
helm uninstall esignet -n esignet
helm uninstall mock-identity-system -n esignet
helm uninstall mock-relying-party-ui -n esignet
helm uninstall mock-relying-party-service -n esignet
helm uninstall oidc-ui -n esignet
helm uninstall keycloak -n keycloak
helm uninstall softhsm-esignet -n softhsm
helm uninstall redis -n redis
```

### Delete Namespaces

```bash
kubectl delete ns esignet
kubectl delete ns softhsm
kubectl delete ns keycloak
kubectl delete ns redis
```

---

## Related Documentation

- [Helmsman DSF Guide](../README.md)
- [Workflows README](../../.github/workflows/README.md)
- [Secret Generation Guide](./SECRET_GENERATION_GUIDE.md)
- [Onboarding Guide](./ONBOARDING_GUIDE.md)

---

## Support

For issues or questions:
1. Check [Troubleshooting](#troubleshooting) section
2. Review GitHub Actions workflow logs
3. Open an issue in the repository
