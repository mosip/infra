# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

MOSIP Rapid Deployment — Terraform for cloud infrastructure + Helmsman for Kubernetes application deployment. Supports eSignet standalone and full MOSIP platform deployments. All operations run through **GitHub Actions workflows**; no manual CLI scripts are needed except for local Helmsman testing.

## Key Difference from Generic Infra Repos

- **GPG-encrypted local Terraform state**: state files are encrypted and committed to Git per-branch — no S3/remote backend dependency. File naming: `{provider}-{component}-{branch}-terraform.tfstate.gpg`
- **Helmsman DSFs organized by deployment profile** (not a single flat folder)
- **~59 hook scripts** for pre/post-install automation; all are idempotent and accept `KUBECONFIG` as optional first argument
- **Versioned hooks**: `Helmsman/hooks/esignet-1.7.1/` contains version-specific overrides (takes precedence over root-level hooks when referenced in a DSF)
- **Ansible** for external PostgreSQL provisioning (in `Helmsman/utils/ansible/`)

---

## Overall Deployment Sequence

```
1. Terraform: base-infra      → VPC, networking, WireGuard jump server
2. Terraform: observ-infra    → Rancher management cluster (optional)
3. Terraform: infra           → RKE2/EKS K8s cluster + PostgreSQL
4. Helmsman: external         → prereq-dsf.yaml + external-dsf.yaml (parallel)
5. Helmsman: MOSIP            → mosip-dsf.yaml (auto-triggered after step 4)
6. Helmsman: eSignet          → esignet-dsf.yaml (manual or after MOSIP)
7. Helmsman: testrigs         → testrigs-dsf.yaml (manual, after all pods running)
```

---

## Terraform

### Structure

```
terraform/
├── base-infra/        # VPC, networking, WireGuard (run FIRST)
├── infra/             # K8s cluster + PostgreSQL (main deployment)
├── observ-infra/      # Rancher + monitoring cluster (optional)
├── modules/           # Reusable modules (aws/ complete; azure/ & gcp/ placeholders)
└── implementations/   # Cloud provider-specific configs
```

**Only AWS is fully implemented.** Azure and GCP directories exist but are placeholders.

### GitHub Actions Workflow: `terraform.yml`

Key inputs:
- `CLOUD_PROVIDER`: always `aws` (Azure/GCP not functional)
- `TERRAFORM_COMPONENT`: `base-infra` → `observ-infra` → `infra` (run in this order)
- `TERRAFORM_APPLY`: unchecked = plan only, checked = apply (creates real resources + billing starts)
- `SSH_PRIVATE_KEY`: GitHub secret name holding the SSH key (must match `ssh_key_name` in tfvars)
- `BACKEND_TYPE`: `local` (GPG-encrypted, default) or `remote` (S3/Azure/GCS — requires `setup-cloud-storage.sh`)

### Terraform Modules (`terraform/modules/aws/`)

All reusable modules are under `modules/aws/` (Azure/GCP are empty stubs):

| Module | Provisions |
|---|---|
| `aws-resource-creation` | EC2, VPC, subnets, security groups, Route53 DNS |
| `rke2-cluster` | RKE2 Kubernetes nodes + Rancher import |
| `nginx-setup` | NGINX load balancer + SSL via certbot |
| `nfs-setup` | Shared NFS storage class |
| `postgresql-setup` | External PostgreSQL 15 via Terraform + Ansible |
| `activemq-setup` | ActiveMQ message broker |
| `rancher-keycloak-setup` | Keycloak SSO for Rancher |

### State Backend

GPG-encrypted local backend — state is encrypted and stored in the repo per branch. Required secret: `GPG_PASSPHRASE`.
Branch isolation: each branch gets its own `aws-infra-<branch>-terraform.tfstate.gpg`.

### Required GitHub Secrets (Terraform)
- `CLUSTER_WIREGUARD_WG0`, `CLUSTER_WIREGUARD_WG1` — WireGuard VPN configs
- `KUBECONFIG` — raw YAML (not base64); generated at `terraform/implementations/aws/infra/kubeconfig_<cluster-name>` after infra apply
- `GPG_PASSPHRASE` — for state encryption
- SSH private key secret (name must match tfvars)

---

## Helmsman

### DSF Directory Structure

Unlike a flat DSF folder, this repo organizes DSFs by **deployment profile**:

