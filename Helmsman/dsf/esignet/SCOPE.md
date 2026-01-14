# eSignet DSF Creation - Scope Document

## Project Overview

**Ticket:** MOSIP-43143  
**Branch:** MOSIP-43143  
**Objective:** Create Helmsman Desired State File (DSF) for automated eSignet stack deployment

---

## Scope Summary

Convert legacy shell-based eSignet installation scripts to Helmsman DSF pattern with automated hooks, enabling GitOps-based deployment via GitHub Actions.

---

## Deliverables

### 1. eSignet DSF File

**File:** `Helmsman/dsf/esignet-dsf.yaml`

| Component | Chart | Version | Priority | Status |
|-----------|-------|---------|----------|--------|
| postgres | bitnami/postgresql | 13.1.5 | -18 | Optional |
| istio-addons-psql | local chart | 0.1.0 | -17 | Optional |
| postgres-init-esignet | mosip/postgres-init | 12.0.1 | -16 | ✅ Enabled |
| redis | bitnami/redis | 17.3.14 | -15 | ✅ Enabled |
| softhsm-esignet | mosip/softhsm | 12.0.1 | -14 | ✅ Enabled |
| keycloak | mosip/keycloak | 7.1.18 | -13 | Optional |
| istio-addons-iam | local chart | 0.1.0 | -12 | ✅ Enabled |
| esignet-keycloak-init | mosip/keycloak-init | 12.0.2 | -11 | ✅ Enabled |
| esignet | mosip/esignet | 1.4.1 | -10 | ✅ Enabled |
| oidc-ui | mosip/oidc-ui | 1.4.1 | -9 | ✅ Enabled |
| softhsm-mock-identity-system | mosip/softhsm | 12.0.1 | -8 | ✅ Enabled |
| mock-identity-system | mosip/mock-identity-system | 0.9.3 | -7 | ✅ Enabled |
| mock-relying-party-ui | mosip/mock-relying-party-ui | 0.9.3 | -6 | ✅ Enabled |
| mock-relying-party-service | mosip/mock-relying-party-service | 0.9.3 | -5 | ✅ Enabled |
| esignet-resident-oidc-partner-onboarder | mosip/partner-onboarder | 12.0.1 | -4 | ✅ Enabled |
| esignet-demo-oidc-partner-onboarder | mosip/partner-onboarder | 12.0.1 | -3 | ✅ Enabled |

**Total Apps:** 16 (14 enabled by default)

---

### 2. Helmsman Hooks Created

**Location:** `Helmsman/hooks/`

| Hook Script | Type | Purpose |
|-------------|------|---------|
| `esignet-init-db.sh` | preInstall | Database initialization for eSignet |
| `redis-setup.sh` | postInstall | Redis namespace and Istio setup |
| `softhsm-esignet-setup.sh` | preInstall | SoftHSM namespace preparation |
| `softhsm-esignet-postinstall.sh` | postInstall | Share SoftHSM secrets to esignet namespace |
| `esignet-preinstall-keycloak-init.sh` | preInstall | Copy Keycloak configmaps/secrets |
| `esignet-postinstall-keycloak-init.sh` | postInstall | Sync Keycloak client secrets, config-server env vars |
| `esignet-preinstall.sh` | preInstall | Captcha/MISP secrets setup |
| `esignet-postinstall.sh` | postInstall | Config-server env vars, restart deployments |
| `oidc-ui-preinstall.sh` | preInstall | OIDC UI namespace preparation |
| `softhsm-mock-identity-system-preinstall.sh` | preInstall | Mock identity SoftHSM setup |
| `softhsm-mock-identity-system-postinstall.sh` | postInstall | Share SoftHSM secrets |
| `mock-identity-system-preinstall.sh` | preInstall | Copy configmaps (global, artifactory, config-server, softhsm) |
| `mock-relying-party-ui-preinstall.sh` | preInstall | Namespace and Istio label setup |
| `mock-relying-party-service-preinstall.sh` | preInstall | Create private key secrets from GitHub Actions secrets |
| `esignet-partner-onboarder-preinstall.sh` | preInstall | S3 configmaps, Keycloak secrets |
| `esignet-partner-onboarder-postinstall.sh` | postInstall | MISP/OIDC key sync, resident deployment updates |
| `esignet-demo-oidc-partner-onboarder-preinstall.sh` | preInstall | S3 configmaps, namespace setup |
| `esignet-demo-oidc-partner-onboarder-postinstall.sh` | postInstall | Extract keypair/clientId, update mock-relying-party |

