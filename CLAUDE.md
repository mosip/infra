# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

MOSIP Rapid Deployment — Terraform for cloud infrastructure + Helmsman for Kubernetes application deployment. Supports eSignet standalone and full MOSIP platform deployments. All operations run through **GitHub Actions workflows**; no manual CLI scripts are needed except for local Helmsman testing.

## Key Difference from Generic Infra Repos

- **GPG-encrypted local Terraform state**: state files are encrypted and committed to Git per-branch — no S3/remote backend dependency. File naming: `{provider}-{component}-{branch}-terraform.tfstate.gpg`
- **Helmsman DSFs organized by deployment profile** (not a single flat folder)
- **~73 hook scripts** for pre/post-install automation; all are idempotent and accept `KUBECONFIG` as optional first argument
- **Versioned hooks**: `Helmsman/hooks/esignet-standalone/` contains version-specific overrides (takes precedence over root-level hooks when referenced in a DSF)
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
7. Helmsman: Signup           → signup-dsf.yaml (auto-triggered by esignet workflow when profile=esignet, or manual)
8. Helmsman: testrigs         → testrigs-dsf.yaml (manual, after all pods running)
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
│   ├── esignet-dsf.yaml
│   ├── signup-dsf.yaml         # Signup stack (deployed after esignet-dsf)
│   └── testrigs-dsf.yaml       # API/UI testrigs for all 4 esignet namespaces
├── mosip-platform-1.2.0.x/      # Full MOSIP platform with Java 11
│   ├── prereq-dsf.yaml
│   ├── external-dsf.yaml
│   ├── mosip-dsf.yaml
│   ├── esignet-dsf.yaml
│   └── testrigs-dsf.yaml
└── mosip-platform-1.2.1.x/      # Full MOSIP platform with Java 21
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
| `signup-dsf.yaml` | Signup Keycloak init, Kernel services (authmanager/auditmanager/otpmanager/notifier), mock-smtp, signup-service, signup-ui |
| `testrigs-dsf.yaml` | API test rig, UI test rig, DSL test rig. For `esignet` profile: deploys `esignet-apitestrig` into esignet/esignet-cre/esignet-qa11/esignet-sunbird namespaces + optional signup apitestrig and signup uitestrig (disabled by default) |

**Always use `apply` mode.** `dry-run` fails because MOSIP services reference ConfigMaps/Secrets from other namespaces that don't exist at dry-run time.

### Workflow Auto-Trigger Chain

`helmsman_esignet.yml` has a `workflow-caller` job that fires `helmsman_signup.yml` automatically — **only when `profile=esignet`** (standalone eSignet; not for MOSIP platform profiles). For push-triggered runs the esignet workflow always uses the esignet profile and will call signup after completion.

```
helmsman_esignet.yml  →  (profile=esignet, deploy success)  →  helmsman_signup.yml
```

The signup workflow will fail fast if the `esignet-dsf=completed` namespace label is missing — this guards against running signup before eSignet is ready. The `workflow-caller` job requires `GH_INFRA_PAT` secret (a PAT with `actions:write` scope) to dispatch the workflow via the GitHub API.

### eSignet DSF — Component Priority Order

Lower number = deployed first:

| Priority | Component | Namespace |
|---|---|---|
| -18 | postgres | postgres |
| -17 | istio-addons-psql | postgres |
| -16 | postgres-init-esignet (`0.0.1-develop`), redis | esignet / redis | Dynamic DB creation — one DB per esignet namespace (esignet, esignet-cre, esignet-qa11, esignet-sunbird) |
| -15 | kafka, postgres-init-mock-identity, postgres-init-signup | kafka / esignet / signup |
| -14 | kafka-ui | kafka |
| -12 | softhsm-esignet | softhsm |
| -12 | keycloak | keycloak |
| -11 | esignet-keycloak-init | keycloak | Runs in **keycloak ns** — chart creates `keycloak-host` CM + `keycloak-client-secrets` secret there (all keycloak resources already present). postInstall fans both out to esignet, esignet-cre, esignet-qa11, esignet-sunbird. `wait: true` so postInstall only fires after job completes. |
| -10 | captcha | captcha |
| -9 | minio | minio |

**`esignet-dsf.yaml` priority order** (runs after `external-dsf.yaml`):

The DSF supports **4 parallel eSignet instances** — one per namespace — each with its own SoftHSM, plugin config, and service URLs. All instances share the same Keycloak, postgres, redis, and captcha infrastructure from `external-dsf.yaml`.

| Priority | Component | Namespace | Notes |
|---|---|---|---|
| -16 | esignet-softhsm | esignet | Plugin 1 (mock) |
| -16 | esignet-softhsm-cre | esignet-cre | Plugin 2 (mosip-identity) |
| -16 | esignet-softhsm-qa11 | esignet-qa11 | Plugin 2 (mosip-identity) |
| -16 | esignet-softhsm-sunbird | esignet-sunbird | Plugin 3 (sunbird-rc) |
| -15 | esignet-config-server | esignet | Spring Cloud Config Server; pre+postInstall hooks copy secrets and propagate share CM |
| -14 | esignet | esignet | Plugin 1 (mock) |
| -14 | esignet-cre | esignet-cre | Plugin 2 (mosip-identity); DSF overrides `extraEnvVarsCM[1]: esignet-global`, `extraEnvVarsCM[2]: esignet-config-server-share` (replaces chart defaults `[global, config-server-share]`) |
| -14 | esignet-qa11 | esignet-qa11 | Plugin 2 (mosip-identity); same `extraEnvVarsCM` overrides as esignet-cre |
| -14 | esignet-sunbird | esignet-sunbird | Plugin 3 (sunbird-rc) |
| -13 | oidc-ui | esignet | Istio host: `esignet.${domain_name}` |
| -13 | oidc-ui-cre | esignet-cre | Istio host: `esignet-cre.${domain_name}` |
| -13 | oidc-ui-qa11 | esignet-qa11 | Istio host: `esignet-qa11.${domain_name}` |
| -13 | oidc-ui-sunbird | esignet-sunbird | Istio host: `esignet-sunbird.${domain_name}` |
| -12 | softhsm-mock-identity-system (optional) | softhsm | Must precede mock-identity-system — postInstall creates the secret that mock-identity-system-preinstall.sh copies |
| -11 | mock-identity-system (optional) | esignet | |
| -10 | mock-relying-party-service | esignet | Istio via `healthservices.${domain_name}` |
| -10 | mock-relying-party-service-cre | esignet-cre | Istio via `healthservices-mosipid-cre.${domain_name}` |
| -10 | mock-relying-party-service-qa11 | esignet-qa11 | Istio via `healthservices-mosipid-qa11.${domain_name}` |
| -10 | mock-relying-party-service-sunbird | esignet-sunbird | Istio via `healthservices-sunbird.${domain_name}` |
| -9 | mock-relying-party-ui | esignet | |
| -9 | mock-relying-party-ui-cre | esignet-cre | |
| -9 | mock-relying-party-ui-qa11 | esignet-qa11 | |
| -9 | mock-relying-party-ui-sunbird | esignet-sunbird | |
| -9 | pms-partner-cre | esignet-cre | PMS partner; preInstall creates `pms-partner-cre-gateway` (chart has no gateway template); DSF overrides `extraEnvVarsCM[0]: esignet-global`, `extraEnvVarsCM[1]: esignet-config-server-share` |
| -9 | pms-policy-cre | esignet-cre | PMS policy; VS references `pms-partner-cre-gateway` (shared with pms-partner); same `extraEnvVarsCM` overrides as pms-partner-cre |
| -9 | pms-partner-qa11 | esignet-qa11 | PMS partner; preInstall creates `pms-partner-qa11-gateway`; DSF overrides `extraEnvVarsCM[0]: esignet-global`, `extraEnvVarsCM[1]: esignet-config-server-share` |
| -9 | pms-policy-qa11 | esignet-qa11 | PMS policy; VS references `pms-partner-qa11-gateway` (shared with pms-partner); same `extraEnvVarsCM` overrides as pms-partner-qa11 |
| -6 | esignet-misp-onboarder (optional) | esignet | Enable for plugin 2 (mosip-identity) only — runs FIRST |
| -5 | esignet-mock-rp-onboarder (optional) | esignet | Enable for plugin 1 (mock) or plugin 3 (sunbird) |