```
Helmsman/dsf/
├── esignet/                    # Standalone eSignet v1.7.1 (no full MOSIP)
│   ├── prereq-dsf.yaml
│   ├── external-dsf.yaml
│   └── esignet-dsf.yaml
├── mosip-platform-java11/      # Full MOSIP platform with Java 11
│   ├── prereq-dsf.yaml
│   ├── external-dsf.yaml
│   ├── mosip-dsf.yaml
│   ├── esignet-dsf.yaml
│   └── testrigs-dsf.yaml
└── mosip-platform-java21/      # Full MOSIP platform with Java 21
    ├── prereq-dsf.yaml
    ├── external-dsf.yaml
    ├── mosip-dsf.yaml
    ├── esignet-dsf.yaml
    └── testrigs-dsf.yaml
```

Choose the profile matching your deployment target. The GitHub Actions workflows reference the appropriate subdirectory.

### DSF Files — What Each Deploys

| File | Deploys |
|---|---|
| `prereq-dsf.yaml` | Rancher monitoring, Elasticsearch, Kibana, Istio, httpbin, global configmap |
| `external-dsf.yaml` | PostgreSQL, Redis, Kafka, SoftHSM, Keycloak, ClamAV, MinIO, ActiveMQ, Captcha |
| `mosip-dsf.yaml` | All MOSIP core services (22 namespaces, 50+ microservices) |
| `esignet-dsf.yaml` | eSignet, OIDC UI, Keycloak init, SoftHSM, Mock identity, Partner onboarder, Mock RP |
| `testrigs-dsf.yaml` | API test rig, UI test rig, DSL test rig |

**Always use `apply` mode.** `dry-run` fails because MOSIP services reference ConfigMaps/Secrets from other namespaces that don't exist at dry-run time.

### eSignet DSF — Component Priority Order

Lower number = deployed first:

| Priority | Component | Namespace |
|---|---|---|
| -19 | redis | redis |
| -18 | softhsm-esignet | softhsm |
| -15 | postgres-init-esignet | postgres |
| -14 | keycloak | keycloak |
| -13 | esignet-keycloak-init | esignet |
| -12 | esignet | esignet |
| -11 | softhsm-mock-identity-system, oidc-ui | softhsm / esignet |
| -10 | mock-identity-system, partner-onboarder | esignet |
| -9 | mock-relying-party-ui | esignet |
| -8 | mock-relying-party-service | esignet |

### DSF Runtime Variable Substitution

All domain, environment, and secret values are now resolved at deploy time via Helmsman's built-in env-var expansion (`${VAR}`) — **no manual edits to DSF files are needed per environment**.

| Variable | Resolved from | Used in |
|---|---|---|
| `${domain_name}` | Workflow input or `vars.DOMAIN_NAME` | All DSFs — hostnames, DB hosts, Istio virtual services |
| `${env_name}` | Workflow input or `vars.ENV_NAME` | `mosip-dsf`, `external-dsf`, `testrigs-dsf` — landing page name, test rig user |
| `${slack_channel_name}` | Workflow input or `vars.SLACK_CHANNEL_NAME` | `prereq-dsf` — alerting-setup.sh arg |
| `${SLACK_WEBHOOK_URL}` | Workflow input → overrides `secrets.SLACK_WEBHOOK_URL` | `prereq-dsf`, `testrigs-dsf` |
| `${PREREG/ADMIN/RESIDENT_CAPTCHA_SITE_KEY}` | `secrets.*` | `external-dsf` (MOSIP profiles only) — captcha-setup.sh args |
| `${PREREG/ADMIN/RESIDENT_CAPTCHA_SECRET_KEY}` | `secrets.*` | `external-dsf` (MOSIP profiles only) — captcha-setup.sh args |

**For push-triggered runs** (no workflow_dispatch inputs), values fall back to GitHub Actions [Environment Variables](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/store-information-in-variables) (`vars.DOMAIN_NAME`, `vars.ENV_NAME`, `vars.SLACK_CHANNEL_NAME`). Configure these under Repository → Settings → Environments → `<branch-name>` → Variables.