**Total Hooks:** 18

---

### 3. Values Files Created

**Location:** `Helmsman/utils/`

| File | Purpose |
|------|---------|
| `keycloak-init-values.yaml` | Keycloak realm, roles, clients, client_scopes configuration |
| `softhsm-esignet-values.yaml` | SoftHSM configuration for eSignet |
| `softhsm-mock-identity-system-values.yaml` | SoftHSM configuration for Mock Identity System |

---

### 4. GitHub Actions Workflow

**File:** `.github/workflows/helmsman_esignet.yml`

#### Features:
- Manual trigger with `dry-run` / `apply` mode
- Push trigger on `esignet-dsf.yaml` changes
- Standalone mode support (skip MOSIP DSF dependency check)
- Secret validation before deployment
- WireGuard VPN setup for cluster access
- Deployment summary and namespace labeling

#### Required GitHub Secrets:

| Secret | Description |
|--------|-------------|
| `KUBECONFIG` | Kubernetes config file |
| `CLUSTER_WIREGUARD_WG0` | WireGuard VPN configuration |
| `MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY` | Client private key (base64 encoded PEM) |
| `MOCK_RELYING_PARTY_JWE_PRIVATE_KEY` | JWE userinfo private key (base64 encoded PEM) |

#### Repository Variables (Optional):

| Variable | Description |
|----------|-------------|
| `ESIGNET_STANDALONE_MODE` | Enable standalone mode for push-triggered runs |

---

### 5. Documentation

| Document | Location | Purpose |
|----------|----------|---------|
| eSignet DSF README | `Helmsman/dsf/esignet/README.md` | Comprehensive deployment guide |
| Workflows README Update | `.github/workflows/README.md` | Added eSignet workflow documentation |

---

## Key Features Implemented

### Idempotent Hooks
All hooks are designed to be idempotent:
- Check if resources exist before creating
- Use `--dry-run=client -o yaml | kubectl apply -f -` pattern
- Skip operations if already completed
- Safe for re-runs

### Secret Management
- No secrets stored in values.yaml files
- Private keys passed via GitHub Actions secrets (base64 encoded)
- Automatic masking in workflow logs
- Secrets created as Kubernetes secrets in target namespaces

### Deployment Modes
1. **Dependent Mode** (default): Requires MOSIP DSF completion
2. **Standalone Mode**: Independent eSignet deployment

### Cross-Namespace Resource Sharing
- ConfigMaps and Secrets copied between namespaces using `copy_cm_func.sh`
- Supports: global, config-server-share, artifactory-share, keycloak, s3, softhsm

---

## Namespaces Created/Used

| Namespace | Components |
|-----------|------------|
| `postgres` | postgres, postgres-init-esignet |
| `redis` | redis |
| `softhsm` | softhsm-esignet, softhsm-mock-identity-system |
| `keycloak` | keycloak, istio-addons-iam |
| `esignet` | esignet, oidc-ui, mock-identity-system, mock-relying-party-*, partner-onboarder |

---

## Configuration Points

### Domain Configuration (Update for your environment)
```yaml
# Replace sandbox.xyz.net with your domain
keycloakExternalHost: "iam.YOUR_DOMAIN.net"
istio.hosts[0]: "esignet.YOUR_DOMAIN.net"
mock_relying_party_ui.mock_relying_party_ui_service_host: "healthservices.YOUR_DOMAIN.net"
databases.mosip_esignet.host: "postgres.YOUR_DOMAIN.net"
```

### S3/MinIO Configuration
```yaml
onboarding.configmaps.s3.s3-host: "http://minio.minio:9000"
onboarding.configmaps.s3.s3-bucket-name: "onboarder"
```

### Security Configuration
```yaml
enable_insecure: "false"  # Set to true only for development without SSL
```

---

## Legacy Scripts Converted