### Signup DSF — Component Priority Order

All apps in `signup-dsf.yaml` are **disabled by default** — enable the ones you need. Prerequisites from `external-dsf.yaml` must already be running: postgres-init-signup, Redis, Kafka, Keycloak (with `keycloak-postinstall` having propagated `keycloak-client-secrets`), and Captcha.

| Priority | Component | Namespace | Notes |
|---|---|---|---|
| -10 | signup-keycloak-init | signup | Creates mosip-signup-client; propagates secret to signup ns |
| -8 | authmanager, auditmanager, otpmanager | kernel | All share `kernel-preinstall.sh` (creates namespace + domain-config configmap) |
| -7 | notifier | kernel | `notifier-postinstall.sh` waits for notifier readiness |
| -5 | mock-smtp | mock-smtp | Optional — dev/test email/SMS only |
| -4 | signup | signup | `signup-service-preinstall.sh` copies secrets, creates keycloak-host + captcha + keystore + msg-gateway resources |
| -3 | signup-ui | signup | Signup UI; Istio virtualservice on `signup.${domain_name}` |

### DSF Runtime Variable Substitution

All domain, environment, and secret values are now resolved at deploy time via Helmsman's built-in env-var expansion (`${VAR}`) — **no manual edits to DSF files are needed per environment**.

| Variable | Resolved from | Used in |
|---|---|---|
| `${domain_name}` | Workflow input or `vars.DOMAIN_NAME` | All DSFs — hostnames, DB hosts, Istio virtual services |
| `${env_name}` | Workflow input or `vars.ENV_NAME` | `mosip-dsf`, `external-dsf`, `testrigs-dsf` — landing page name, test rig user |
| `${slack_channel_name}` | Workflow input or `vars.SLACK_CHANNEL_NAME` | `prereq-dsf` — alerting-setup.sh arg |
| `${SLACK_WEBHOOK_URL}` | Workflow input → overrides `secrets.SLACK_WEBHOOK_URL` | `prereq-dsf`, `testrigs-dsf` |
| `${db_port}` | Workflow input or `vars.DB_PORT` | MOSIP platform `external-dsf`, `mosip-dsf`, `testrigs-dsf` — external postgres port (typically `5433`) |
| `${esignet_db_port}` | Workflow input or `vars.ESIGNET_DB_PORT` | eSignet profile `external-dsf`, `esignet-dsf`, `testrigs-dsf` — container postgres port (typically `5432`); also used in MOSIP platform `esignet-dsf.yaml` for the esignet/mock-identity DB entries |
| `${PREREG/ADMIN/RESIDENT_CAPTCHA_SITE_KEY}` | `secrets.*` | `external-dsf` (MOSIP profiles only) — captcha-setup.sh args |
| `${PREREG/ADMIN/RESIDENT_CAPTCHA_SECRET_KEY}` | `secrets.*` | `external-dsf` (MOSIP profiles only) — captcha-setup.sh args |

**For push-triggered runs** (no workflow_dispatch inputs), values fall back to GitHub Actions [Environment Variables](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/store-information-in-variables) (`vars.DOMAIN_NAME`, `vars.ENV_NAME`, `vars.SLACK_CHANNEL_NAME`, `vars.DB_PORT`, `vars.ESIGNET_DB_PORT`). Configure these under Repository → Settings → Environments → `<branch-name>` → Variables.

Still requires manual update per environment:
- `Helmsman/utils/global_configmap.yaml` — domain names + cluster ID shared across all services
- `Helmsman/utils/config-server-values.yaml` — Git repository URLs for inji-config and mosip-config
- `terraform/implementations/aws/infra/profiles/{esignet,mosip}/aws.tfvars` — instance types, region, node counts; `activemq_storage_device` must be `/dev/<name>` (not bare `/dev/`), `activemq_mount_point` must be an absolute path that is not `/`, `activemq_nfs_allowed_hosts` defaults to `"*"` — set to your cluster CIDR (e.g. `"10.0.0.0/8"`) in production

### Hooks (`Helmsman/hooks/`)

