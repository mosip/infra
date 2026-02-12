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
2. MOSIP DSF deployed (or run in standalone mode)
3. GitHub Actions secrets configured
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

## Repository Variables (Optional)

Configure in **Repository → Settings → Secrets and variables → Actions → Variables**:

| Variable | Description | Values |
|----------|-------------|--------|
| `ESIGNET_STANDALONE_MODE` | Skip MOSIP DSF check for push-triggered runs | `true` / `false` |

---

## Deployment Modes

### 1. Dependent Mode (Default)

Requires MOSIP DSF to be completed first. The workflow checks for `mosip-dsf=completed` label.

```
┌─────────────┐     ┌─────────────┐
│  MOSIP DSF  │ ──► │ eSignet DSF │
└─────────────┘     └─────────────┘
```

### 2. Standalone Mode

Deploy eSignet independently without MOSIP DSF dependency.

**Enable via:**

| Trigger | Method |
|---------|--------|
| Manual run | Set `skip_mosip_dsf_check = true` |
| Push triggered | Set `ESIGNET_STANDALONE_MODE = true` variable |

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
Helmsman/dsf/esignet-dsf.yaml
```

### Key Configurations to Update

Update these values for your environment:

```yaml
# Domain configurations (replace sandbox.xyz.net)
keycloakExternalHost: "iam.YOUR_DOMAIN.net"
istio.hosts[0]: "esignet.YOUR_DOMAIN.net"
mock_relying_party_ui.mock_relying_party_ui_service_host: "healthservices.YOUR_DOMAIN.net"

# PostgreSQL host
databases.mosip_esignet.host: "postgres.YOUR_DOMAIN.net"
databases.mosip_esignet.port: 5433

# eSignet URLs
mock_relying_party_ui.ESIGNET_UI_BASE_URL: "https://esignet.YOUR_DOMAIN.net"
mock_relying_party_service.ESIGNET_AUD_URL: "https://esignet.YOUR_DOMAIN.net/v1/esignet/oauth/v2/token"
```

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

1. Go to **Actions** → **Deploy eSignet using Helmsman**
2. Select mode: `dry-run` (preview) or `apply` (deploy)
3. Click **Run workflow**

---

## GitHub Actions Workflow

### Triggers

| Trigger | Condition |
|---------|-----------|
| **Manual** | Run from Actions tab (`workflow_dispatch`) |
| **Push** | When `Helmsman/dsf/esignet-dsf.yaml` is modified |

### Workflow Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `mode` | `dry-run` (preview) or `apply` (deploy) | Yes | `dry-run` |
| `skip_mosip_dsf_check` | Skip MOSIP DSF dependency check | No | `false` |

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

# Dry run (preview changes)
helmsman --dry-run -f $WORKDIR/dsf/esignet-dsf.yaml

# Apply changes
helmsman --apply -f $WORKDIR/dsf/esignet-dsf.yaml
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
# Using Helmsman (recommended)
helmsman --destroy -f Helmsman/dsf/esignet-dsf.yaml

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