| Legacy Script | Converted To |
|---------------|--------------|
| `install.sh` (esignet) | DSF app + hooks |
| `install.sh` (keycloak-init) | DSF app + hooks |
| `install.sh` (softhsm) | DSF app + hooks |
| `install.sh` (mock-identity-system) | DSF app + hooks |
| `install.sh` (mock-relying-party-ui) | DSF app + hooks |
| `install.sh` (mock-relying-party-service) | DSF app + hooks |
| `install.sh` (partner-onboarder resident-oidc) | DSF app + hooks |
| `install.sh` (partner-onboarder demo-oidc) | DSF app + hooks |
| `copy_cm.sh` | Integrated into preInstall hooks |
| `copy_secrets.sh` | Integrated into preInstall hooks |

---

## Testing Checklist

- [ ] Dry-run mode works without errors
- [ ] Apply mode deploys all components in correct order
- [ ] Hooks execute successfully (preInstall and postInstall)
- [ ] Secrets are created correctly in target namespaces
- [ ] Cross-namespace configmap/secret copying works
- [ ] Partner onboarder jobs complete successfully
- [ ] Demo OIDC client ID is extracted and applied
- [ ] Mock Relying Party services start with correct configuration
- [ ] Standalone mode works without MOSIP DSF dependency
- [ ] Workflow completes and labels namespace on success

---

## Out of Scope

- Keycloak deployment (uses existing Keycloak from MOSIP DSF)
- PostgreSQL deployment (uses existing PostgreSQL)
- Istio installation (prerequisite)
- Base infrastructure (handled by Terraform workflows)
- MOSIP core services deployment

---

## Dependencies

| Dependency | Required For |
|------------|--------------|
| MOSIP DSF completed | Dependent mode (default) |
| Keycloak running | esignet-keycloak-init |
| PostgreSQL running | postgres-init-esignet |
| MinIO/S3 running | partner-onboarder |
| Config Server running | esignet, mock-identity-system |
| Istio installed | All services (mesh networking) |

---

## Files Changed/Created Summary

### New Files Created (22 files)

```
Helmsman/dsf/esignet-dsf.yaml
Helmsman/dsf/esignet/README.md
Helmsman/hooks/esignet-init-db.sh
Helmsman/hooks/redis-setup.sh
Helmsman/hooks/softhsm-esignet-setup.sh
Helmsman/hooks/softhsm-esignet-postinstall.sh
Helmsman/hooks/esignet-preinstall-keycloak-init.sh
Helmsman/hooks/esignet-postinstall-keycloak-init.sh
Helmsman/hooks/esignet-preinstall.sh
Helmsman/hooks/esignet-postinstall.sh
Helmsman/hooks/oidc-ui-preinstall.sh
Helmsman/hooks/softhsm-mock-identity-system-preinstall.sh
Helmsman/hooks/softhsm-mock-identity-system-postinstall.sh
Helmsman/hooks/mock-identity-system-preinstall.sh
Helmsman/hooks/mock-relying-party-ui-preinstall.sh
Helmsman/hooks/mock-relying-party-service-preinstall.sh
Helmsman/hooks/esignet-partner-onboarder-preinstall.sh
Helmsman/hooks/esignet-partner-onboarder-postinstall.sh
Helmsman/hooks/esignet-demo-oidc-partner-onboarder-preinstall.sh
Helmsman/hooks/esignet-demo-oidc-partner-onboarder-postinstall.sh
Helmsman/utils/keycloak-init-values.yaml
Helmsman/utils/softhsm-esignet-values.yaml
Helmsman/utils/softhsm-mock-identity-system-values.yaml
.github/workflows/helmsman_esignet.yml
```

### Files Modified (1 file)

```
.github/workflows/README.md  (Added eSignet workflow documentation)
```

---

## Reviewer Notes

1. All hooks follow the existing pattern in the repository
2. Uses existing `copy_cm_func.sh` utility for cross-namespace operations
3. Secrets handling follows GitHub Actions best practices (masked, base64 encoded)
4. DSF follows priority-based deployment order
5. All components have proper wait and timeout configurations
6. Standalone mode allows flexible deployment scenarios