73 shell scripts executed by Helmsman as `preInstall`/`postInstall` steps. Two layers:
- **Root-level hooks** — default hooks used by all profiles
- **`esignet-standalone/` subdirectory** — version-specific overrides for eSignet 1.7.1 (takes precedence when referenced in eSignet DSF)

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
| `esignet-init-db.sh` | postgres-init-esignet | Pre-creates all 4 esignet namespaces (`esignet`, `esignet-cre`, `esignet-qa11`, `esignet-sunbird`) with Istio label at priority -16 so postInstall can copy `db-common-secrets` into each (namespace-specific preinstalls only run at -14) |
| `esignet-db-postinstall.sh` | postgres-init-esignet | Copies `db-common-secrets` from `postgres` ns to all 4 esignet namespaces after init jobs complete |
| `config-server-esignet-setup.sh` | esignet-config-server | Creates esignet ns + Istio label; copies db secrets (`db-common-secrets` from postgres ns, `redis`/`redis-config` from redis ns); creates `esignet-global` CM in esignet ns with 10 keys from `${domain_name}`: `installation-domain`, `mosip-api-host`, `mosip-api-internal-host`, `mosip-esignet-host` (`esignet.${domain_name}`), `mosip-iam-external-host`, `mosip-kafka-host`, `mosip-postgres-host`, `mosip-signup-host`, `mosip-smtp-host`, `mosip-version`; pre-creates empty `esignet-misp-onboarder-key` placeholder. **Does NOT copy softhsm secret** — the softhsm Helm chart installs directly into the esignet namespace, so no cross-namespace copy is needed. **Does NOT copy keycloak resources** — those are pre-populated by `esignet-postinstall-keycloak-init.sh` in external-dsf |
| `config-server-esignet-postinstall.sh` | esignet-config-server | Copies `esignet-config-server-share` CM from `esignet` ns to `esignet-cre`, `esignet-qa11`, `esignet-sunbird` so those instances can locate the config-server |
| `esignet-preinstall-keycloak-init.sh` | esignet-keycloak-init | Deletes old `esignet-keycloak-init` release from keycloak ns (helm manages `keycloak-host` and `keycloak-client-secrets` — no manual kubectl delete needed); also cleans up old esignet-ns release (migration); fetches all 5 client secrets from keycloak ns for Helmsman `${VAR}` substitution (empty on fresh install — chart generates them) |
| `esignet-postinstall-keycloak-init.sh` | esignet-keycloak-init | Fans out `keycloak-host` CM, `keycloak-env-vars` CM, `keycloak` secret, and `keycloak-client-secrets` secret from keycloak ns to all 4 esignet namespaces (esignet, esignet-cre, esignet-qa11, esignet-sunbird); skips any namespace that does not exist |
| `softhsm-esignet-setup.sh` / `softhsm-esignet-postinstall.sh` | softhsm-esignet | HSM namespace + secret sharing (esignet ns) |
| `softhsm-esignet-{cre,qa11,sunbird}-setup.sh` | softhsm-esignet-{cre,qa11,sunbird} | Thin wrappers — set `ESIGNET_NS` and exec `softhsm-esignet-setup.sh` |
| `esignet-preinstall.sh` | esignet | Copies postgres/redis configmaps+secrets to esignet ns |
| `esignet-{cre,qa11,sunbird}-preinstall.sh` | esignet-{cre,qa11,sunbird} | Set `ESIGNET_NS`, call base `esignet-preinstall.sh`, then: (1) **create namespace-specific `esignet-global`** CM directly in target ns — all keys use `${domain_name}` except `mosip-esignet-host` and `mosip-signup-host` which use namespace-specific subdomains (`esignet-mosipid-cre`, `signup-mosipid-cre` / `esignet-mosipid-qa11`, `signup-mosipid-qa11` / `esignet-sunbird`, `signup-sunbird`); (2) patch `postgres-config` with env-specific `database-name` and `database-username` (e.g. `mosip_esignet_cre`/`esignetuser_cre`); (3) create `esignet-misp-onboarder-key` placeholder secret if absent; (4) create `esignet-captcha-{cre,qa11,sunbird}` secret in captcha ns from `ESIGNET_{CRE,QA11,SUNBIRD}_CAPTCHA_SITE/SECRET_KEY` env vars (injected by esignet workflow), copy to target ns, and patch captcha deployment with `MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNET{CRE,QA11,SUNBIRD}`; **(cre and qa11 only)** (5) create `postgres-postgresql-{cre,qa11}` secret from `CRE/QA11_POSTGRES_PASSWORD`; (6) create `keycloak-host-{cre,qa11}` CM with 5 keys — `keycloak-external-host/url` → `iam.${cre/qa11_domain_name}`, `keycloak-internal-host/url/service-url` → `keycloak.keycloak`; (7) fetch all confidential clients from remote CRE/QA11 Keycloak REST API using `CRE/QA11_KEYCLOAK_ADMIN_PASSWORD` → create `keycloak-client-secrets-{cre,qa11}` (key per client: `{clientId_with_underscores}_secret`) |
| `oidc-ui-preinstall.sh` | oidc-ui | Waits for esignet pods ready in esignet ns |
| `oidc-ui-{cre,qa11,sunbird}-preinstall.sh` | oidc-ui-{cre,qa11,sunbird} | Thin wrappers — set `ESIGNET_NS` and exec `oidc-ui-preinstall.sh` |
| `mock-identity-system-preinstall.sh` | mock-identity-system | Copies `softhsm-mock-identity-system` secret from softhsm ns (chart references it via `secretKeyRef` — must be in same namespace as pod); creates `mockid-postgres-config` with `database-host` read from `postgres-config` in esignet ns and hardcoded defaults for `database-name`/`database-username`/`database-port` (`mosip_mockidentitysystem`/`mockidsystemuser`/`5432`) — overridable via `MOCKID_DB_NAME`/`MOCKID_DB_USER`/`MOCKID_DB_PORT` env vars (no dependency on `db-mockidentitysystem-init-env-config` CM); verifies `softhsm-mock-identity-system-share` CM is present |
| `mock-relying-party-service-preinstall.sh` | mock-relying-party-service | Creates K8s secrets `mock-relying-party-private-key-jwk` (key: `client-private-key`) and `jwe-userinfo-service-secrets` (key: `jwe-userinfo-private-key`) from `$MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY` and `$MOCK_RELYING_PARTY_JWE_PRIVATE_KEY` env vars injected by the workflow |
| `mock-relying-party-service-{cre,qa11,sunbird}-preinstall.sh` | mock-relying-party-service-{cre,qa11,sunbird} | Thin wrappers — set `ESIGNET_NS` and exec base `mock-relying-party-service-preinstall.sh` (creates private key secrets in the target namespace) |
| `mock-relying-party-ui-preinstall.sh` | mock-relying-party-ui | Namespace creation + service check (esignet ns) |
| `mock-relying-party-ui-{cre,qa11,sunbird}-preinstall.sh` | mock-relying-party-ui-{cre,qa11,sunbird} | Namespace creation + service check in correct namespace (esignet-cre/qa11/sunbird) |
| `esignet-misp-onboarder-preinstall.sh` | esignet-misp-onboarder | Disables Istio injection; deletes stale `esignet-onboarder-config` CM + `esignet-onboarder-secrets` secret; copies `keycloak-env-vars`/`keycloak`/`keycloak-client-secrets` from keycloak ns; builds `s3` secret with `s3-user-secret` key from MinIO root-password; deletes `onboarder-namespace` CM; waits for esignet ready |
| `esignet-misp-onboarder-postinstall.sh` | esignet-misp-onboarder | Checks job completion; re-enables Istio injection; restarts `esignet-config-server` first (reloads MISP key from secret), then restarts `esignet` to fetch updated config |
| `esignet-mock-rp-onboarder-preinstall.sh` | esignet-mock-rp-onboarder | Disables Istio injection; copies `keycloak-env-vars` configmap + `keycloak`/`keycloak-client-secrets` secrets from keycloak ns; builds `s3` secret with `s3-user-secret` key from MinIO root-password; deletes `onboarder-namespace` CM before install; waits for esignet ready |
| `esignet-mock-rp-onboarder-postinstall.sh` | esignet-mock-rp-onboarder | Checks job completion; re-enables Istio injection; restarts `mock-relying-party-service` |
| `pms-partner-cre-preinstall.sh` | pms-partner-cre | Creates `pms-partner-cre-gateway` in `esignet-cre` (HTTPS+HTTP, TLS credential `pms-partner-cre-tls`); chart has no gateway template |
| `pms-partner-qa11-preinstall.sh` | pms-partner-qa11 | Creates `pms-partner-qa11-gateway` in `esignet-qa11` (HTTPS+HTTP, TLS credential `pms-partner-qa11-tls`); chart has no gateway template |
| `common-labeling-istio-and-sharing-cm-secrets-among-ns.sh` | multiple | Apply Istio labels + share configmaps/secrets across namespaces |