Still requires manual update per environment:
- `Helmsman/utils/global_configmap.yaml` — domain names + cluster ID shared across all services
- `Helmsman/utils/config-server-values.yaml` — Git repository URLs for inji-config and mosip-config
- `terraform/implementations/aws/infra/profiles/{esignet,mosip}/aws.tfvars` — instance types, region, node counts; `activemq_storage_device` must be `/dev/<name>` (not bare `/dev/`), `activemq_mount_point` must be an absolute path that is not `/`, `activemq_nfs_allowed_hosts` defaults to `"*"` — set to your cluster CIDR (e.g. `"10.0.0.0/8"`) in production

### Hooks (`Helmsman/hooks/`)

73 shell scripts executed by Helmsman as `preInstall`/`postInstall` steps. Two layers:
- **Root-level hooks** — default hooks used by all profiles
- **`esignet-1.7.1/` subdirectory** — version-specific overrides for eSignet 1.7.1 (takes precedence when referenced in eSignet DSF)

**Hook naming convention:**
- `{service}-setup.sh` — main initialization (runs once, creates namespaces/resources)
- `{service}-preinstall.sh` — runs before `helm install`
- `{service}-postinstall.sh` — runs after `helm install` (secret sync, readiness checks)
- `wait-for-{job}.sh` — blocks until a K8s Job completes