Key Signup hooks (`Helmsman/hooks/esignet-standalone/`):

| Hook | App | Purpose |
|---|---|---|
| `signup-keycloak-init-preinstall.sh` | signup-keycloak-init | Creates signup namespace; copies `keycloak-client-secrets` from keycloak ns |
| `signup-keycloak-init-postinstall.sh` | signup-keycloak-init | Propagates `mosip_signup_client_secret` to signup namespace |
| `signup-init-db.sh` | postgres-init-signup | Initializes mosip_audit, mosip_kernel, mosip_otp DB schemas for signup |
| `kernel-preinstall.sh` | authmanager / auditmanager / otpmanager | Creates kernel namespace; creates `domain-config` configmap with `MOSIP_API_HOST`, `MOSIP_API_INTERNAL_HOST`, `MOSIP_IAM_EXTERNAL_HOST` |
| `notifier-postinstall.sh` | notifier | Waits for notifier rollout readiness |
| `signup-service-preinstall.sh` | signup | Copies redis/keycloak secrets; creates `keycloak-host` configmap, `signup-captcha` secret (in signup ns + copies to captcha ns + patches captcha deployment with `MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_SIGNUP`), `signup-keystore` secret, `msg-gateway` configmap+secret pointing to mock-smtp |
| `mock-identity-init-db.sh` | postgres-init-mock-identity | Initializes mock identity DB schema |

Key Testrig hooks (`Helmsman/hooks/esignet-standalone/`):

| Hook | App | Purpose |
|---|---|---|
| `apitestrig-esignet-setup.sh` | esignet-apitestrig | Deletes stale testrig CMs (`s3`, `db`, `apitestrig`) in esignet ns; copies `postgres-postgresql` secret from postgres ns. keycloak resources already present from `esignet-postinstall-keycloak-init.sh` |
| `apitestrig-esignet-cre-setup.sh` | esignet-cre-apitestrig | Same as above for esignet-cre ns |
| `apitestrig-esignet-qa11-setup.sh` | esignet-qa11-apitestrig | Same as above for esignet-qa11 ns |
| `apitestrig-esignet-sunbird-setup.sh` | esignet-sunbird-apitestrig | Same as above for esignet-sunbird ns |
| `apitestrig-signup-setup.sh` | esignet-signup-apitestrig | Deletes stale testrig CMs in signup ns; copies `postgres-postgresql` from postgres ns. keycloak resources already present from signup-keycloak-init |
| `uitestrig-signup-setup.sh` | signup-uitestrig | Creates signup-uitestrig namespace with Istio disabled; copies `keycloak-host` from keycloak ns, `keycloak-client-secrets` from keycloak ns, `s3` from minio ns, `postgres-postgresql` from postgres ns |
| `trigger-test-jobs-esignet.sh` | esignet-sunbird-apitestrig (postInstall) | Triggers all cronjobs in esignet, esignet-cre, esignet-qa11, esignet-sunbird namespaces sequentially; optionally triggers signup and signup-uitestrig if deployed. Uses `trigger_all_in_ns` so cronjob names are auto-detected |

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
| `keycloak-init-values.yaml` | Keycloak realm configuration for Java 11/21 MOSIP platform profiles — 2 clients (`mosip-pms-client`, `mpartner-default-auth`) |
| `keycloak-esignet-init-values.yaml` | Keycloak realm configuration for **eSignet standalone** — full mosip realm with `realm_config`, 30+ roles, 6 client scopes, and 5 clients (`mosip-pms-client`, `mpartner-default-auth`, `mosip-ida-client`, `mosip-deployment-client`, `mpartner-default-mobile`). Mirrors `esignet/deploy/keycloak/keycloak-init-values.yaml`. Used by `dsf/esignet/external-dsf.yaml` (`esignet-keycloak-init` at priority -11 in keycloak ns). |
| `keycloak-signup-init-values.yaml` | Keycloak realm configuration for signup (mosip-signup-client) |
| `softhsm-esignet-values.yaml` | SoftHSM for esignet namespace |
| `softhsm-esignet-{cre,qa11,sunbird}-values.yaml` | SoftHSM for esignet-cre/qa11/sunbird — identical config; separate files give each namespace an independent PVC and pin secret |
| `softhsm-mock-identity-system-values.yaml` | SoftHSM for mock identity |
| `esignet-plugin-values.yaml` | Plugin 1 (mock) — captcha `secretKeyRef` active; plugin 2/3 sections commented out |
| `esignet-cre-plugin-values.yaml` | Plugin 2 (mosip-identity) — captcha + all IDA service URLs active; overrides full `extraEnvVars` list (SOFTHSM_ESIGNET_SECURITY_PIN references `esignet-softhsm-cre`); used by `esignet-cre` |
| `esignet-qa11-plugin-values.yaml` | Plugin 2 (mosip-identity) — identical to cre; SOFTHSM_ESIGNET_SECURITY_PIN references `esignet-softhsm-qa11`; used by `esignet-qa11` |
| `esignet-sunbird-plugin-values.yaml` | Plugin 3 (sunbird-rc) — captcha + sunbird registry URL + `NoOpKeyBinder`; overrides full `extraEnvVars` list (SOFTHSM_ESIGNET_SECURITY_PIN references `esignet-softhsm-sunbird`); used by `esignet-sunbird` |
| `esignet-apitestrig-values.yaml` | Shared values for all 4 esignet apitestrig releases — enables `mosipdev/apitest-esignet:develop` image; `extraEnvVarsCM`: `[s3, keycloak-host, db, apitestrig, esignet-global]`; `extraEnvVarsSecret` defaults overridden per-release in DSF via indexed `set:` |
| `esignet-signup-apitestrig-values.yaml` | Values for signup apitestrig — `mosipid/apitest-esignet-signup:1.2.2` image; same CM pattern |
| `signup-uitestrig-values.yaml` | Values for signup UI testrig — `mosipdev/uitest-signup:develop` image; `extraEnvVarsCM`: `[s3, keycloak-host, db, uitestrig]` |
| `config-server-values.yaml` | Git repo config for Spring Cloud Config Server (MOSIP platform profiles) |
| `config-server-esignet-values.yaml` | Config-server values for **eSignet standalone** — gitRepo: `esignet-config` @ `develop`; all env vars use `configMapKeyRef`/`secretKeyRef` (no literals); domain values from `esignet-global` CM created by preinstall hook |
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
| `helmsman_esignet.yml` | Manual / push to esignet DSF | Deploy eSignet stack; auto-triggers `helmsman_signup.yml` when `profile=esignet` and deploy succeeds |
| `helmsman_signup.yml` | Auto (from esignet workflow, `profile=esignet`) / Manual / push to signup DSF | Deploy signup stack (kernel, signup-service, signup-ui); requires esignet-dsf=completed label |
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

| Secret | Format | Used by |
|---|---|---|
| `MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY` | Base64 encoded PEM | Injected as `env:` in workflow → `mock-relying-party-service-preinstall.sh` → K8s secret `mock-relying-party-private-key-jwk` |
| `MOCK_RELYING_PARTY_JWE_PRIVATE_KEY` | Base64 encoded PEM | Injected as `env:` in workflow → `mock-relying-party-service-preinstall.sh` → K8s secret `jwe-userinfo-service-secrets` |
| `ESIGNET_CAPTCHA_SITE_KEY` | Plain text | captcha secret in esignet ns |
| `ESIGNET_CAPTCHA_SECRET_KEY` | Plain text | captcha secret in esignet ns |
| `ESIGNET_CRE_CAPTCHA_SITE_KEY` | Plain text | captcha secret for esignet-cre ns (esignet standalone only) |
| `ESIGNET_CRE_CAPTCHA_SECRET_KEY` | Plain text | captcha secret for esignet-cre ns (esignet standalone only) |
| `ESIGNET_QA11_CAPTCHA_SITE_KEY` | Plain text | captcha secret for esignet-qa11 ns (esignet standalone only) |
| `ESIGNET_QA11_CAPTCHA_SECRET_KEY` | Plain text | captcha secret for esignet-qa11 ns (esignet standalone only) |
| `ESIGNET_SUNBIRD_CAPTCHA_SITE_KEY` | Plain text | captcha secret for esignet-sunbird ns (esignet standalone only) |
| `ESIGNET_SUNBIRD_CAPTCHA_SECRET_KEY` | Plain text | captcha secret for esignet-sunbird ns (esignet standalone only) |
| `CRE_KEYCLOAK_ADMIN_PASSWORD` | Plain text | Keycloak admin password for CRE env — used by `esignet-cre-preinstall.sh` to fetch all client secrets via Keycloak REST API into `keycloak-client-secrets-cre` |
| `QA11_KEYCLOAK_ADMIN_PASSWORD` | Plain text | Keycloak admin password for QA11 env — used by `esignet-qa11-preinstall.sh` into `keycloak-client-secrets-qa11` |
| `CRE_POSTGRES_PASSWORD` | Plain text | Postgres superuser password for CRE env — creates `postgres-postgresql-cre` in esignet-cre ns |
| `QA11_POSTGRES_PASSWORD` | Plain text | Postgres superuser password for QA11 env — creates `postgres-postgresql-qa11` in esignet-qa11 ns |

> **How secrets reach hook scripts**: `helmsman_esignet.yml` maps GitHub secrets to workflow `env:` variables. Helmsman executes hook scripts as subprocesses of that workflow step, so all `env:` vars are available as shell env vars in every hook. To run hooks locally, export them manually: `export MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY=$(base64 < client-key.pem)`

**Signup deployment (`helmsman_signup.yml`) only:**

| Secret | Format |
|---|---|
| `MOSIP_SIGNUP_CAPTCHA_SITE_KEY` | Plain text |
| `MOSIP_SIGNUP_CAPTCHA_SECRET_KEY` | Plain text |

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
      domainConfig.installation-domain: "${domain_name}"