**Hook error handling pattern:** All `kubectl wait` calls use a 480s timeout (aligned with Helmsman's default) and fail-fast on timeout — errors go to stderr (`>&2`) followed by `exit 1`. Never use `|| echo "WARNING..."` to swallow wait failures, as `set -euo pipefail` won't catch them through `||`.

Key eSignet hooks:

| Hook | App | Purpose |
|---|---|---|
| `pre-helmsman-cleanup.sh` | (global) | **Deletes immutable Jobs before re-deploy** — run this first on re-deployments |
| `esignet-init-db.sh` | postgres-init-esignet | Initialize DB schema |
| `esignet-preinstall-keycloak-init.sh` | esignet-keycloak-init | Copy Keycloak configs |
| `esignet-postinstall-keycloak-init.sh` | esignet-keycloak-init | Sync client secrets to K8s |
| `softhsm-esignet-setup.sh` / `softhsm-esignet-postinstall.sh` | softhsm-esignet | HSM namespace + secret sharing |
| `esignet-preinstall.sh` | esignet | Namespace, captcha secret, prerequisite setup |
| `mock-relying-party-service-preinstall.sh` | mock-relying-party-service | Create private key K8s secrets |
| `common-labeling-istio-and-sharing-cm-secrets-among-ns.sh` | multiple | Apply Istio labels + share configmaps/secrets across namespaces |

To re-run a failed hook locally:
```bash
export KUBECONFIG=/path/to/kubeconfig
export WORKDIR=/path/to/Helmsman
./hooks/esignet-preinstall.sh
```

### Utils (`Helmsman/utils/`)

| File/Dir | Purpose |
|---|---|
| `global_configmap.yaml` | Domain names shared across all services — update this per environment |
| `postgres-values.yaml` | PostgreSQL Helm chart values |
| `keycloak-init-values.yaml` | Keycloak realm configuration |
| `softhsm-esignet-values.yaml` | SoftHSM for eSignet |
| `softhsm-mock-identity-system-values.yaml` | SoftHSM for mock identity |
| `config-server-values.yaml` | Git repo config for Spring Cloud Config Server |
| `istio-gateway/` | Helm chart for Istio gateways (internal + public) and auth policies |
| `*-istio-addons-*.tgz` | Pre-packaged Istio addon charts (logging, IAM, Kafka, MinIO, Postgres, gateway) |
| `logging/` | Elasticsearch clusterflow/output YAMLs + 5 Kibana dashboards |
| `alerting/` | AlertManager config + 5 custom Prometheus alert rules |
| `ansible/` | Ansible playbooks for external PostgreSQL provisioning |

---

## GitHub Actions Helper Scripts (`.github/scripts/`)

16 utility scripts called by workflows. The following can also be run locally for validation:

| Script | Purpose |
|---|---|
| `test-infrastructure.sh` | Validates hook script functionality end-to-end |
| `test-workflow-e2e.sh` | Simulates full workflow execution without real cloud resources |
| `validate-workflow-integration.sh` | Checks workflow YAML + secret references are consistent |
| `test-state-locking.sh` | Validates GPG state encryption/decryption cycle |

```bash
# Run locally to validate before pushing
.github/scripts/test-infrastructure.sh
.github/scripts/validate-workflow-integration.sh
```

---

## GitHub Actions Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| `terraform.yml` | Manual | Provision cloud infrastructure |
| `terraform-destroy.yml` | Manual | Destroy cloud infrastructure |
| `helmsman_external.yml` | Manual / push to DSF | Deploy prereqs + external services in parallel; auto-triggers mosip workflow (push events: only first detected profile triggers MOSIP dispatch — use `workflow_dispatch` for multiple profiles) |
| `helmsman_mosip.yml` | Auto (from external) / manual | Deploy MOSIP core services |
| `helmsman_esignet.yml` | Manual / push to esignet DSF | Deploy eSignet stack |
| `helmsman_testrigs.yml` | Manual | Deploy test rigs |
| `destroy-resources.yml` | Manual | Comprehensive full-stack cleanup |
| `helmsman_mosip_destroy.yml` | Manual | Destroy MOSIP services |
| `helmsman_external_destroy_external.yml` | Manual | Destroy external services |
| `helmsman_external_destroy_prereq.yml` | Manual | Destroy prerequisites |
| `helmsman_testrigs_destroy.yml` | Manual | Destroy test rigs |
| `keycloak-rancher-integration.yml` | Manual | Configure Keycloak-Rancher integration |

### Required GitHub Secrets

All secrets must be **Environment Secrets** (not Repository Secrets). Environment name = branch name. Configure at: Repository → Settings → Environments → `<branch-name>` → Secrets.

**All workflows:**

| Secret | Format | Used by |
|---|---|---|
| `KUBECONFIG` | Raw YAML (not base64) | All Helmsman workflows |
| `CLUSTER_WIREGUARD_WG0` | Plain text WireGuard config | All Helmsman workflows |
| `SLACK_WEBHOOK_URL` | Plain text URL | `helmsman_external.yml`, `helmsman_testrigs.yml` (fallback when not provided as input) |

**eSignet deployment (`helmsman_esignet.yml`) only:**

| Secret | Format |
|---|---|
| `MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY` | Base64 encoded PEM |
| `MOCK_RELYING_PARTY_JWE_PRIVATE_KEY` | Base64 encoded PEM |
| `ESIGNET_CAPTCHA_SITE_KEY` | Plain text |
| `ESIGNET_CAPTCHA_SECRET_KEY` | Plain text |

**MOSIP external deployment (`helmsman_external.yml`, MOSIP profiles only) — reCAPTCHA for MOSIP services:**

| Secret | Format |
|---|---|
| `PREREG_CAPTCHA_SITE_KEY` | Plain text |
| `PREREG_CAPTCHA_SECRET_KEY` | Plain text |
| `ADMIN_CAPTCHA_SITE_KEY` | Plain text |
| `ADMIN_CAPTCHA_SECRET_KEY` | Plain text |
| `RESIDENT_CAPTCHA_SITE_KEY` | Plain text |
| `RESIDENT_CAPTCHA_SECRET_KEY` | Plain text |

---

## Manual eSignet Deployment (`esignet/deploy/`)

An alternative to the Helmsman DSF workflow — interactive shell scripts for direct Helm installs. Used for local/manual deployments outside of GitHub Actions.

### Deployment Order

```
1. install-prereq.sh    → Istio gateway, PostgreSQL, Kafka, Redis, SoftHSM, Captcha, Keycloak
2. initialise-prereq.sh → DB schema init + Keycloak realm/client setup
3. install-esignet.sh   → eSignet (with or without plugins) + OIDC UI
```

Helper scripts: `restart-all.sh` (restart in dependency order), `delete-all.sh` (uninstall all).

### Namespace and Secret Layout

Each service deploys into its own namespace. ConfigMaps/Secrets are copied across namespaces via `copy_cm_func.sh`:

```bash
./copy_cm_func.sh <configmap|secret> <name> <source-ns> <dest-ns> [new-name]
```

**Created by prereq scripts and consumed by eSignet:**

| Resource | Type | Source NS | Purpose |
|---|---|---|---|
| `postgres-config` | ConfigMap | postgres | DB host/port/name/user |
| `redis-config` | ConfigMap | redis | Redis host/port |
| `esignet-softhsm-share` | ConfigMap | softhsm | HSM config |
| `db-common-secrets` | Secret | postgres | DB password |
| `redis` | Secret | redis | Redis password |
| `esignet-softhsm` | Secret | softhsm | HSM PIN |
| `esignet-captcha` | Secret | captcha | reCAPTCHA site+secret keys |
| `keycloak-client-secrets` | Secret | keycloak | IDA client secret |

### Domain Values — GitOps Approach

Domain/host values are no longer stored in an `esignet-global` ConfigMap (already removed). A committed `domain-values.yaml` file per branch/environment supplies all 8 domain vars — no runtime prompts, no `--set` index hacks.

#### Why `domainConfig` map (not `extraEnvVars`)

`extraEnvVars` is a YAML list — Helm **replaces** lists on `-f` merge, wiping all `configMapKeyRef`/`secretKeyRef` entries. `domainConfig` is a map — Helm **merges** maps, so each deployment only provides what it needs without touching other values.

#### How Spring property placeholders get resolved

Config files in `esignet-config` repo use Spring placeholders like `${mosip.api.internal.host}`. These are resolved by the **service pod at startup** via Spring relaxed binding:

```
env var in pod:   MOSIP_API_INTERNAL_HOST=api-internal.sandbox.xyz.net
         ↓  Spring relaxed binding (uppercase+underscore → lowercase+dot)
Spring property:  mosip.api.internal.host=api-internal.sandbox.xyz.net
         ↓
Config file:      ${mosip.api.internal.host}  → resolved
```

Config-server just passes property files through unchanged — it does **not** resolve placeholders. The `domainConfig` env vars land in the service pod, which resolves them.

#### `domain-values.yaml` per branch (manual deploy path)

Committed to Git at `esignet/deploy/domain-values.yaml` — update values for your environment:
```yaml
domainConfig:
  MOSIP_API_HOST: api.sandbox.xyz.net
  MOSIP_IAM_EXTERNAL_HOST: iam.sandbox.xyz.net
  MOSIP_API_INTERNAL_HOST: api-internal.sandbox.xyz.net
  MOSIP_KAFKA_HOST: kafka.sandbox.xyz.net
  MOSIP_ESIGNET_HOST: esignet.sandbox.xyz.net
  MOSIP_POSTGRES_HOST: esignet-postgres.sandbox.xyz.net
  MOSIP_SIGNUP_HOST: signup.sandbox.xyz.net
  MOSIP_SMTP_HOST: smtp.sandbox.xyz.net
```

`esignet-signup/deploy/domain-values.yaml` — signup-service only needs 2 keys:
```yaml
domainConfig:
  MOSIP_ESIGNET_HOST: esignet.sandbox.xyz.net
  MOSIP_SIGNUP_HOST: signup.sandbox.xyz.net
```

Adding a new host in future: add one line to this file. No helm chart release required.

#### Helmsman DSF path (CI/CD)

`set:` with `${domain_name}` substitution — maps merge cleanly, no index management:
```yaml
apps:
  esignet:
    set:
      domainConfig.MOSIP_ESIGNET_HOST: "esignet.${domain_name}"
      domainConfig.MOSIP_SIGNUP_HOST: "signup.${domain_name}"
      domainConfig.MOSIP_API_HOST: "api.${domain_name}"
      domainConfig.MOSIP_IAM_EXTERNAL_HOST: "iam.${domain_name}"
      domainConfig.MOSIP_API_INTERNAL_HOST: "api-internal.${domain_name}"
      domainConfig.MOSIP_KAFKA_HOST: "kafka.${domain_name}"
      domainConfig.MOSIP_POSTGRES_HOST: "postgres.${domain_name}"
      domainConfig.MOSIP_SMTP_HOST: "smtp.${domain_name}"
```

#### Compatible with ArgoCD / PipeCD / FluxCD

All GitOps tools support `valuesFiles` + `parameters` natively — `domainConfig` as a map works cleanly with all of them because it uses standard Helm scalar merge semantics.

#### Chart ownership rule

| Chart | Approach | Notes |
|---|---|---|
| `esignet` | `domainConfig: {}` + `{{- range }}` loop in `deployment.yaml` | All 8 domain vars; PKCS12 keystore type still uses `extraEnvVarsAdditional[0]` (non-domain var) |
| `signup-service` | `domainConfig: {}` + `{{- range }}` loop | 2 domain vars (`ESIGNET_HOST`, `SIGNUP_HOST`) |
| `mock-identity-system` | `domainConfig: {}` + `{{- range }}` loop | 1 domain var (`ESIGNET_HOST`) |
| `oidc-ui` | No `domainConfig` — uses `--set istio.hosts[0]` and `--set oidc_ui.configmaps.*` | These are Istio/ConfigMap resources, not Spring env vars |
| `mock-relying-party-service` | No `domainConfig` — uses `--set mock_relying_party_service.*` | Constructed URL values via chart-specific paths |
| `mock-relying-party-ui` | No `domainConfig` — uses `--set mock_relying_party_ui.*` | Frontend configmap entries, not Spring env vars |
| `config-server` (published external chart) | Write the **complete** `envVariables` list into a runtime YAML override file (via `mktemp`) and pass as `-f "$override_file"` | Cannot modify chart source — `domainConfig` not available. List replacement means the override file must contain every entry, including domain values. See `deploy/config-server/install.sh` |
| `keycloak` (published external chart) | Domain values filled directly in the committed `deploy/keycloak/values.yaml` per branch | Cannot modify chart source |

#### Helm template iteration block (in each owned chart's `deployment.yaml`)

```yaml
{{- range $key, $val := .Values.domainConfig }}
- name: {{ $key }}
  value: {{ $val | quote }}
{{- end }}
```

Placed after the `extraEnvVarsAdditional` block (esignet) or `extraEnvVars` block (signup-service, mock-identity-system).

#### `install-prereq.sh` exported env vars

Prompts for all 8 values at startup and exports them so child scripts inherit:

| Env var | Example value | Used by |
|---|---|---|
| `MOSIP_API_HOST` | `api.sandbox.xyz.net` | `istio-gateway/install.sh` |
| `MOSIP_API_INTERNAL_HOST` | `api-internal.sandbox.xyz.net` | `istio-gateway/install.sh`, init container SSL cert |
| `MOSIP_IAM_EXTERNAL_HOST` | `iam.sandbox.xyz.net` | `keycloak/install.sh`, `keycloak-init.sh` |
| `MOSIP_KAFKA_HOST` | `kafka.sandbox.xyz.net` | `kafka/install.sh` |
| `MOSIP_ESIGNET_HOST` | `esignet.sandbox.xyz.net` | `captcha/install.sh`, `oidc-ui/install.sh` |
| `MOSIP_POSTGRES_HOST` | `esignet-postgres.sandbox.xyz.net` | `postgres/install.sh` |
| `MOSIP_SIGNUP_HOST` | `signup.sandbox.xyz.net` | signup helm |
| `MOSIP_SMTP_HOST` | `smtp.sandbox.xyz.net` | SMTP-dependent services |

### HSM Options (prompted during prereq install)

| Option | When to use |
|---|---|
| `s` SoftHSM | Default; self-contained |
| `e` External HSM | Requires URL, host URL, password |
| `p` PKCS12 | File-based; requires PVC mount in eSignet |
| `n` Skip | Use existing HSM deployment |

### eSignet Plugin Options (`esignet-with-plugins/install.sh`)

| # | Plugin | Key requirement |
|---|---|---|
| 1 | `esignet-mock-plugin` | None — testing only |
| 2 | `mosip-identity-plugin` | MISP license key + 9 IDA service URLs; creates `esignet-misp-onboarder-key` secret |
| 3 | `sunbird-rc-plugin` | Registry URL; disables key binder (`NoOpKeyBinder`) |
| 4 | Custom | Plugin JAR URL + filename |

Plugin number is written to `/tmp/plugin_no.txt` — read by parent scripts to conditionally run MISP onboarding.

### OIDC UI Configuration (prompted during install)

- **Theme**: `blue`, `orange`, or custom URL
- **Default language**: `en`, `fr`, `ara`
- **ID Provider name**: displayed on login page
- Connects to eSignet via `REACT_APP_API_BASE_URL` (must match eSignet service host)

### Helm Charts (`esignet/helm/`)

Two charts: `esignet/` and `oidc-ui/`, both using Bitnami common library.

**eSignet chart key defaults:**
- Image: `mosipdev/esignet-with-plugins:develop`
- Resources: 500m CPU / 2250Mi memory limit; `-Xms1500M -Xmx1500M`
- Health endpoint: `/v1/esignet/actuator/health` (startup delay 180s)
- Metrics: `/v1/esignet/actuator/prometheus` (Prometheus, 10s interval)
- Persistence: disabled by default; enable for PKCS12 (`mountDir: /home/mosip/config/`)
- Init container: runs only when `enable_insecure=true` — generates self-signed SSL certs

**OIDC UI chart key defaults:**
- Image: `mosipdev/oidc-ui:develop`
- Resources: 300m CPU / 1500Mi memory limit
- Health endpoint: `/` on port 3000
- Runs as root (uid 0) — required by the image
- Istio: uses dedicated `oidc-ui-gateway` (not shared `istio-system/public`)

### Known Gotchas

- `kubectl create ns esignet` runs **before** the user confirmation prompt in `esignet-with-plugins/install.sh` — namespace is left behind if user cancels
- `config-server` is a **published external chart** — `domainConfig` cannot be added to it. Domain values are injected by building a complete `envVariables` list in a runtime `mktemp` YAML file and passing it as `-f "$override_file"`. Since `envVariables` is a list and Helm replaces lists on `-f` merge, the override file must include every entry (not just the domain ones). Do not use `--set envVariables[N].value=...` — index-based list `--set` is fragile and replaces the whole list anyway
- `extraEnvVars` in Helm values is a **list** — Helm replaces lists on `-f` merge, wiping all `configMapKeyRef`/`secretKeyRef` entries. Never try to partially override `extraEnvVars` via a second values file. Domain vars use the `domainConfig` map instead (merges cleanly); PKCS12 keystore type and other conditional vars use `extraEnvVarsAdditional` (base is `[]`, replacing empty list loses nothing)
- Domain values for `esignet`, `signup-service`, `mock-identity-system` come from committed `domain-values.yaml` via `-f domain-values.yaml`. Do **not** add domain prompts or `--set domainConfig.*` to install scripts — edit the committed file instead
- `oidc-ui`, `mock-relying-party-service`, `mock-relying-party-ui` do **not** use `domainConfig` — they configure Istio hosts and app-specific configmap values via chart-specific `--set` paths; these are not Spring env vars
- PVCs/PVs are **not deleted** on `helm delete` — must be manually cleaned up
- `set -e` / strict flags are placed after function definitions — functionally correct but non-obvious
- Temp env-var files (`mktemp`) from plugin config in `esignet-with-plugins/install.sh` are not cleaned up after install
- Chart versions are hardcoded to `0.0.1-develop` — update before production use
- Istio injection is **disabled** in the `captcha` and `keycloak` namespaces

---

## Local Helmsman Testing

```bash
export KUBECONFIG=~/.kube/config
export WORKDIR=$(pwd)/Helmsman

# Preview (note: will fail for MOSIP due to cross-namespace dependencies)
helmsman --dry-run -f Helmsman/dsf/esignet/esignet-dsf.yaml

# Apply
helmsman --apply -f Helmsman/dsf/esignet/esignet-dsf.yaml

# Destroy
helmsman --destroy -f Helmsman/dsf/esignet/esignet-dsf.yaml
```

---

## Documentation (`docs/`)

Guides covering the full deployment lifecycle — consult these before opening issues:

| Guide | When to read |
|---|---|
| `ONBOARDING_GUIDE.md` | First time setting up |
| `SECRET_GENERATION_GUIDE.md` | Generating SSH keys, GPG passwords, WireGuard configs |
| `WORKFLOW_GUIDE.md` | Visual walkthrough of GitHub Actions |
| `DSF_CONFIGURATION_GUIDE.md` | Configuring Helmsman DSF files and domain values |
| `TERRAFORM_WORKFLOW_GUIDE.md` | Terraform-specific procedures |
| `ENVIRONMENT_DESTRUCTION_GUIDE.md` | Safe teardown and cost management |
| `HELMSMAN_DESTROY_GUIDE.md` | Destroying Helmsman-deployed services safely |
| `RECAPTCHA_SETUP_GUIDE.md` | reCAPTCHA configuration |
| `GLOSSARY.md` | Terminology reference for MOSIP/eSignet concepts |

---

## Verification After Deployment

```bash
# Check all pods healthy
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed

# eSignet-specific
kubectl get pods -n esignet
kubectl get virtualservice -n esignet
helm list -n esignet

# View logs
kubectl logs -n esignet -l app=esignet -f
kubectl logs -n keycloak -l app.kubernetes.io/name=keycloak -f

# Check namespace label set by eSignet DSF completion
kubectl get ns default --show-labels | grep esignet-dsf
```