```

#### Compatible with ArgoCD / PipeCD / FluxCD

All GitOps tools support `valuesFiles` + `parameters` natively — `domainConfig` as a map works cleanly with all of them because it uses standard Helm scalar merge semantics.

#### Chart ownership rule

| Chart | Approach | Notes |
|---|---|---|
| `esignet` | `domainConfig: {}` + `{{- range }}` loop in `deployment.yaml` | 9 domain vars (8 Spring uppercase + `installation-domain`); PKCS12 keystore type still uses `extraEnvVarsAdditional[0]` (non-domain var) |
| `signup-service` | `domainConfig: {}` + `{{- range }}` loop | 2 domain vars (`ESIGNET_HOST`, `SIGNUP_HOST`) |
| `mock-identity-system` | `domainConfig: {}` + `{{- range }}` loop | Domain vars as needed; initContainer uses `MOSIP_API_INTERNAL_HOST` for SSL cert |
| `mock-relying-party-service` | `domainConfig: {}` + `{{- range }}` loop | Main container still uses `--set mock_relying_party_service.*` for app URLs; `domainConfig` is used by the initContainer (`MOSIP_API_INTERNAL_HOST` for SSL cert) |
| `partner-onboarder` (`mosip-onboarding/helm/`) | `domainConfig: {}` + `{{- range }}` loop in `jobs.yaml` | 6 vars: `mosip-api-internal-host`, `mosip-api-host`, `mosip-esignet-host`, `mosip-esignet-insurance-host`, `mosip-resident-host`, `installation-domain` — all lowercase-hyphen (Linux env, not Spring). `installation-domain` = `${domain_name}` root domain, used by `default.sh` to build redirect/logo URIs |
| `oidc-ui` | No `domainConfig` — uses `--set istio.hosts[0]` and `--set oidc_ui.configmaps.*` | These are Istio/ConfigMap resources, not Spring env vars |
| `mock-relying-party-ui` | No `domainConfig` — uses `--set mock_relying_party_ui.*` | Frontend configmap entries, not Spring env vars |
| `config-server` (published external chart) | Write the **complete** `envVariables` list into a runtime YAML override file (via `mktemp`) and pass as `-f "$override_file"` | Cannot modify chart source — `domainConfig` not available. List replacement means the override file must contain every entry, including domain values. See `deploy/config-server/install.sh` |
| `keycloak` (published external chart) | Domain values filled directly in the committed `deploy/keycloak/values.yaml` per branch | Cannot modify chart source |
| `pms-partner` / `pms-policy` (published external charts) | No `domainConfig` — uses `--set istio.gateways[0]` and `--set istio.corsPolicy.allowOrigins[0].prefix` | Charts create VirtualService only — no Gateway template. Gateway must be created separately via preInstall hook. `pms-policy` shares the `pms-partner` gateway (same gateway name in both VS configs). Setting `istio.gateways[0]` alone replaces the default 2-gateway list (`istio-system/public` + `istio-system/internal`) with the single custom gateway |

#### Helm template iteration block (in each owned chart's `deployment.yaml`, or `jobs.yaml` for partner-onboarder)

```yaml
{{- range $key, $val := .Values.domainConfig }}
- name: {{ $key }}
  value: {{ $val | quote }}
{{- end }}
```

Placed after the `extraEnvVarsAdditional` block (esignet) or `extraEnvVars` block (signup-service, mock-identity-system, mock-relying-party-service).

#### initContainer `mosip-api-internal-host` wiring

The `cacerts` initContainer fetches the internal API host's SSL cert using `env | grep "mosip-api-internal-host"`. This is wired to `domainConfig.MOSIP_API_INTERNAL_HOST` via a template expression in `values.yaml` (not a static value, not `envFrom: configMapRef`):

```yaml
initContainers:
  - env:
      - name: ENABLE_INSECURE
        value: "true"
      - name: mosip-api-internal-host
        value: '{{ index .Values.domainConfig "MOSIP_API_INTERNAL_HOST" | default "" }}'
```

`common.tplvalues.render` (used in `deployment.yaml` to render `initContainers`) applies `tpl` to the YAML, so the `{{ }}` expression is evaluated at render time. Charts: `esignet`, `mock-identity-system`, `mock-relying-party-service`, `signup-service`.

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

**Helmsman DSF plugin configuration** (eSignet standalone `dsf/esignet/esignet-dsf.yaml`):
- `pluginNameEnv` and `pluginUrlEnv` are set directly in each app's `set:` block in the DSF
- Each namespace has its own `valuesFile:` with the appropriate plugin's `extraEnvVarsAdditional` entries active:
  - `esignet` → `utils/esignet-plugin-values.yaml` (plugin 1, mock — no IDA URLs needed)
  - `esignet-cre` → `utils/esignet-cre-plugin-values.yaml` (plugin 2, mosip-identity — IDA URLs active)
  - `esignet-qa11` → `utils/esignet-qa11-plugin-values.yaml` (plugin 2, mosip-identity — IDA URLs active)
  - `esignet-sunbird` → `utils/esignet-sunbird-plugin-values.yaml` (plugin 3, sunbird-rc — registry URL active)
- Update IDA/Sunbird URLs in the respective values file before deploying non-mock plugins
- `metrics.serviceMonitor.enabled: "false"` — set to `"true"` if Prometheus Service Monitor Operator is deployed
- `extraEnvVarsCM[1]: "kafka-config"` — kafka is deployed as part of external-dsf for standalone profile; currently commented out in the DSF (`#extraEnvVarsCM[1]: "kafka-config"`) — uncomment if your eSignet config requires kafka event publishing

**Partner onboarder selection** — both disabled by default, enable the one matching your plugin:
- `esignet-mock-rp-onboarder` (module: `mock-rp-oidc`) — for plugin 1 (mock) and plugin 3 (sunbird-rc); restarts `mock-relying-party-service` after completion
- `esignet-misp-onboarder` (module: `esignet`) — for plugin 2 (mosip-identity) only; restarts `esignet` to pick up MISP license key
- Each has its own preinstall hook: MISP uses `esignet-misp-onboarder-preinstall.sh` (extra cleanup of stale MISP artifacts); mock-rp uses `esignet-mock-rp-onboarder-preinstall.sh`
- Both preinstall hooks disable Istio injection on the esignet namespace before the Job runs (Job pods with Istio sidecars never reach Completed state); both postinstall hooks re-enable it after the Job completes

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
- **SoftHSM secret name follows the Helm release name**: the softhsm chart creates a secret named `<release-name>` (e.g. release `esignet-softhsm-cre` → secret `esignet-softhsm-cre`). The esignet chart's default `extraEnvVars` references `esignet-softhsm` — which only exists in the main esignet namespace. For cre/qa11/sunbird, the full `extraEnvVars` list is overridden in each plugin values file so `SOFTHSM_ESIGNET_SECURITY_PIN` references the correct release-named secret (`esignet-softhsm-cre`, `esignet-softhsm-qa11`, `esignet-softhsm-sunbird`). Do NOT use `fullnameOverride` in softhsm values files — it renames the share ConfigMap too, breaking the name convention for all downstream consumers
- **postgres-config is copied with esignet default DB values then patched per namespace**: `esignet-preinstall.sh` copies `postgres-config` from the postgres ns (which carries `mosip_esignet`/`esignetuser` values). Each cre/qa11/sunbird preinstall hook then runs `kubectl patch configmap postgres-config --type merge` to override `database-name` and `database-username` with env-specific values (e.g. `mosip_esignet_cre`/`esignetuser_cre`). The patch runs after the copy so only the two differing keys change, preserving host/port
- **`global` CM replaced by `esignet-global` for cre/qa11 and pms charts**: the esignet chart defaults include `extraEnvVarsCM: [global, config-server-share]` which causes `configmap "global" not found` in esignet-cre/qa11 and pms-partner/policy namespaces. These are overridden in `esignet-dsf.yaml` via indexed `extraEnvVarsCM[N]` keys: `extraEnvVarsCM[1]: esignet-global` + `extraEnvVarsCM[2]: esignet-config-server-share` for esignet-cre/qa11; `extraEnvVarsCM[0]: esignet-global` + `extraEnvVarsCM[1]: esignet-config-server-share` for pms-partner/policy. **Each namespace creates its own `esignet-global`** — cre/qa11/sunbird preinstall hooks `kubectl create configmap ... | kubectl apply -f -` directly in the target ns (idempotent). All keys use `${domain_name}`; only `mosip-esignet-host` and `mosip-signup-host` differ per namespace. Do NOT copy from esignet ns — the main esignet CM has `esignet.${domain_name}` which is wrong for cre/qa11/sunbird. `esignet-config-server-share` is still copied by `config-server-esignet-postinstall.sh`
- `extraEnvVars` in Helm values is a **list** — Helm replaces lists on `-f` merge, wiping all `configMapKeyRef`/`secretKeyRef` entries. Never try to partially override `extraEnvVars` via a second values file. Domain vars use the `domainConfig` map instead (merges cleanly); PKCS12 keystore type and other conditional vars use `extraEnvVarsAdditional` (base is `[]`, replacing empty list loses nothing)
- Domain values for `esignet`, `signup-service`, `mock-identity-system`, `mock-relying-party-service` come from committed `domain-values.yaml` via `-f domain-values.yaml`. Do **not** add domain prompts or `--set domainConfig.*` to install scripts — edit the committed file instead
- `oidc-ui` and `mock-relying-party-ui` do **not** use `domainConfig` — they configure Istio hosts and app-specific configmap values via chart-specific `--set` paths; these are not Spring env vars
- `mock-relying-party-service/templates/deployment.yaml` had a pre-existing volumes indentation bug: when `enable_insecure=true`, the static volumes (`mock-relying-party-service` ConfigMap, `conf-file`) were indented at 8 spaces while the cacerts volume was at 6, causing YAML parse failure. Fixed: all volumes list items are now at 6 spaces (consistent with `enable_insecure` cacerts volume)
- **`ESIGNET_AUD_URL` must match `MOSIP_ESIGNET_HOST`**: in `mock-relying-party-service-{cre,qa11,sunbird}`, the `ESIGNET_AUD_URL` hostname must exactly match the public-facing `MOSIP_ESIGNET_HOST` set for that namespace. For cre the public host is `esignet-mosipid-cre.${domain_name}` and for qa11 it is `esignet-mosipid-qa11.${domain_name}` — using `esignet-cre.${domain_name}` / `esignet-qa11.${domain_name}` will cause token audience validation failures.
- **PMS Gateway TLS secrets must exist before deploy**: `pms-partner-cre-tls` and `pms-partner-qa11-tls` must be present in `istio-system` before the gateway preInstall hook runs — provision these via cert-manager or import manually beforehand
- **PMS policy has no gateway of its own**: `pms-policy-cre` and `pms-policy-qa11` VS both reference the corresponding `pms-partner-*-gateway`. If pms-partner is disabled or its hook hasn't run, pms-policy traffic will fail
- PVCs/PVs are **not deleted** on `helm delete` — must be manually cleaned up
- `set -e` / strict flags are placed after function definitions — functionally correct but non-obvious
- Temp env-var files (`mktemp`) from plugin config in `esignet-with-plugins/install.sh` are not cleaned up after install
- Chart versions are hardcoded to `0.0.1-develop` — update before production use
- Istio injection is **disabled** in the `captcha` and `keycloak` namespaces
- `helmsman_esignet.yml` `workflow-caller` job requires a `GH_INFRA_PAT` **Environment secret** with `actions:write` scope — without it the signup auto-trigger will fail even though eSignet itself deployed successfully
- `signup-dsf.yaml` apps are all `enabled: false` by default — you must explicitly enable each component (e.g. `authmanager`, `signup`, `signup-ui`) in the DSF before running the workflow
- `kernel-preinstall.sh` creates a `domain-config` ConfigMap in the `kernel` namespace using `MOSIP_API_HOST`, `MOSIP_API_INTERNAL_HOST`, and `MOSIP_IAM_EXTERNAL_HOST` env vars — these are set by the workflow from `domain_name`; if running locally, export all three before invoking the hook
- `esignet-keycloak-init` (eSignet standalone) runs in the **keycloak namespace** as part of **external-dsf** (priority -11, after keycloak at -12). The chart creates `keycloak-host` CM and `keycloak-client-secrets` secret directly in keycloak ns — all other required resources (`keycloak` secret, `keycloak-env-vars` CM) already exist there from the bitnami chart, so the preInstall hook requires no copying. The postInstall fans `keycloak-host`, `keycloak-env-vars`, `keycloak`, and `keycloak-client-secrets` to all 4 esignet namespaces. By the time esignet-dsf runs, all keycloak resources are pre-populated in every esignet namespace. Do NOT add `kubectl delete keycloak-host` or `kubectl delete keycloak-client-secrets` to the preInstall — these are helm-managed resources in keycloak ns; `helm delete` removes them cleanly.
- `utils/keycloak-esignet-init-values.yaml` must match `esignet/deploy/keycloak/keycloak-init-values.yaml` — it is the authoritative source for the eSignet standalone Keycloak realm config. `utils/keycloak-init-values.yaml` is for Java 11/21 MOSIP platform profiles only (2 clients, no `realm_config`). Do not mix them up.
- **MinIO re-deploy fails with PASSWORDS ERROR**: Bitnami charts require the existing `auth.rootPassword` on `helm upgrade`. Fix: `helmsman_external.yml` "Mask sensitive secrets" step fetches the password from the `minio` secret and exports it as `MINIO_ROOT_PASSWORD` via `$GITHUB_ENV`. All three `external-dsf.yaml` files pass it via `auth.rootPassword: "${MINIO_ROOT_PASSWORD}"`. On fresh install the variable is empty and Bitnami auto-generates the password. On re-deploy the existing password is passed through so upgrade succeeds. The `helmsman_testrigs.yml` "Get MinIO root password" step also reads this secret (for `${MINIO_ROOT_PASSWORD}` substitution in `testrigs-dsf.yaml`). **MinIO chart secret is named `minio` in the `minio` namespace** (`kubectl -n minio get secret minio`) — do NOT look for a secret named `s3`; the `s3` secret in the `s3` namespace is a derived secret created by `s3-setup.sh` postInstall hook and has a different key (`s3-user-secret`, not `root-password`).
- **postgres-init chart version is `0.0.1-develop`** (not `12.0.1`) — the published `12.0.1` chart has per-service hardcoded templates with fixed `MOSIP_DB_NAME` values and cannot support multiple esignet DBs. `0.0.1-develop` uses a single `job.yaml` that iterates over `databases:` map with configurable `scriptsDir`, `dbName`, and `dbUser` per entry. Do not revert to `12.0.1`
- **Dynamic DB per namespace**: `scriptsDir` is fixed and must match the repo folder (`mosip_esignet`, `mosip_mockidentitysystem`); `dbName` and `dbUser` are customized per namespace (e.g. `mosip_esignet_cre` / `esignetuser_cre`). Adding a new namespace requires a new `databases.*` entry in the DSF with a unique `dbName` and `dbUser`
- **New database entries MUST include both `su` block AND `defaultDb`**: `0.0.1-develop` chart accesses `$dbVal.su.secret.name` for every enabled entry AND uses `defaultDb` as the initial psql connection target. Entries that exist in chart defaults (e.g. `mosip_esignet`, `mosip_mockidentitysystem`) inherit these automatically; NEW entries (e.g. `mosip_esignet_cre`, `mosip_esignet_qa11`, `mosip_esignet_sunbird`) must explicitly set all of: `databases.<key>.su.user: "postgres"`, `databases.<key>.su.secret.name: "postgres-postgresql"`, `databases.<key>.su.secret.key: "postgres-password"`, `databases.<key>.defaultDb: "postgres"`. Missing `su` block → `nil pointer evaluating interface {}.secret` at template render. Missing `defaultDb` → `deploy.sh` connects to the wrong database for schema setup, causing `DROP SCHEMA`/`CREATE SCHEMA` to run in an existing DB (corrupting it), and then DDL in the target DB fails with `permission denied to create "pg_catalog.client_detail"` because the schema was never created there.
- **postgres-init image must be new enough to support `DB_SCRIPTS_DIR`**: The `0.0.1-develop` chart sets `DB_SCRIPTS_DIR` in the ConfigMap to decouple the scripts folder from the DB name. If the deployed `mosipqa/postgres-init:develop` image is old (pre-`DB_SCRIPTS_DIR` support), the script falls back to using `MOSIP_DB_NAME` as the scripts directory — causing `cd: db_scripts/mosip_esignet_cre: No such file or directory`. The DSF explicitly sets `image.repository: "mosipqa/postgres-init"`, `image.tag: "develop"`, `image.pullPolicy: "Always"` to force a fresh pull on every Job run. Confirm the image is the new version by checking the log: new image prints `"Successfully cloned"` (correct spelling) and `"Executing db_script for ... (scripts dir: ...)"` before the cd.
- **eSignet standalone DB port is `5432`** (not `5433`) — all `postgres-init` entries in `dsf/esignet/external-dsf.yaml` use port `5432`. The Java 11/21 profiles use `5433` (custom port). Do not copy port values across profiles. Both ports are now parameterised: `${esignet_db_port}` for the eSignet profile, `${db_port}` for MOSIP platform profiles. Set `vars.ESIGNET_DB_PORT=5432` and `vars.DB_PORT=5433` in the GitHub Environment.
- **`--skip-releases` flag does not exist in Helmsman v3.17.1** — use `-exclude-target <release>` (one flag per release) to exclude specific apps. The softhsm skip logic in `helmsman_esignet.yml` builds the argument as `-exclude-target esignet-softhsm -exclude-target esignet-softhsm-cre ...` inside the loop rather than a comma-separated list.
- **Testrigs workflow must use `--keep-untracked-releases`** — without this flag, Helmsman sees releases deployed by `esignet-dsf.yaml` (esignet, oidc-ui, softhsm, mock-relying-party-service, etc.) as "Helmsman-managed but not in testrigs-dsf.yaml" and **deletes them**. Always pass `--keep-untracked-releases` when running any DSF that covers only a subset of deployed releases.
- **`signup` namespace must be declared in `namespaces:` of `testrigs-dsf.yaml`** — `esignet-signup-apitestrig` deploys into the `signup` namespace; Helmsman validation fails if it is not listed in the `namespaces:` block even though the namespace already exists in the cluster.
- **`helmsman_testrigs.yml` requires `cre_domain_name` and `qa11_domain_name` for the `esignet` profile** — `testrigs-dsf.yaml` uses `${cre_domain_name}` and `${qa11_domain_name}` for CRE/QA11 apitestrig `db-server` and `mosip_components_base_urls`. Set `vars.CRE_DOMAIN_NAME` and `vars.QA11_DOMAIN_NAME` in the GitHub Environment, or provide them as workflow inputs. The validate-inputs job enforces this when `profile=esignet`.
- **`helmsman_esignet.yml` validates 4 extra secrets for the `esignet` profile** — `CRE_POSTGRES_PASSWORD`, `QA11_POSTGRES_PASSWORD`, `CRE_KEYCLOAK_ADMIN_PASSWORD`, `QA11_KEYCLOAK_ADMIN_PASSWORD` are checked in the "Validate required secrets" deploy step (inside `if [ "$PROFILE" = "esignet" ]`). These are all Environment secrets (not vars). The workflow fails fast before Helmsman runs if any are missing.

---

## Local Helmsman Testing

```bash
export KUBECONFIG=~/.kube/config
export WORKDIR=$(pwd)/Helmsman

# Preview (note: will fail for MOSIP due to cross-namespace dependencies)
helmsman --dry-run -f Helmsman/dsf/esignet/esignet-dsf.yaml

# Apply eSignet
helmsman --apply -f Helmsman/dsf/esignet/esignet-dsf.yaml

# Apply Signup (run after esignet-dsf apply succeeds)
export domain_name=sandbox.example.net
helmsman --apply -f Helmsman/dsf/esignet/signup-dsf.yaml

# Destroy
helmsman --destroy -f Helmsman/dsf/esignet/esignet-dsf.yaml
helmsman --destroy -f Helmsman/dsf/esignet/signup-dsf.yaml
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

# Signup-specific
kubectl get pods -n signup
kubectl get pods -n kernel
kubectl get virtualservice -n signup
helm list -n signup
helm list -n kernel

# Check namespace label set by Signup DSF completion
kubectl get ns default --show-labels | grep signup-dsf

# View signup logs
kubectl logs -n signup -l app=signup -f
```
